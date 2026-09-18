import Foundation
import Infrastructure
import Observation

@MainActor
@Observable
final class ScreenRecordingModel {
    struct TerminationApprovalIdentity: Equatable {
        let sessionID: UUID
        let artifactID: UUID?
        let options: ScreenRecordingOptions
    }
    enum Phase: Equatable { case setup, preparing, selecting, recording, stopping, cancelling, finalizing, review, exporting, discardFailed }
    let sessionLabel: String?
    var options = ScreenRecordingOptions()
    private(set) var activeOptions: ScreenRecordingOptions?
    private(set) var phase: Phase = .setup
    private(set) var progress = ScreenRecordingProgress(duration: 0, fileBytes: 0)
    private(set) var artifact: ScreenRecordingArtifact?
    private(set) var message: String?
    private(set) var needsStopRetry = false
    private(set) var hasSavedCopy = false
    var showsCloseConfirmation = false
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onCloseCancelled: (() -> Void)?
    @ObservationIgnored var onChooseExport: (() -> Void)?
    @ObservationIgnored private let capture: any ScreenRecordingCapturing
    @ObservationIgnored private let storage: any ScreenRecordingStoring
    @ObservationIgnored private let limits: ScreenRecordingLimits
    @ObservationIgnored private var draft: ScreenRecordingDraft?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var cancellation: Task<Void, Never>?
    @ObservationIgnored private var exportWork: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var closeAfterStop = false
    @ObservationIgnored private var closeAfterExport = false
    @ObservationIgnored private var closeAfterDiscard = false
    @ObservationIgnored private var terminationClose = false

    init(capture: any ScreenRecordingCapturing, storage: any ScreenRecordingStoring, sessionLabel: String? = nil,
         limits: ScreenRecordingLimits = ScreenRecordingLimits()) {
        self.capture = capture; self.storage = storage; self.sessionLabel = sessionLabel; self.limits = limits
    }

    var terminationApprovalIdentity: TerminationApprovalIdentity? {
        guard (phase == .setup && draft == nil) || (phase == .review && hasSavedCopy) else { return nil }
        return TerminationApprovalIdentity(sessionID: generation, artifactID: artifact?.draft.id, options: options)
    }

