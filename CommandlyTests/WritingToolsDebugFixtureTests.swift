#if DEBUG
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct WritingToolsDebugFixtureTests {
    @Test func generatedSuggestionsReviewAndCopyUseOnlyAnInMemoryPasteboard() async throws {
        let services = WritingToolsDebugFixture.services
        let model = WritingToolsViewModel(services: services, onGoBack: {})
        #expect(model.report == nil && model.isChecking == false)
        model.input = WritingToolsDebugFixture.sampleInput
        model.check()
        let report = try #require(model.report)
        #expect(report.issues.count == 2)
        #expect(report.issues.allSatisfy { $0.explanation.hasPrefix("Generated fixture:") })
        #expect(model.output == WritingToolsDebugFixture.sampleInput)
        model.useAutomaticSuggestions()
        #expect(model.output == WritingToolsDebugFixture.sampleOutput)
        #expect(await services.pasteboard.readString() == nil)
        model.copyResult()
        await model.waitForCopyForTesting()
        #expect(await services.pasteboard.readString() == WritingToolsDebugFixture.sampleOutput)
    }

    @Test func aDifferentSentenceOrLanguageCannotBeMisrepresentedAsNativeChecking() {
        let services = WritingToolsDebugFixture.services
        var outcome: Result<WritingCheckReport, WritingCheckError>?
        _ = services.checker.check(text: "This are different text", language: nil) { outcome = $0 }
        #expect(outcome == .failure(.malformedResult))
        _ = services.checker.check(text: WritingToolsDebugFixture.sampleInput, language: "invalid") { outcome = $0 }
        #expect(outcome == .failure(.unsupportedLanguage))
    }
}
#endif
