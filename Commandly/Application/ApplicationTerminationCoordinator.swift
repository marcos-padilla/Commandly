import Foundation

@MainActor
protocol FloatingNoteTerminationHandling: AnyObject {
    var hasUnsavedNotes: Bool { get }
    func requestCloseAll(onCompletion: @escaping (Bool) -> Void)
}

@MainActor
protocol ScreenRecordingTerminationHandling: AnyObject {
    var hasActiveOrUnsavedRecording: Bool { get }
    func requestCloseForTermination(completion: @escaping (Bool) -> Void)
    func commitPreparedTermination() async -> Bool
    func cancelPendingTermination()
}

@MainActor
protocol DisplayResolutionTerminationHandling: AnyObject {
    var requiresTerminationReview: Bool { get }
    func requestCloseForTermination(completion: @escaping @MainActor (Bool) -> Void)
    func cancelPendingTermination()
}

extension FloatingNoteCoordinator: FloatingNoteTerminationHandling {}
extension ScreenRecordingCoordinator: ScreenRecordingTerminationHandling {}
extension DisplayResolutionCoordinator: DisplayResolutionTerminationHandling {}

/// Stops capture before reviewing documents. A cancelled document close retains recording review;
/// the recorder may release an approved video only after every document has agreed to quit.
@MainActor
final class ApplicationTerminationCoordinator {
    weak var floatingNotes: (any FloatingNoteTerminationHandling)?
    weak var screenRecording: (any ScreenRecordingTerminationHandling)?
    weak var displayResolution: (any DisplayResolutionTerminationHandling)?
    private(set) var isReviewing = false
    private var reviewTask: Task<Void, Never>?

    var requiresReview: Bool {
        floatingNotes?.hasUnsavedNotes == true || screenRecording?.hasActiveOrUnsavedRecording == true
            || displayResolution?.requiresTerminationReview == true
    }

    func review(completion: @escaping (Bool) -> Void) {
        guard isReviewing == false else { return }
        isReviewing = true
        // Starting a MainActor task lets applicationShouldTerminate return .terminateLater before
        // any completion, including synchronous empty-window and already-saved paths.
        reviewTask = Task { @MainActor in
            let recording = screenRecording
            let notes = floatingNotes
            let display = displayResolution
            let approved = await prepareAndCommit(recording: recording, display: display, notes: notes)
            // A new note/recording may appear while an asynchronous close is in flight. Check on
            // the same actor turn as the AppKit reply, so no newly created work can slip through.
            let mayQuit = approved && requiresReview == false
            if mayQuit == false {
                recording?.cancelPendingTermination()
                display?.cancelPendingTermination()
            }
            isReviewing = false
            completion(mayQuit)
        }
    }

    private func prepareAndCommit(recording: (any ScreenRecordingTerminationHandling)?,
                                  display: (any DisplayResolutionTerminationHandling)?,
                                  notes: (any FloatingNoteTerminationHandling)?) async -> Bool {
        if let recording {
            let approved = await withCheckedContinuation { continuation in
                recording.requestCloseForTermination { continuation.resume(returning: $0) }
            }
            guard approved else { return false }
        }
        if let display {
            let approved = await withCheckedContinuation { continuation in
                display.requestCloseForTermination { continuation.resume(returning: $0) }
            }
            guard approved else { return false }
        }
        if let notes {
            let approved = await withCheckedContinuation { continuation in
                notes.requestCloseAll { continuation.resume(returning: $0) }
            }
            guard approved, notes.hasUnsavedNotes == false else { return false }
        }
        if let recording { return await recording.commitPreparedTermination() }
        return true
    }

    func waitForCompletionForTesting() async { await reviewTask?.value }
}
