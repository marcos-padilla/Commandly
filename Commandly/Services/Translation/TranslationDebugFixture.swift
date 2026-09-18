#if DEBUG
import Foundation
import Infrastructure

/// Opt-in UI acceptance data only. Output is visibly labeled; it is not a native translation.
/// Input: exactly "hello", source Detect Language or English, target Spanish.
@MainActor
enum TranslationDebugFixture {
    static var services: TranslationApplicationServices {
        TranslationApplicationServices(languages: TranslationFixtureCatalog(), translator: TranslationFixtureTranslator(),
            copier: TranslationFixtureCopier(), preferredLanguages: ["es"], sessionFactory: { Self.services })
    }
}

nonisolated private enum TranslationFixtureValue {
    static let english = TranslationLanguage(id: "en", name: "English")
    static let spanish = TranslationLanguage(id: "es", name: "Spanish")
    static let output = "hola\n\nGenerated UI fixture — no native translation ran."
}

nonisolated private struct TranslationFixtureCatalog: TranslationLanguageProviding {
    func supportedLanguages() async throws -> [TranslationLanguage] {
        try Task.checkCancellation()
        return [TranslationFixtureValue.english, TranslationFixtureValue.spanish]
    }
    func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability {
        try Task.checkCancellation()
        return sourceLanguageID == "en" && targetLanguageID == "es" ? .installed : .unsupported
    }
}

@MainActor private struct TranslationFixtureTranslator: TextTranslating {
    func translate(_ request: TextTranslationRequest) async throws -> TextTranslationResult {
        try Task.checkCancellation()
        guard request.text == "hello", request.sourceLanguageID == nil || request.sourceLanguageID == "en",
              request.targetLanguageID == "es" else { throw TextTranslationError.unsupportedPair }
        return try TextTranslationResult(text: TranslationFixtureValue.output,
            sourceLanguage: TranslationFixtureValue.english, targetLanguage: TranslationFixtureValue.spanish)
    }
    func prepare(sourceLanguageID: String, targetLanguageID: String) async throws {
        try Task.checkCancellation()
        guard sourceLanguageID == "en", targetLanguageID == "es" else { throw TextTranslationError.unsupportedPair }
    }
    func cancel() {}
}

/// Records explicit copy intent for debug verification; never touches NSPasteboard.
actor TranslationFixtureCopier: TranslationResultCopying {
    private(set) var copied: [String] = []
    func copy(_ text: String) async throws {
        try Task.checkCancellation()
        guard text == TranslationFixtureValue.output else { throw TextTranslationError.copyFailed }
        copied.append(text)
    }
}
#endif
