import AppKit
import Foundation
import Infrastructure

@MainActor
struct TranslationApplicationServices {
    let languages: any TranslationLanguageProviding
    let translator: any TextTranslating
    let copier: any TranslationResultCopying
    let nativeBridge: NativeTranslationBridge?
    let preferredLanguages: [String]
    private let sessionFactory: (@MainActor () -> TranslationApplicationServices)?

    init(languages: any TranslationLanguageProviding, translator: any TextTranslating,
         copier: any TranslationResultCopying, nativeBridge: NativeTranslationBridge? = nil,
         preferredLanguages: [String] = Locale.preferredLanguages,
         sessionFactory: (@MainActor () -> TranslationApplicationServices)? = nil) {
        self.languages = languages; self.translator = translator; self.copier = copier
        self.nativeBridge = nativeBridge; self.preferredLanguages = preferredLanguages
        self.sessionFactory = sessionFactory
    }

    static var live: Self {
        let bridge = NativeTranslationBridge()
        return Self(languages: NativeTranslationCatalog(), translator: bridge,
                    copier: NativeTranslationCopier(), nativeBridge: bridge, sessionFactory: { Self.live })
    }
    static var inMemory: Self {
        Self(languages: UnavailableTranslationCatalog(), translator: UnavailableTextTranslator(), copier: UnavailableTranslationCopier())
    }

    /// Every live launcher session owns a fresh native bridge. An old disappearing model must
    /// never cancel a newer session's request through a shared global translation handle.
    func freshSession() -> Self { sessionFactory?() ?? self }
}

@MainActor private struct NativeTranslationCopier: TranslationResultCopying {
    func copy(_ text: String) async throws {
        try Task.checkCancellation()
        guard text.isEmpty == false, text.utf8.count <= 262_144 else { throw TextTranslationError.copyFailed }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw TextTranslationError.copyFailed }
    }
}
nonisolated private struct UnavailableTranslationCatalog: TranslationLanguageProviding {
    func supportedLanguages() async throws -> [TranslationLanguage] { throw TextTranslationError.unavailable }
    func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability { throw TextTranslationError.unavailable }
}
@MainActor private struct UnavailableTextTranslator: TextTranslating {
    func translate(_ request: TextTranslationRequest) async throws -> TextTranslationResult { throw TextTranslationError.unavailable }
    func prepare(sourceLanguageID: String, targetLanguageID: String) async throws { throw TextTranslationError.unavailable }
    func cancel() {}
}
nonisolated private struct UnavailableTranslationCopier: TranslationResultCopying {
    func copy(_ text: String) async throws { throw TextTranslationError.copyFailed }
}
