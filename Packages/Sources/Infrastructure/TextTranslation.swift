import Foundation

/// One language reported by the native translation framework, with a localized display name.
public struct TranslationLanguage: Sendable, Equatable, Identifiable {
    /// The framework language's canonical identifier; retains script and regional distinctions.
    public let id: String
    /// A localized name suitable for a language picker.
    public let name: String
    /// Creates one catalog entry, without implying that its model is installed.
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Current support for a native source/target language pair.
public enum TranslationPairAvailability: Sendable, Equatable {
    /// The native pair metadata is being refreshed; no download need is implied yet.
    case checking
    /// Native models are already available. They can still be removed before the next request.
    case installed
    /// Supported; Apple may ask to download models after explicit translation/download intent.
    case downloadRequired
    /// The selected native language pairing is unsupported, including the same language twice.
    case unsupported
    /// Automatic detection needs the text and may ask the person to resolve ambiguity.
    case automaticSource
}

/// A bounded text submission. A nil source asks the native framework to detect the source language.
public struct TextTranslationRequest: Sendable, Equatable {
    /// Exact reviewed source text, limited to 10,000 characters and 64 KiB UTF-8.
    public let text: String
    /// A chosen native language ID, or nil for automatic detection.
    public let sourceLanguageID: String?
    /// An explicitly chosen native target language ID.
    public let targetLanguageID: String
    /// Validates an explicit submission without changing its contents.
    public init(text: String, sourceLanguageID: String?, targetLanguageID: String) throws {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw TextTranslationError.emptyInput }
        guard text.count <= 10_000, text.utf8.count <= 65_536 else { throw TextTranslationError.inputTooLong }
        guard targetLanguageID.isEmpty == false, targetLanguageID.utf8.count <= 128,
              sourceLanguageID.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true else {
            throw TextTranslationError.unsupportedLanguage
        }
        self.text = text; self.sourceLanguageID = sourceLanguageID; self.targetLanguageID = targetLanguageID
    }
}

/// One native translation result, kept only for the current review session.
public struct TextTranslationResult: Sendable, Equatable {
    /// Exact translated text, bounded to 256 KiB UTF-8.
    public let text: String
    /// The source language actually used, including native automatic detection.
    public let sourceLanguage: TranslationLanguage
    /// The target language actually used.
    public let targetLanguage: TranslationLanguage
    /// Validates a bounded result. It does not write to the clipboard or persist the text.
    public init(text: String, sourceLanguage: TranslationLanguage, targetLanguage: TranslationLanguage) throws {
        guard text.isEmpty == false, text.utf8.count <= 262_144 else { throw TextTranslationError.invalidResult }
        self.text = text; self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage
    }
}

/// Sanitized recoverable translation failures. Native error descriptions must not expose input text.
public enum TextTranslationError: Error, Sendable, Equatable {
    /// The submission has no non-whitespace text.
    case emptyInput
    /// The submission exceeds the character or UTF-8 byte limit.
    case inputTooLong
    /// A selected language is absent or invalid.
    case unsupportedLanguage
    /// The native framework cannot translate this source/target pairing.
    case unsupportedPair
    /// Native source detection needs an explicit language choice.
    case unableToDetectSource
    /// The native language models are not installed or ready.
    case languagesNotInstalled
    /// Native translation support metadata cannot be loaded.
    case unavailable
    /// The result is empty, oversized, or inconsistent with the requested operation.
    case invalidResult
    /// The native request failed; private native error details are not propagated.
    case translationFailed
    /// The explicit clipboard write failed; the reviewed result remains available.
    case copyFailed
}

/// Read-only native language support. Construction and catalog reads must not request downloads.
public protocol TranslationLanguageProviding: Sendable {
    /// Returns the actual native catalog without a hardcoded or silently truncated shortlist.
    func supportedLanguages() async throws -> [TranslationLanguage]
    /// Reports whether a specific selected pair is installed, downloadable, or unsupported.
    func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability
}

/// User-initiated native translation. A live adapter may require an attached view for Apple consent UI.
@MainActor
public protocol TextTranslating: Sendable {
    /// Translates exactly one reviewed submission, requesting Apple's download consent if needed.
    func translate(_ request: TextTranslationRequest) async throws -> TextTranslationResult
    /// Explicitly asks Apple to prepare a chosen pair; no translation is requested.
    func prepare(sourceLanguageID: String, targetLanguageID: String) async throws
    /// Cancels local work and prevents late results. OS-managed downloads may continue separately.
    func cancel()
}

/// Copies only a reviewed translation after explicit intent, without reading the clipboard.
public protocol TranslationResultCopying: Sendable {
    /// Writes the provided reviewed text without reading other clipboard contents.
    func copy(_ text: String) async throws
}
