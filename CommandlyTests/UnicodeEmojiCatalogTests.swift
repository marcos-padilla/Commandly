import Foundation
import Testing
@testable import Commandly

@Suite("Unicode emoji catalog")
struct UnicodeEmojiCatalogTests {
    @Test func catalogHasEveryPinnedRGISequenceAndValidFamilies() async throws {
        let catalog = try await EmojiTestData.catalog()
        #expect(catalog.entries.count == 3_953)
        #expect(catalog.entries.filter { !$0.isComponent }.count == 3_944)
        #expect(catalog.entries.filter(\.isComponent).count == 9)
        #expect(Set(catalog.entries.map(\.symbol)).count == 3_953)
        #expect(catalog.categories.count == 10)
        for entry in catalog.entries {
            #expect(catalog.entry(for: entry.family) != nil)
            #expect(catalog.variants(of: entry).contains(entry))
        }
        #expect(try catalog.search(.init(includesVariants: true)).count == 3_953)
        #expect(try catalog.search(.init()).allSatisfy { !$0.isVariant })
        #expect(try catalog.search(.init()).first?.name == "grinning face")
        #expect(try catalog.search(.init(query: "  ", includesVariants: true)) == catalog.entries)
    }
    @Test func englishKeywordsAndNamesFindFlagsJoinedFamiliesAndNewUnicode17Emoji() async throws {
        let catalog = try await EmojiTestData.catalog()
        #expect(try catalog.search(.init(query: "Japan")).contains { $0.symbol == "🇯🇵" })
        #expect(try catalog.search(.init(query: "family woman woman girl")).contains { $0.symbol == "👩‍👩‍👧" })
        #expect(try catalog.search(.init(query: "astronaut")).contains { $0.symbol == "🧑‍🚀" })
        #expect(try catalog.search(.init(query: "orca")).contains { $0.name == "orca" })
        #expect(try catalog.search(.init(query: "LOL")).contains { $0.symbol == "😂" })
        #expect(try catalog.search(.init(query: "???")).isEmpty)
        #expect(try catalog.search(.init(category: "Flags")).allSatisfy { $0.category == "Flags" })
    }
    @Test func exactAliasesPreservePresentationAndAllHandshakeSkinToneCombinations() async throws {
        let catalog = try await EmojiTestData.catalog()
        let handshake = try #require(catalog.entry(for: "🤝"))
        let variants = catalog.variants(of: handshake)
        #expect(variants.count == 26)
        #expect(variants.contains { $0.symbol == "🫱🏻‍🫲🏿" })
        #expect(try catalog.search(.init(query: "handshake light dark")).contains { $0.symbol == "🫱🏻‍🫲🏿" })
        #expect(try catalog.search(.init(query: "👩🏽‍🚀")).map(\.symbol) == ["👩🏽‍🚀"])
        #expect(catalog.entry(for: "❤")?.symbol == "❤️")
        #expect(catalog.entry(for: "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}")?.name == "flag: Scotland")
        #expect(catalog.entry(for: "🫱🏻‍🫲🏿")?.codePoints == "U+1FAF1 U+1F3FB U+200D U+1FAF2 U+1F3FF")
    }
    @Test func corruptCatalogAndOversizedSearchAreRejected() async throws {
        #expect(throws: UnicodeEmojiError.invalidCatalog) { try UnicodeEmojiCatalog(data: Data("{}".utf8)) }
        let catalog = try await EmojiTestData.catalog()
        #expect(throws: UnicodeEmojiError.queryTooLong) { try catalog.search(.init(query: String(repeating: "x", count: 1_025))) }
    }
}

nonisolated enum EmojiTestData {
    static func catalog() async throws -> UnicodeEmojiCatalog { try await BundledUnicodeEmojiCatalog(resourceURL: resourceURL()).load() }
    static func resourceURL() throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return try #require(bundle.url(forResource: "emoji-catalog-v17", withExtension: "json", subdirectory: "Emoji")
            ?? bundle.url(forResource: "emoji-catalog-v17", withExtension: "json"))
    }
}
