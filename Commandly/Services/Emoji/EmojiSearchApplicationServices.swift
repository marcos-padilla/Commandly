import Foundation
import Infrastructure

@MainActor
struct EmojiSearchApplicationServices {
    let catalog: any UnicodeEmojiCatalogProviding
    let semantic: any EmojiSemanticSearching
    let pasteboard: any PasteboardAccessing

    init(catalog: any UnicodeEmojiCatalogProviding, semantic: any EmojiSemanticSearching, pasteboard: any PasteboardAccessing) {
        self.catalog = catalog; self.semantic = semantic; self.pasteboard = pasteboard
    }

    static func live(pasteboard: any PasteboardAccessing, quickAI: any QuickAIServicing, bundle: Bundle = .main) -> Self {
        // Xcode may preserve the resource directory or flatten it. Neither path accesses user files.
        let url = bundle.url(forResource: "emoji-catalog-v17", withExtension: "json", subdirectory: "Emoji")
            ?? bundle.url(forResource: "emoji-catalog-v17", withExtension: "json")
        return Self(catalog: BundledUnicodeEmojiCatalog(resourceURL: url),
                    semantic: ProviderEmojiSemanticSearch(service: quickAI), pasteboard: pasteboard)
    }
}
