import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct WritingToolsViewModelTests {
    @Test func openingIsInertAndCheckingRequiresExplicitAction() async {
        let checker = WritingControlledChecker()
        let board = InMemoryPasteboard()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: board), onGoBack: {})
        #expect(checker.requests.isEmpty)
        model.input = "teh text"
        #expect(checker.requests.isEmpty)
        model.check()
        #expect(checker.requests == ["teh text"])
        #expect(model.isChecking)
        checker.complete(.success(Self.report("teh text")))
        #expect(model.output == "teh text")
        model.useAutomaticSuggestions()
        #expect(model.output == "the text")
        #expect(await board.readString() == nil)
        model.copyResult()
        await model.waitForCopyForTesting()
        #expect(await board.readString() == "the text")
        model.stop()
        #expect(model.input.isEmpty && model.output.isEmpty && model.report == nil)
    }

    @Test func editingInputCancellationAndStopRejectLateResults() {
        let checker = WritingControlledChecker()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: InMemoryPasteboard()), onGoBack: {})
        model.input = "teh first"
        model.check()
        model.input = "A newer draft"
        #expect(checker.tokens.first?.cancelled == true)
        checker.complete(.success(Self.report("teh first")))
        #expect(model.input == "A newer draft" && model.report == nil && model.output.isEmpty)
        model.check()
        #expect(model.handleEscape())
        checker.complete(.success(.init(source: "A newer draft", issues: [])), index: 1)
        #expect(model.report == nil)
        model.check()
        model.stop()
        checker.complete(.success(.init(source: "A newer draft", issues: [])), index: 2)
        #expect(model.report == nil && model.output.isEmpty)
    }

    @Test func malformedFailureAndOversizedInputKeepTextAndNeverCopy() {
        let checker = WritingControlledChecker()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: InMemoryPasteboard()), onGoBack: {})
        model.input = "teh text"
        model.check()
        checker.complete(.failure(.unavailable))
        #expect(model.input == "teh text")
        #expect(model.statusMessage != nil)
        #expect(model.canCopy == false)
        model.input = String(repeating: "x", count: WritingCorrectionPolicy.maximumInputBytes + 1)
        model.check()
        #expect(checker.requests.count == 1)
    }

    @Test func editedOutputIsNotOverwrittenByApplyingOffsetsFromOldInput() {
        let checker = WritingControlledChecker()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: InMemoryPasteboard()), onGoBack: {})
        model.input = "teh text"
        model.check()
        let report = Self.report("teh text")
        checker.complete(.success(report))
        model.output = "A manual correction"
        if let issue = report.issues.first { model.useSuggestion("the", for: issue) }
        #expect(model.output == "A manual correction")
        #expect(model.statusMessage?.contains("Restore Original") == true)
        model.restoreOriginal()
        #expect(model.output == "teh text")
    }

    @Test func successiveSuggestionsPreserveAcceptedChoicesAndManualEdits() {
        let checker = WritingControlledChecker()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: InMemoryPasteboard()), onGoBack: {})
        let first = WritingIssue(kind: .grammar, range: .init(location: 3, length: 3),
            explanation: "Grammar", suggestions: ["is"], automaticReplacement: "is")
        let second = WritingIssue(kind: .correction, range: .init(location: 7, length: 3),
            explanation: "Spelling", suggestions: ["the"], automaticReplacement: "the")
        model.input = "He are teh example"
        model.check()
        checker.complete(.success(.init(source: "He are teh example", issues: [first, second])))
        model.useSuggestion("is", for: first)
        model.useSuggestion("the", for: second)
        #expect(model.output == "He is the example")
        model.output = "Keep these manual edits"
        model.useSuggestion("is", for: first)
        model.useAutomaticSuggestions()
        #expect(model.output == "Keep these manual edits")
        model.restoreOriginal()
        model.useSuggestion("the", for: second)
        #expect(model.output == "He are the example")
        model.useAutomaticSuggestions()
        #expect(model.output == "He is the example")
    }

    @Test func conflictingSuggestionDoesNotDiscardPreviouslyAcceptedText() {
        let checker = WritingControlledChecker()
        let model = WritingToolsViewModel(services: .init(checker: checker, pasteboard: InMemoryPasteboard()), onGoBack: {})
        let first = WritingIssue(kind: .correction, range: .init(location: 0, length: 3), explanation: "Spelling", suggestions: ["the"])
        let overlap = WritingIssue(kind: .grammar, range: .init(location: 0, length: 8), explanation: "Grammar", suggestions: ["different"])
        model.input = "teh text"
        model.check()
        checker.complete(.success(.init(source: "teh text", issues: [first, overlap])))
        model.useSuggestion("the", for: first)
        model.useSuggestion("different", for: overlap)
        #expect(model.output == "the text")
        #expect(model.statusMessage?.contains("could not be applied") == true)
    }

    private static func report(_ source: String) -> WritingCheckReport {
        .init(source: source, issues: [.init(kind: .correction, range: .init(location: 0, length: 3),
            explanation: "Spelling", suggestions: ["the"], automaticReplacement: "the")])
    }
}

@MainActor
private final class WritingControlledChecker: WritingChecking {
    let availableLanguages = ["en_US"]
    var requests: [String] = []
    var tokens: [WritingControlledToken] = []
    var completions: [@MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void] = []
    func check(text: String, language: String?,
               completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void
    ) -> any WritingCheckCancelling {
        requests.append(text); completions.append(completion)
        let token = WritingControlledToken(); tokens.append(token); return token
    }
    func complete(_ result: Result<WritingCheckReport, WritingCheckError>, index: Int = 0) { completions[index](result) }
}
@MainActor private final class WritingControlledToken: WritingCheckCancelling {
    var cancelled = false
    func cancel() { cancelled = true }
}
