import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct SlackEmojiCatalogTests {
    @Test func aliasesRemainDistinctResolveChainsAndRejectCyclesOrMissingTargets() throws {
        let workspace = try SlackEmojiTestData.workspace()
        let map = ["circle": "https://emoji.slack-edge.com/TFIXTURE/circle/generated.png", "hello": "alias:circle", "wave": "alias:hello",
                   "cycle_one": "alias:cycle_two", "cycle_two": "alias:cycle_one", "missing": "alias:standard_not_returned", "unsafe": "https://other.invalid/image.png"]
        let items = try SlackEmojiCatalogParser.parse(SlackEmojiTestData.catalog(map), workspace: workspace)
        let wave = try #require(items.first { $0.name == "wave" })
        #expect(wave.shortcode == ":wave:")
        guard case .image(let url, let canonical, let aliases) = wave.resolution else { Issue.record("Expected resolved alias"); return }
        #expect(url.host == "emoji.slack-edge.com"); #expect(canonical == "circle"); #expect(aliases == ["hello", "circle"])
        #expect(items.first { $0.name == "cycle_one" }?.resolution == .aliasCycle)
        #expect(items.first { $0.name == "missing" }?.resolution == .missingAlias)
        #expect(items.first { $0.name == "unsafe" }?.resolution == .unsupportedURL)
        let matches = try SlackEmojiCatalogParser.matches(items, query: ":circle:")
        #expect(matches.items.map(\.name) == ["circle", "hello", "wave"])
    }
    @Test func absentOrBroaderScopesNeverCountAsEmojiOnlyAccess() throws {
        try SlackEmojiAPIValidation.scopes("emoji:read")
        #expect(throws: SlackEmojiError.unverifiedScopes) { try SlackEmojiAPIValidation.scopes(nil) }
        #expect(throws: SlackEmojiError.missingScope) { try SlackEmojiAPIValidation.scopes("") }
        #expect(throws: SlackEmojiError.excessiveScopes) { try SlackEmojiAPIValidation.scopes("emoji:read,chat:write") }
        #expect(throws: SlackEmojiError.expired) { try SlackEmojiAPIValidation.check(ok: false, error: "token_expired") }
    }
    @Test func exactNamesRemainReachablePastVisibleCapAndOverlargeInventoryIsRejected() throws {
        let workspace = try SlackEmojiTestData.workspace()
        var map = Dictionary(uniqueKeysWithValues: (0..<400).map { ("alias_\($0)", "alias:circle") })
        map["circle"] = "https://emoji.slack-edge.com/TFIXTURE/circle/image.png"
        let items = try SlackEmojiCatalogParser.parse(SlackEmojiTestData.catalog(map), workspace: workspace)
        let matches = try SlackEmojiCatalogParser.matches(items, query: ":circle:")
        #expect(matches.items.first?.name == "circle"); #expect(matches.items.count == 300); #expect(matches.total == 401)
        let large = Dictionary(uniqueKeysWithValues: (0..<20_001).map { ("emoji_\($0)", "alias:circle") })
        #expect(throws: SlackEmojiError.catalogTooLarge) { try SlackEmojiCatalogParser.parse(SlackEmojiTestData.catalog(large), workspace: workspace) }
    }
    @Test func excessivelyDeepAliasesHaveABoundedExplicitResult() throws {
        var map = Dictionary(uniqueKeysWithValues: (0..<65).map { ("alias_\($0)", "alias:alias_\($0 + 1)") })
        map["alias_65"] = "https://emoji.slack-edge.com/TFIXTURE/circle/image.png"
        let items = try SlackEmojiCatalogParser.parse(SlackEmojiTestData.catalog(map), workspace: SlackEmojiTestData.workspace())
        #expect(items.first { $0.name == "alias_0" }?.resolution == .aliasTooDeep)
        #expect(items.first { $0.name == "alias_64" }?.resolution.imageURL != nil)
    }
    @Test func mediaAddressesRemainInsideVerifiedWorkspaceEmojiHosts() throws {
        let workspace = try SlackEmojiTestData.workspace()
        for text in ["https://emoji.slack-edge.com/TFIXTURE/circle/image.png", "https://fixture.slack.com/emoji/circle/image.gif", "https://my.slack.com/emoji/circle/image.gif"] {
            #expect(SlackEmojiURLPolicy.media(try #require(URL(string: text)), workspace: workspace))
        }
        for text in ["https://emoji.slack-edge.com/TOTHER/circle/image.png", "https://evil.slack.com/emoji/circle/image.gif", "https://emoji.slack-edge.com.evil.invalid/TFIXTURE/circle/image.png", "https://fixture.slack.com/api/image.gif", "http://emoji.slack-edge.com/TFIXTURE/circle/image.png", "https://user:secret@emoji.slack-edge.com/TFIXTURE/circle/image.png", "https://emoji.slack-edge.com:444/TFIXTURE/circle/image.png"] {
            #expect(!SlackEmojiURLPolicy.media(try #require(URL(string: text)), workspace: workspace))
        }
    }
}
nonisolated enum SlackEmojiTestData {
    static func workspace(id: String = "TFIXTURE", revision: UUID = UUID()) throws -> SlackEmojiWorkspace {
        .init(id: id, name: "Generated Workspace", url: try #require(URL(string: "https://fixture.slack.com/")), botID: "BFIXTURE", enterpriseID: nil, revision: revision)
    }
    static func catalog(_ map: [String: String]) throws -> Data { try JSONSerialization.data(withJSONObject: ["ok": true, "emoji": map]) }
}
