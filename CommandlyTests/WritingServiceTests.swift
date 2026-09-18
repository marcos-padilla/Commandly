import AppKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct WritingServiceTests {
    @Test func sharedPasteboardNamesAreRejectedBeforeReadingAnyText() {
        let reserved: [NSPasteboard.Name] = [.general, .find, .font, .ruler, .drag]
        for identity in reserved.map(\.rawValue) + [""] {
            let board = WritingTestPasteboard("teh text")
            board.identity = identity
            #expect(throws: WritingServiceError.invalidSelection) {
                try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { 0 })
            }
            #expect(board.readCount == 0 && board.writes.isEmpty)
        }
    }

    @Test func successfulServiceWritesOnlyItsExplicitPasteboard() throws {
        let board = WritingTestPasteboard("teh text")
        let progress = WritingTestProgress(result: .success(Self.report("teh text")))
        let origin = WritingTestOrigin()
        let provider = NativeWritingServiceProvider(checker: InMemoryWritingChecker(), progress: progress,
            now: { 0 }, captureOrigin: { .init(name: "Fixture Editor", restoreIfAppropriate: { origin.restoreCount += 1 }) })
        try provider.perform(on: board)
        #expect(board.text == "the text")
        #expect(board.writes == ["the text"])
        #expect(progress.receivedText == "teh text")
        #expect(origin.restoreCount == 1)
    }

    @Test func cancellationTimeoutAndChangedRequestsNeverWrite() throws {
        let board = WritingTestPasteboard("teh text")
        let time = WritingTestClock()
        let transaction = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { time.value })
        transaction.cancel()
        #expect(throws: WritingServiceError.cancelled) { try transaction.commit("the text") }
        let timed = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { time.value })
        time.value = 8
        #expect(throws: WritingServiceError.timedOut) { try timed.commit("the text") }
        time.value = 0
        let changed = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { time.value })
        board.changeCount += 1
        #expect(throws: WritingServiceError.changedSelection) { try changed.commit("the text") }
        #expect(board.writes.isEmpty)
        #expect(board.text == "teh text")
    }

    @Test func reportMismatchAndEngineFailureReturnWithoutReplacement() {
        for result in [Result<WritingCheckReport, WritingCheckError>.failure(.cancelled), .failure(.timedOut), .success(Self.report("different source"))] {
            let board = WritingTestPasteboard("teh text")
            let provider = NativeWritingServiceProvider(checker: InMemoryWritingChecker(), progress: WritingTestProgress(result: result),
                now: { 0 }, captureOrigin: { .none })
            #expect(throws: (any Error).self) { try provider.perform(on: board) }
            #expect(board.writes.isEmpty)
        }
    }

    @Test func onlyOneCompletionWinsAndLateNativeCallbacksAreDiscarded() {
        let time = WritingTestClock()
        var finishes = 0
        let operation = WritingInlineOperation(deadline: 8, now: { time.value }, onFinish: { finishes += 1 })
        time.value = 8
        operation.receive(.success(Self.report("teh text")))
        operation.receive(.success(Self.report("late text")))
        operation.cancel()
        #expect(operation.outcome == .failure(.timedOut))
        #expect(finishes == 1)
        let cancelled = WritingInlineOperation(deadline: 9, now: { time.value }, onFinish: { finishes += 1 })
        cancelled.cancel()
        cancelled.timeOut()
        cancelled.receive(.success(Self.report("late")))
        #expect(cancelled.outcome == .failure(.cancelled))
        #expect(finishes == 2)
    }

    @Test func changedPasteboardAfterProgressAndDeadlineBeforeCommitFailClosed() {
        let board = WritingTestPasteboard("teh text")
        let progress = WritingTestProgress(result: .success(Self.report("teh text")), beforeReturning: { board.text = "new selection" })
        let provider = NativeWritingServiceProvider(checker: InMemoryWritingChecker(), progress: progress, now: { 0 }, captureOrigin: { .none })
        #expect(throws: WritingServiceError.changedSelection) { try provider.perform(on: board) }
        #expect(board.writes.isEmpty)
        let expiredBoard = WritingTestPasteboard("teh text")
        let clock = WritingTestClock()
        let slowProgress = WritingTestProgress(result: .success(Self.report("teh text")), beforeReturning: { clock.value = 8 })
        let lateProvider = NativeWritingServiceProvider(checker: InMemoryWritingChecker(), progress: slowProgress,
            now: { clock.value }, captureOrigin: { .none })
        #expect(throws: WritingServiceError.timedOut) { try lateProvider.perform(on: expiredBoard) }
        #expect(expiredBoard.writes.isEmpty)
    }

    @Test func unchangedResultsValidateTheRequestButNeverWriteOrCreateAnUndoChange() throws {
        let board = WritingTestPasteboard("Already correct")
        let transaction = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { 0 })
        try transaction.commit("Already correct")
        #expect(board.readCount == 2 && board.writes.isEmpty)
        let stale = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { 0 })
        board.changeCount += 1
        #expect(throws: WritingServiceError.changedSelection) { try stale.commit("Already correct") }
        let expired = try WritingServiceTransaction(pasteboard: board, deadline: 8, now: { 8 })
        #expect(throws: WritingServiceError.timedOut) { try expired.commit("Already correct") }
        #expect(board.writes.isEmpty)
    }

    private static func report(_ source: String) -> WritingCheckReport {
        .init(source: source, issues: [.init(kind: .correction, range: .init(location: 0, length: 3),
            explanation: "Spelling", suggestions: ["the"], automaticReplacement: "the")])
    }
}

@MainActor private final class WritingTestOrigin { var restoreCount = 0 }
@MainActor private final class WritingTestClock { var value: TimeInterval = 0 }
@MainActor private final class WritingTestPasteboard: WritingServicePasteboard {
    var identity = "fixture-service-board"
    var changeCount = 1
    var text: String
    var writes: [String] = []
    var readCount = 0
    init(_ text: String) { self.text = text }
    func readText() -> String? { readCount += 1; return text }
    func writeText(_ text: String) -> Bool { writes.append(text); self.text = text; changeCount += 1; return true }
}
@MainActor private final class WritingTestProgress: WritingInlineProgressPresenting {
    let result: Result<WritingCheckReport, WritingCheckError>
    let beforeReturning: () -> Void
    var receivedText: String?
    init(result: Result<WritingCheckReport, WritingCheckError>, beforeReturning: @escaping () -> Void = {}) {
        self.result = result; self.beforeReturning = beforeReturning
    }
    func run(text: String, checker: any WritingChecking, deadline: TimeInterval, originName: String?) -> Result<WritingCheckReport, WritingCheckError> {
        receivedText = text; beforeReturning(); return result
    }
}
