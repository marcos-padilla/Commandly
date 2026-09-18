import Testing
@testable import Commandly

@Suite("Application recording and document termination")
@MainActor
struct ApplicationTerminationTests {
    @Test
    func stoppedRecordingApprovalPrecedesNotesAndRepliesOnlyAfterCommit() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        #expect(events.replies.isEmpty)
        #expect(coordinator.isReviewing)
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "notes.close", "recording.commit"])
        #expect(events.replies == [true])
        #expect(coordinator.isReviewing == false)
    }

    @Test
    func failedStopNeverClosesNotesOrCommitsRecording() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        recording.prepares = false
        let notes = TerminationNotesDouble(events)
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "recording.cancel"])
        #expect(events.replies == [false])
        #expect(recording.hasActiveOrUnsavedRecording)
        #expect(notes.hasUnsavedNotes)
    }

    @Test
    func noteCancellationRetainsStoppedReviewWithoutCommit() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        notes.approves = false
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "notes.close", "recording.cancel"])
        #expect(events.replies == [false])
        #expect(recording.hasActiveOrUnsavedRecording)
    }

    @Test
    func replacementRecordingInvalidatesApprovalWhileNotesArePending() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        notes.beforeReply = { recording.commits = false }
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "notes.close", "recording.commit", "recording.cancel"])
        #expect(events.replies == [false])
        #expect(recording.hasActiveOrUnsavedRecording)
    }

    @Test
    func newlyEditedNoteDuringAsynchronousRecorderCommitPreventsQuit() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        recording.duringCommit = { notes.hasUnsavedNotes = true }
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.replies == [false])
        #expect(notes.hasUnsavedNotes)
    }

    @Test
    func recordingAppearingAtCommitCompletionPreventsQuit() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        recording.keepsRecordingAfterCommit = true
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.replies == [false])
        #expect(recording.hasActiveOrUnsavedRecording)
    }

    @Test
    func repeatedQuitRequestsDoNotCreateCompetingDocumentPrompts() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        let coordinator = makeCoordinator(recording, notes)
        coordinator.review { events.replies.append($0) }
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.replies == [true])
        #expect(events.calls.filter { $0 == "notes.close" }.count == 1)
    }

    @Test
    func emptyRuntimeNeedsNoReviewAndNotesOnlyStillSafelyClose() async {
        let coordinator = ApplicationTerminationCoordinator()
        #expect(coordinator.requiresReview == false)
        let events = TerminationEvents()
        let notes = TerminationNotesDouble(events)
        coordinator.floatingNotes = notes
        #expect(coordinator.requiresReview)
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["notes.close"])
        #expect(events.replies == [true])
    }

    private func makeCoordinator(_ recording: TerminationRecordingDouble, _ notes: TerminationNotesDouble)
        -> ApplicationTerminationCoordinator {
        let coordinator = ApplicationTerminationCoordinator()
        coordinator.screenRecording = recording
        coordinator.floatingNotes = notes
        return coordinator
    }

    @Test
    func displayRestoreRunsAfterRecordingStopsAndBeforeNoteReview() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        let display = TerminationDisplayDouble(events)
        let coordinator = makeCoordinator(recording, notes)
        coordinator.displayResolution = display
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "display.restore", "notes.close", "recording.commit"])
        #expect(events.replies == [true])
    }

    @Test
    func failedDisplayRestorationRetainsRecordingReviewAndLeavesNotesUntouched() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        let display = TerminationDisplayDouble(events)
        display.approves = false
        let coordinator = makeCoordinator(recording, notes)
        coordinator.displayResolution = display
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.calls == ["recording.prepare", "display.restore", "recording.cancel", "display.cancel"])
        #expect(events.replies == [false])
        #expect(recording.hasActiveOrUnsavedRecording && notes.hasUnsavedNotes)
    }

    @Test
    func newDisplayPreviewDuringRecordingCleanupPreventsQuit() async {
        let events = TerminationEvents()
        let recording = TerminationRecordingDouble(events)
        let notes = TerminationNotesDouble(events)
        let display = TerminationDisplayDouble(events)
        recording.duringCommit = { display.requiresTerminationReview = true }
        let coordinator = makeCoordinator(recording, notes)
        coordinator.displayResolution = display
        coordinator.review { events.replies.append($0) }
        await coordinator.waitForCompletionForTesting()
        #expect(events.replies == [false])
        #expect(display.requiresTerminationReview)
    }
}

@MainActor
private final class TerminationDisplayDouble: DisplayResolutionTerminationHandling {
    var requiresTerminationReview = true
    var approves = true
    let events: TerminationEvents
    init(_ events: TerminationEvents) { self.events = events }
    func requestCloseForTermination(completion: @escaping @MainActor (Bool) -> Void) {
        events.calls.append("display.restore")
        if approves { requiresTerminationReview = false }
        completion(approves)
    }
    func cancelPendingTermination() { events.calls.append("display.cancel") }
}

@MainActor
private final class TerminationEvents {
    var calls: [String] = []
    var replies: [Bool] = []
}

@MainActor
private final class TerminationRecordingDouble: ScreenRecordingTerminationHandling {
    var hasActiveOrUnsavedRecording = true
    var prepares = true
    var commits = true
    var keepsRecordingAfterCommit = false
    var duringCommit: (() -> Void)?
    let events: TerminationEvents
    init(_ events: TerminationEvents) { self.events = events }
    func requestCloseForTermination(completion: @escaping (Bool) -> Void) {
        events.calls.append("recording.prepare")
        completion(prepares)
    }
    func commitPreparedTermination() async -> Bool {
        events.calls.append("recording.commit")
        duringCommit?()
        if commits { hasActiveOrUnsavedRecording = keepsRecordingAfterCommit }
        return commits
    }
    func cancelPendingTermination() { events.calls.append("recording.cancel") }
}

@MainActor
private final class TerminationNotesDouble: FloatingNoteTerminationHandling {
    var hasUnsavedNotes = true
    var approves = true
    var beforeReply: (() -> Void)?
    let events: TerminationEvents
    init(_ events: TerminationEvents) { self.events = events }
    func requestCloseAll(onCompletion: @escaping (Bool) -> Void) {
        events.calls.append("notes.close")
        if approves { hasUnsavedNotes = false }
        beforeReply?()
        onCompletion(approves)
    }
}
