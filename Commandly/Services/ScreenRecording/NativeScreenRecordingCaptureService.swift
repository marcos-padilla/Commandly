import Foundation
import Infrastructure
import ScreenCaptureKit
import Synchronization

/// Owns the process-wide system picker on MainActor for the entire selected recording. The exact
/// consent-bearing native filter transfers directly from the callback into the native worker.
@MainActor
final class NativeScreenRecordingCaptureService: ScreenRecordingCapturing {
    private var operationID: UUID?
    private var worker: NativeScreenRecordingWorker?
    private var observer: ScreenRecordingSystemPickerObserver?
    private var previousConfiguration: SCContentSharingPickerConfiguration?
    private var continuation: AsyncStream<ScreenRecordingEvent>.Continuation?
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func begin(options: ScreenRecordingOptions, destination: ScreenRecordingDraft,
               limits: ScreenRecordingLimits) async throws -> AsyncStream<ScreenRecordingEvent> {
        try Task.checkCancellation()
        guard operationID == nil else { throw ScreenRecordingError.busy }
        let picker = SCContentSharingPicker.shared
        guard !picker.isActive, picker.isAvailable else { throw ScreenRecordingError.selectionUnavailable }
        let id = UUID()
        let stream = AsyncStream<ScreenRecordingEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        operationID = id
        continuation = stream.continuation
        stream.continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                Task { @MainActor in await self?.cancel(id: id) }
            }
        }
        let worker = NativeScreenRecordingWorker(options: options, destination: destination, limits: limits) { [weak self] event in
            Task { @MainActor in self?.received(event, id: id) }
        }
        self.worker = worker
        let observer = ScreenRecordingSystemPickerObserver(worker: worker)
        self.observer = observer
        previousConfiguration = picker.defaultConfiguration
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = options.source == .window ? [.singleWindow] : [.singleDisplay]
        configuration.allowsChangingSelectedContent = false
        if let bundleID = Bundle.main.bundleIdentifier { configuration.excludedBundleIDs = [bundleID] }
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true
        picker.present(using: options.source == .window ? .window : .display)
        return stream.stream
    }

    func stop() async { worker?.stop() }

    func cancel() async {
        guard let operationID else { return }
        await cancel(id: operationID)
    }

    private func cancel(id: UUID) async {
        guard operationID == id else { return }
        observer?.invalidate()
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
            worker?.cancel()
        }
    }

    private func received(_ event: ScreenRecordingEvent, id: UUID) {
        guard operationID == id else { return }
        continuation?.yield(event)
        switch event {
        case .finished, .failed, .cancelled:
            operationID = nil
            continuation?.finish()
            continuation = nil
            if let observer {
                observer.invalidate()
                let picker = SCContentSharingPicker.shared
                picker.remove(observer)
                picker.isActive = false
                if let previousConfiguration { picker.defaultConfiguration = previousConfiguration }
            }
            observer = nil
            previousConfiguration = nil
            worker = nil
            let waiters = cancellationWaiters
            cancellationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        case .started, .progress, .stopping, .stopNeedsAttention: break
        }
    }
}

nonisolated private final class ScreenRecordingSystemPickerObserver: NSObject, SCContentSharingPickerObserver, Sendable {
    private let claimed = Mutex(false)
    private let worker: NativeScreenRecordingWorker
    init(worker: NativeScreenRecordingWorker) { self.worker = worker }
    func invalidate() { claimed.withLock { $0 = true } }
    private func claim() -> Bool {
        claimed.withLock { state in guard !state else { return false }; state = true; return true }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil, claim() else { return }
        worker.cancel()
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        guard claim() else { return }
        worker.selectionFailed()
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil, claim() else { return }
        worker.selected(filter)
    }
}