    var isCapturing: Bool { [.selecting, .recording, .stopping, .cancelling].contains(phase) }
    var hasActiveOrUnsavedRecording: Bool { phase != .setup || draft != nil }
    var canStart: Bool { phase == .setup && draft == nil && cancellation == nil }
    var isCompact: Bool { [.recording, .stopping, .cancelling, .finalizing].contains(phase) }
    var audioDescription: String { (activeOptions ?? options).audio == .none ? "Audio off" : "System audio on · Microphone off" }
    var durationText: String {
        let safeDuration = progress.duration.isFinite ? progress.duration : 0
        let seconds = Int(min(36_000, max(0, safeDuration)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: progress.fileBytes, countStyle: .file) }

    func start() {
        guard canStart else { return }
        let settings = options
        let id = UUID()
        generation = id
        activeOptions = settings
        message = nil
        needsStopRetry = false
        hasSavedCopy = false
        progress = ScreenRecordingProgress(duration: 0, fileBytes: 0)
        phase = .preparing
        operation = Task { [weak self, capture, storage, limits] in
            guard let self else { return }
            do {
                let destination = try await storage.prepare(container: settings.container, limits: limits)
                guard generation == id else { try await storage.discard(destination); return }
                draft = destination
                try Task.checkCancellation()
                phase = .selecting
                let events = try await capture.begin(options: settings, destination: destination, limits: limits)
                try Task.checkCancellation()
                var terminal = false
                recordingEvents: for await event in events {
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    switch event {
                    case .started: if phase == .selecting { phase = .recording }
                    case .progress(let progress): self.progress = progress
                    case .stopping: if phase != .cancelling { phase = .stopping }
                    case .stopNeedsAttention:
                        needsStopRetry = true
                        message = "macOS could not confirm that capture stopped. Retry Stop, or stop sharing from the recording indicator in the menu bar."
                    case .finished(let summary):
                        terminal = true
                        phase = .finalizing
                        let result = try await storage.finalize(destination, summary: summary, limits: limits)
                        try Task.checkCancellation()
                        guard generation == id else { return }
                        artifact = result
                        progress = ScreenRecordingProgress(duration: result.summary.duration, fileBytes: result.summary.fileBytes)
                        phase = .review
                        message = Self.limitMessage(summary.stopReason)
                        if closeAfterStop { showsCloseConfirmation = true }
                        break recordingEvents
                    case .failed(let error): throw error
                    case .cancelled:
                        terminal = true
                        try await removeDraft()
                        phase = .setup
                        activeOptions = nil
                        if closeAfterStop { closeAfterStop = false; onClose?() }
                        break recordingEvents
                    }
                }
                if !terminal, !Task.isCancelled { throw ScreenRecordingError.interrupted }
            } catch {
                guard generation == id, phase != .cancelling else { return }
                await capture.cancel()
                let errorMessage = error is CancellationError ? nil : Self.description(error)
                do {
                    try await removeDraft()
                    phase = .setup
                    activeOptions = nil
                    message = errorMessage
                } catch {
                    phase = .discardFailed
                    message = "The temporary recording could not be removed. Retry Discard before starting another recording."
                }
                if closeAfterStop { closeAfterStop = false; terminationClose = false; onCloseCancelled?() }
            }
            if generation == id { operation = nil }
        }
    }

    func stop() {
        guard [.recording, .stopping, .cancelling].contains(phase) else { return }
        if phase != .cancelling { phase = .stopping }
        needsStopRetry = false
        message = nil
        let id = generation
        Task { [weak self, capture] in
            guard let self, generation == id, isCapturing else { return }
            await capture.stop()
        }
    }

    /// Cancellation waits for a pending prepare/begin/finalize and native stop before deleting its
    /// destination. A new operation remains disabled throughout that cleanup barrier.
    func discard(close: Bool = false) {
        guard phase != .exporting, cancellation == nil else { return }
        showsCloseConfirmation = false
        closeAfterStop = false
        closeAfterExport = false
        closeAfterDiscard = close
        phase = .cancelling
        let oldOperation = operation
        oldOperation?.cancel()
        cancellation = Task { [weak self, capture] in
            guard let self else { return }
            await oldOperation?.value
            await capture.cancel()
            do {
                try await removeDraft()
                generation = UUID()
                artifact = nil
                hasSavedCopy = false
                activeOptions = nil
                progress = ScreenRecordingProgress(duration: 0, fileBytes: 0)
                phase = .setup
                message = nil
                needsStopRetry = false
                cancellation = nil
                operation = nil
                if closeAfterDiscard || closeAfterStop {
                    closeAfterDiscard = false; closeAfterStop = false; onClose?()
                }
            } catch {
                phase = .discardFailed
                message = "The temporary recording could not be removed. Retry Discard before closing."
                cancellation = nil
                onCloseCancelled?()
            }
        }
    }

    func requestExport(closeAfterSaving: Bool = false) {
        guard phase == .review, artifact != nil else { return }
        closeAfterExport = closeAfterSaving
        showsCloseConfirmation = false
        onChooseExport?()
    }

    func exportSelectionCancelled() {
        guard phase == .review else { return }
        closeAfterExport = false
        closeAfterStop = false
        terminationClose = false
        onCloseCancelled?()
    }

    func export(to destination: URL) {
        guard phase == .review, let artifact else { return }
        phase = .exporting
        message = nil
        exportWork = Task { [weak self, storage] in
            guard let self else { return }
            do {
                try await storage.export(artifact, to: destination)
                phase = .review
                hasSavedCopy = true
                message = "Recording saved. Your review stays here until you discard it or close this window."
                exportWork = nil
                if closeAfterExport {
                    closeAfterExport = false
                    if terminationClose { onClose?() }
                    else { discard(close: true) }
                }
            } catch {
                phase = .review
                message = "The recording could not be saved. Your video is still available to review and save again."
                closeAfterExport = false
                closeAfterStop = false
                terminationClose = false
                exportWork = nil
                onCloseCancelled?()
            }
        }
    }

    func requestClose(forTermination: Bool = false) {
        terminationClose = forTermination
        switch phase {
        case .setup:
            if draft == nil { onClose?() } else { showsCloseConfirmation = true }
        case .preparing, .selecting: discard(close: true)
        case .recording, .stopping:
            closeAfterStop = true
            stop()
        case .cancelling, .finalizing: closeAfterStop = true
        case .review:
            if hasSavedCopy {
                if forTermination { onClose?() } else { discard(close: true) }
            } else { showsCloseConfirmation = true }
        case .discardFailed: showsCloseConfirmation = true
        case .exporting:
            // An in-flight explicit Save finishes; quitting remains cancelled so its completion
            // cannot close a review whose save panel the person may still be considering.
            terminationClose = false
            onCloseCancelled?()
        }
    }

    func keepOpen() {
        showsCloseConfirmation = false
        closeAfterStop = false
        closeAfterExport = false
        terminationClose = false
        onCloseCancelled?()
    }

    func cancelTerminationClose() {
        guard terminationClose else { return }
        terminationClose = false
        showsCloseConfirmation = false
        closeAfterStop = false
        closeAfterExport = false
        closeAfterDiscard = false
    }

    func waitForOperationForTesting() async { await operation?.value }
    func waitForCleanup() async { await cancellation?.value }
    func waitForCancellationForTesting() async { await waitForCleanup() }
    func waitForExportForTesting() async { await exportWork?.value }

    private func removeDraft() async throws {
        guard let draft else { return }
        try await storage.discard(draft)
        self.draft = nil
        artifact = nil
    }

    private static func limitMessage(_ reason: ScreenRecordingStopReason) -> String? {
        switch reason {
        case .user: nil
        case .durationLimit: "Stopped at the 10-minute recording limit. Review and save this video before starting another."
        case .sizeLimit: "Stopped near the recording size limit. Review and save this video before starting another."
        }
    }

    private static func description(_ error: Error) -> String {
        switch error as? ScreenRecordingError {
        case .busy: "Another recording or content picker is already in use. Finish it and try again."
        case .selectionUnavailable: "The macOS content picker is unavailable. Finish any other content selection and try again."
        case .selectionInvalid: "That content cannot be recorded. Choose another window or display."
        case .permissionRequired: "macOS did not allow this recording. Choose content again and approve sharing. If access is restricted, review Screen & System Audio Recording in System Settings."
        case .unsupportedConfiguration: "This video format is unavailable on this Mac. Try MP4 with H.264."
        case .insufficientDiskSpace: "Recording needs at least 768 MB of available storage. Free some space and try again."
        case .artifactTooLarge: "The finalized video exceeded the 512 MB safety limit and was discarded. Try a shorter recording or 720p."
        case .invalidArtifact, .finalizationFailed: "The video could not be finalized for playback. Try recording again."
        case .storageUnavailable: "Private recording storage is unavailable. Check available storage and try again."
        case .interrupted: "Recording was interrupted by macOS. Try choosing the content again."
        default: "Recording could not be completed. Choose the content and try again."
        }
    }
}
