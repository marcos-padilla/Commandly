import CoreMedia
import Dispatch
import Foundation
import Infrastructure
import ScreenCaptureKit
import os

/// ScreenCaptureKit's native objects are confined to one lock-protected ownership region.
/// Callback parameters enter that region synchronously; queued work captures only this Sendable
/// owner. Native filter/stream/output objects never cross an actor or enter UI state. Encoder work
/// belongs to ScreenCaptureKit; this serial queue performs only configuration and lifecycle calls.
nonisolated final class NativeScreenRecordingWorker: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, Sendable {
    private struct State {
        var filter: SCContentFilter?
        var stream: SCStream?
        var output: SCRecordingOutput?
        var outputDetached = false
        var width = 0
        var height = 0
        var lifecycle = ScreenRecordingLifecycle()
        var latest = ScreenRecordingProgress(duration: 0, fileBytes: 0)
    }

    // SCContentSharingPicker's Objective-C delegate cannot declare a `sending` filter. This
    // native interop boundary retains that immutable selection under Apple's allocated lock:
    // we never change its properties, disable picker selection replacement, and never let a
    // filter/stream/output escape a locked region. Only the initial callback uses the unchecked
    // closure overload; ordinary operations use Sendable closures and return Sendable facts.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let options: ScreenRecordingOptions
    private let destination: ScreenRecordingDraft
    private let limits: ScreenRecordingLimits
    private let event: @Sendable (ScreenRecordingEvent) -> Void
    private let queue = DispatchQueue(label: "com.commandly.screen-recording", qos: .userInitiated)
    private let timer: DispatchSourceTimer

    init(options: ScreenRecordingOptions, destination: ScreenRecordingDraft, limits: ScreenRecordingLimits,
         event: @escaping @Sendable (ScreenRecordingEvent) -> Void) {
        self.options = options
        self.destination = destination
        self.limits = limits
        self.event = event
        timer = DispatchSource.makeTimerSource(queue: queue)
        super.init()
        timer.setEventHandler { [weak self] in self?.updateProgress() }
        timer.schedule(deadline: .distantFuture)
        timer.activate()
    }

    deinit { timer.cancel() }

    func selected(_ filter: SCContentFilter) {
        let accepted = state.withLockUnchecked { state in
            guard state.lifecycle.ended == false, state.filter == nil, state.stream == nil else { return false }
            state.filter = filter
            return true
        }
        if accepted { queue.async { [self] in configureAndStart() } }
    }

    func selectionFailed() { queue.async { [self] in finishWithoutCapture(.failed(.selectionUnavailable)) } }

    func stop() {
        state.withLock { $0.lifecycle.requestStop(.user, retry: true) }
        queue.async { [self] in issueStopIfReady() }
    }

    func cancel() {
        state.withLock { $0.lifecycle.cancelled = true; $0.lifecycle.requestStop(.user, retry: true) }
        queue.async { [self] in
            let wasIdle = state.withLock { $0.stream == nil && !$0.lifecycle.ended }
            if wasIdle { finishWithoutCapture(.cancelled) }
            else { issueStopIfReady() }
        }
    }

    private func configureAndStart() {
        let cancelled = state.withLock { $0.lifecycle.cancelled || $0.lifecycle.ended }
        if cancelled { finishWithoutCapture(.cancelled); return }
        do {
            try state.withLock { state in
                guard !state.lifecycle.cancelled, !state.lifecycle.ended else { throw CancellationError() }
                guard let filter = state.filter else { throw ScreenRecordingError.selectionInvalid }
                guard (options.source == .window && filter.style == .window)
                    || (options.source == .display && filter.style == .display) else {
                    throw ScreenRecordingError.selectionInvalid
                }
                let (width, height) = try ScreenRecordingNativeConfiguration.dimensions(
                    points: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale), resolution: options.resolution
                )
                let configuration = ScreenRecordingNativeConfiguration.stream(options: options, width: width, height: height)
                let recording = try ScreenRecordingNativeConfiguration.recording(options: options, outputURL: destination.url)
                let output = SCRecordingOutput(configuration: recording, delegate: self)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addRecordingOutput(output)
                state.width = width
                state.height = height
                state.stream = stream
                state.output = output
                state.filter = nil
                // Completion callbacks enqueue their sanitized values instead of reacquiring this
                // mutex inline. This remains safe even if a native completion arrives synchronously.
                stream.startCapture { [self] error in
                    let failure = error.map { ScreenRecordingNativeConfiguration.failure($0, fallback: .startFailed) }
                    queue.async { [self] in captureStartCompleted(failure) }
                }
            }
            timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
        } catch {
            finishWithoutCapture(error is CancellationError ? .cancelled : .failed(error as? ScreenRecordingError ?? .startFailed))
        }
    }

    private func captureStartCompleted(_ failure: ScreenRecordingError?) {
        if let failure {
            finishWithoutCapture(.failed(failure))
            return
        }
        state.withLock { if !$0.lifecycle.ended { $0.lifecycle.captureStarted = true } }
        publishStartedIfReady()
        issueStopIfReady()
    }

    private func publishStartedIfReady() {
        if state.withLock({ $0.lifecycle.claimStarted() }) { event(.started) }
    }

    private func updateProgress() {
        let progress: ScreenRecordingProgress? = state.withLock { state in
            guard !state.lifecycle.ended, state.lifecycle.outputStarted, let output = state.output else { return nil }
            let duration = output.recordedDuration.seconds
            let next = ScreenRecordingProgress(duration: duration.isFinite ? max(0, duration) : 0,
                                               fileBytes: max(0, Int64(output.recordedFileSize)))
            state.latest = next
            if state.lifecycle.stopReason == nil { state.lifecycle.stopReason = ScreenRecordingNativeConfiguration.limitReason(progress: next, limits: limits) }
            return next
        }
        if let progress { event(.progress(progress)) }
        if let reason = state.withLock({ $0.lifecycle.claimStopping() }) { event(.stopping(reason)) }
        issueStopIfReady()
    }

    private func issueStopIfReady() {
        state.withLock { state in
            guard !state.lifecycle.ended, state.lifecycle.stopReason != nil, state.lifecycle.captureStarted, !state.lifecycle.captureStopped,
                  !state.lifecycle.stopIssued, let stream = state.stream else { return }
            state.lifecycle.stopIssued = true
            stream.stopCapture { [self] error in
                let failure = error.map { ScreenRecordingNativeConfiguration.failure($0, fallback: .finalizationFailed) }
                queue.async { [self] in captureStopCompleted(failure) }
            }
        }
    }

    private func captureStopCompleted(_ failure: ScreenRecordingError?) {
        let needsAttention = state.withLock { $0.lifecycle.captureStopCompleted(failure) }
        if needsAttention {
            // If native capture shutdown fails, separately stop the recording output to limit
            // further disk writes. This does not certify capture shutdown: controls stay visible
            // and cancellation still waits for the stream to stop or the macOS sharing indicator.
            do {
                try state.withLock { state in
                    guard !state.outputDetached, let stream = state.stream, let output = state.output else { return }
                    try stream.removeRecordingOutput(output)
                    state.outputDetached = true
                }
            } catch {
                event(.stopNeedsAttention)
            }
            event(.stopNeedsAttention)
        }
        completeIfFinalized()
    }

    private func completeIfFinalized() {
        let result: ScreenRecordingEvent? = state.withLock { state in
            let summary = ScreenRecordingSummary(duration: state.latest.duration, fileBytes: state.latest.fileBytes,
                pixelWidth: state.width, pixelHeight: state.height, stopReason: state.lifecycle.stopReason ?? .user)
            guard let result = state.lifecycle.claimCompletion(summary: summary) else { return nil }
            state.filter = nil; state.stream = nil; state.output = nil
            return result
        }
        if let result { timer.cancel(); event(result) }
    }

    private func finishWithoutCapture(_ result: ScreenRecordingEvent) {
        let accepted = state.withLock { state in
            guard !state.lifecycle.ended else { return false }
            state.lifecycle.ended = true
            state.filter = nil
            state.stream = nil
            state.output = nil
            return true
        }
        if accepted { timer.cancel(); event(result) }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let identity = ObjectIdentifier(recordingOutput)
        queue.async { [self] in
            state.withLock { state in
                guard !state.lifecycle.ended, state.output.map(ObjectIdentifier.init) == identity else { return }
                state.lifecycle.outputStarted = true
            }
            publishStartedIfReady()
            issueStopIfReady()
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let identity = ObjectIdentifier(recordingOutput)
        let duration = recordingOutput.recordedDuration.seconds
        let progress = ScreenRecordingProgress(duration: duration.isFinite ? max(0, duration) : 0,
                                               fileBytes: max(0, Int64(recordingOutput.recordedFileSize)))
        queue.async { [self] in
            state.withLock { state in
                guard !state.lifecycle.ended, state.output.map(ObjectIdentifier.init) == identity else { return }
                state.latest = progress
                state.lifecycle.outputFinished = true
                state.lifecycle.requestStop(.user)
            }
            issueStopIfReady()
            completeIfFinalized()
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let identity = ObjectIdentifier(recordingOutput)
        let failure = ScreenRecordingNativeConfiguration.failure(error, fallback: .recordingFailed)
        queue.async { [self] in
            state.withLock { state in
                guard !state.lifecycle.ended, state.output.map(ObjectIdentifier.init) == identity else { return }
                state.lifecycle.outputFinished = true
                state.lifecycle.failure = failure
                state.lifecycle.requestStop(.user)
            }
            issueStopIfReady()
            completeIfFinalized()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let identity = ObjectIdentifier(stream)
        let userStopped = ScreenRecordingNativeConfiguration.isUserStop(error)
        let failure = ScreenRecordingNativeConfiguration.failure(error, fallback: .interrupted)
        queue.async { [self] in
            state.withLock { state in
                guard !state.lifecycle.ended, state.stream.map(ObjectIdentifier.init) == identity else { return }
                state.lifecycle.captureStopped = true
                if !userStopped { state.lifecycle.failure = failure }
                state.lifecycle.requestStop(.user)
            }
            completeIfFinalized()
        }
    }
}
