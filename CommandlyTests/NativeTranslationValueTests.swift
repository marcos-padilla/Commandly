import Foundation
import Infrastructure
import Testing
import Translation
@testable import Commandly

@Suite("Native translation values", .timeLimit(.minutes(1)))
struct NativeTranslationValueTests {
    @Test
    func reviewedInputPreservesWhitespaceAndEnforcesIndependentCharacterAndByteLimits() throws {
        let exact = " hello\nworld "
        #expect(try TranslationTestValue.request(exact).text == exact)
        #expect(throws: TextTranslationError.emptyInput) { try TranslationTestValue.request("\n \t") }
        #expect(throws: TextTranslationError.inputTooLong) { try TranslationTestValue.request(String(repeating: "a", count: 10_001)) }
        // Each emoji is one grapheme but substantially more than one UTF-8 byte.
        let multibyte = String(repeating: "👨‍👩‍👧‍👦", count: 3_000)
        #expect(multibyte.count < 10_000 && multibyte.utf8.count > 65_536)
        #expect(throws: TextTranslationError.inputTooLong) { try TranslationTestValue.request(multibyte) }
        #expect(throws: TextTranslationError.unsupportedLanguage) { try TextTranslationRequest(text: "hello", sourceLanguageID: "", targetLanguageID: "es") }
        #expect(throws: TextTranslationError.unsupportedLanguage) { try TextTranslationRequest(text: "hello", sourceLanguageID: nil, targetLanguageID: String(repeating: "a", count: 129)) }
    }

    @Test
    func oversizedOrEmptyResultCannotReachReviewOrClipboard() throws {
        #expect(throws: TextTranslationError.invalidResult) { try TranslationTestValue.result("") }
        #expect(throws: TextTranslationError.invalidResult) { try TranslationTestValue.result(String(repeating: "a", count: 262_145)) }
        #expect(try TranslationTestValue.result("  hola\n").text == "  hola\n")
    }

    @Test
    func languageMappingKeepsNativeScriptAndRegionalDistinctions() {
        let traditional = NativeTranslationLanguage.value(Locale.Language(identifier: "zh-Hant"))
        let simplified = NativeTranslationLanguage.value(Locale.Language(identifier: "zh-Hans"))
        #expect(traditional.id != simplified.id && !traditional.name.isEmpty && !simplified.name.isEmpty)
        let brazil = NativeTranslationLanguage.value(Locale.Language(identifier: "pt-BR"))
        let portugal = NativeTranslationLanguage.value(Locale.Language(identifier: "pt-PT"))
        #expect(brazil.id != portugal.id)
    }

    @Test
    func nativeErrorsAreSanitizedWithoutPrivateDescriptions() {
        let pairs: [(Error, TextTranslationError)] = [
            (TranslationError.nothingToTranslate, .emptyInput),
            (TranslationError.unsupportedSourceLanguage, .unsupportedLanguage),
            (TranslationError.unsupportedTargetLanguage, .unsupportedLanguage),
            (TranslationError.unsupportedLanguagePairing, .unsupportedPair),
            (TranslationError.unableToIdentifyLanguage, .unableToDetectSource),
            (TranslationError.notInstalled, .languagesNotInstalled),
            (NSError(domain: "private input text", code: 1, userInfo: [NSLocalizedDescriptionKey: "private result text"]), .translationFailed)
        ]
        for (native, expected) in pairs { #expect(NativeTranslationFailure.sanitized(native) as? TextTranslationError == expected) }
        #expect(NativeTranslationFailure.sanitized(TranslationError.alreadyCancelled) is CancellationError)
        #expect(NativeTranslationFailure.sanitized(CancellationError()) is CancellationError)
    }
}
