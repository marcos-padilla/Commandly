#if DEBUG
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Generated Translation UI fixture", .timeLimit(.minutes(1)))
@MainActor
struct TranslationDebugFixtureTests {
    @Test
    func acceptedFixtureIsVisiblyLabeledAndCopiesOnlyToRecordingActor() async throws {
        let services = TranslationDebugFixture.services.freshSession()
        #expect(services.nativeBridge == nil)
        #expect(try await services.languages.supportedLanguages().map(\.id) == ["en", "es"])
        let result = try await services.translator.translate(TranslationTestValue.request())
        #expect(result.text == "hola\n\nGenerated UI fixture — no native translation ran.")
        #expect(result.sourceLanguage.id == "en" && result.targetLanguage.id == "es")
        let copier = try #require(services.copier as? TranslationFixtureCopier)
        #expect(await copier.copied.isEmpty)
        try await services.copier.copy(result.text)
        #expect(await copier.copied == [result.text])
    }

    @Test
    func unsupportedInputPairAndAlreadyCancelledRequestsNeverProducePretendTranslation() async throws {
        let services = TranslationDebugFixture.services
        await #expect(throws: TextTranslationError.unsupportedPair) {
            try await services.translator.translate(TranslationTestValue.request("other input"))
        }
        await #expect(throws: TextTranslationError.unsupportedPair) {
            try await services.translator.translate(TextTranslationRequest(text: "hello", sourceLanguageID: "es", targetLanguageID: "en"))
        }
        #expect(try await services.languages.availability(sourceLanguageID: "en", targetLanguageID: "en") == .unsupported)
        let task = Task { try await services.translator.translate(TranslationTestValue.request()) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let copier = try #require(services.copier as? TranslationFixtureCopier)
        #expect(await copier.copied.isEmpty)
    }
}
#endif
