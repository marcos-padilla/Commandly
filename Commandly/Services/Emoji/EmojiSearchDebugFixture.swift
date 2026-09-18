#if DEBUG
import Foundation
import Infrastructure

/// Generated UI fixtures never contact a provider and are visibly named as fixtures in the picker.
@MainActor
enum EmojiSearchDebugFixture {
    static func services(pasteboard: any PasteboardAccessing, bundle: Bundle = .main) -> EmojiSearchApplicationServices {
        let url = bundle.url(forResource: "emoji-catalog-v17", withExtension: "json", subdirectory: "Emoji")
            ?? bundle.url(forResource: "emoji-catalog-v17", withExtension: "json")
        return EmojiSearchApplicationServices(catalog: BundledUnicodeEmojiCatalog(resourceURL: url), semantic: GeneratedEmojiSemanticSearch(), pasteboard: pasteboard)
    }
}
private nonisolated struct GeneratedEmojiSemanticSearch: EmojiSemanticSearching {
    private let choice = QuickAISelection(providerID: "commandly.generated-ui", providerName: "Generated UI Fixture — no AI request",
        modelID: "fixed-catalog-examples", modelName: "Fixed example emoji", connectionRevision: "fixture", supportsStreaming: true)
    func selections() async throws -> QuickAICatalog { QuickAICatalog(selections: [choice], preferredID: choice.id) }
    func search(description: String, selection: QuickAISelection, catalog: UnicodeEmojiCatalog) async throws -> [UnicodeEmojiEntry] {
        try Task.checkCancellation()
        return ["🧑‍🚀", "🚀", "✨", "🫱🏻‍🫲🏿"].compactMap { catalog.entry(for: $0) }
    }
}
#endif
