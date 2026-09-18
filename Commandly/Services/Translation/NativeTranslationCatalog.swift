import Foundation
import Infrastructure
import Translation

/// Reads native support metadata only. A fresh availability instance belongs to each call.
nonisolated struct NativeTranslationCatalog: TranslationLanguageProviding {
    @concurrent func supportedLanguages() async throws -> [TranslationLanguage] {
        try Task.checkCancellation()
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        let languages = await availability.supportedLanguages
        try Task.checkCancellation()
        guard languages.isEmpty == false else { throw TextTranslationError.unavailable }
        var seen: Set<String> = []
        return languages.map(NativeTranslationLanguage.value).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @concurrent func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability {
        try Task.checkCancellation()
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        let status = await availability.status(from: Locale.Language(identifier: sourceLanguageID), to: Locale.Language(identifier: targetLanguageID))
        try Task.checkCancellation()
        switch status {
        case .installed: return .installed
        case .supported: return .downloadRequired
        case .unsupported: return .unsupported
        @unknown default: throw TextTranslationError.unavailable
        }
    }
}

nonisolated enum NativeTranslationLanguage {
    static func value(_ language: Locale.Language) -> TranslationLanguage {
        let identifier = language.minimalIdentifier
        return TranslationLanguage(id: identifier,
            name: Locale.current.localizedString(forIdentifier: identifier) ?? identifier)
    }
}
