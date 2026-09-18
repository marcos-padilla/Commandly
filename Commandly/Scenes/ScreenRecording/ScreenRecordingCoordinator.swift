import Foundation
import Infrastructure

@MainActor
protocol ScreenRecordingPresenting: AnyObject {
    var hasActiveOrUnsavedRecording: Bool { get }
    func present(source: ScreenRecordingSource?)
    func stop()
}

@MainActor
protocol ScreenRecordingWindowPresenting: AnyObject {
    func present(model: ScreenRecordingModel, onClosed: @escaping () -> Void)
    func focus()
    func close()
}

/// One retained independent window: dismissing the launcher cannot hide/abandon an active capture.
/// A cancelled quit leaves the finalized video in review, and never silently resumes recording.
@MainActor
final class ScreenRecordingCoordinator: ScreenRecordingPresenting {
    private let capture: any ScreenRecordingCapturing
    private let storage: any ScreenRecordingStoring
    private let sessionLabel: String?
    private let makeWindow: () -> any ScreenRecordingWindowPresenting
    private var window: (any ScreenRecordingWindowPresenting)?
    private(set) var model: ScreenRecordingModel?
    private var terminationApproval: ScreenRecordingModel.TerminationApprovalIdentity?
    private var commitIntent: UUID?
    private var closeCompletion: ((Bool) -> Void)?

    init(capture: any ScreenRecordingCapturing, storage: any ScreenRecordingStoring, sessionLabel: String? = nil,
         makeWindow: @escaping () -> any ScreenRecordingWindowPresenting = { ScreenRecordingWindowController() }) {
        self.capture = capture; self.storage = storage; self.sessionLabel = sessionLabel; self.makeWindow = makeWindow
    }

    var hasActiveOrUnsavedRecording: Bool { model?.hasActiveOrUnsavedRecording == true }

    func present(source: ScreenRecordingSource? = nil) {
        cancelPendingTermination()
        if let model, let window {
            if model.canStart, let source { model.options.source = source }
            window.focus()
            return
        }
        let model = ScreenRecordingModel(capture: capture, storage: storage, sessionLabel: sessionLabel)
        if let source { model.options.source = source }
        let window = makeWindow()
        self.model = model
        self.window = window
        model.onClose = { [weak self] in
            guard let self else { return }
            if closeCompletion != nil {
                guard let approval = self.model?.terminationApprovalIdentity else {
                    completeTermination(false)
                    return
                }
                terminationApproval = approval
                completeTermination(true)
            } else { self.window?.close() }
        }
        model.onCloseCancelled = { [weak self] in self?.cancelPendingTermination() }
        window.present(model: model) { [weak self] in
            guard let self else { return }
            self.model = nil
            self.window = nil
            completeTermination(true)
        }
    }

    func stop() {
        guard let model else { return }
        window?.focus()
        model.stop()
    }

    func requestCloseForTermination(completion: @escaping (Bool) -> Void) {
        guard let model else { completion(true); return }
        guard closeCompletion == nil else { completion(false); return }
        terminationApproval = nil
        closeCompletion = completion
        window?.focus()
        model.requestClose(forTermination: true)
    }

    /// Phase two: call only after every other document/window also approved quitting. Until this
    /// succeeds, the app delegate must not reply terminateNow. A cancelled preparation returns false.
    func commitPreparedTermination() async -> Bool {
        guard let approval = terminationApproval else { return model == nil }
        terminationApproval = nil
        guard let model else { return true }
        guard model.terminationApprovalIdentity == approval else {
            model.cancelTerminationClose()
            return false
        }
        let intent = UUID()
        commitIntent = intent
        model.cancelTerminationClose()
        // Cleanup cannot close a window by itself. Recheck intent and state on the same actor turn
        // as closing, since the person may reopen controls or start another session while we await.
        model.discard(close: false)
        await model.waitForCleanup()
        guard commitIntent == intent, self.model === model, model.canStart,
              model.options == approval.options else {
            if commitIntent == intent { commitIntent = nil }
            return false
        }
        commitIntent = nil
        window?.close()
        return self.model == nil
    }

    func cancelPendingTermination() {
        guard closeCompletion != nil || terminationApproval != nil || commitIntent != nil else { return }
        terminationApproval = nil
        commitIntent = nil
        model?.cancelTerminationClose()
        completeTermination(false)
    }

    private func completeTermination(_ shouldClose: Bool) {
        let completion = closeCompletion
        closeCompletion = nil
        completion?(shouldClose)
    }
}
