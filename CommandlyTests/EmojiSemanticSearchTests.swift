import AIKit
import Foundation
import Testing
@testable import Commandly

@Suite("Provider emoji search boundary")
struct EmojiSemanticSearchTests {
    @Test func providerReceivesOnlyTheExplicitDescriptionAndReturnsValidatedEmoji() async throws {
        let catalog = try await EmojiTestData.catalog()
        let service = EmojiQuickAIFake(reply: "[\"🧑‍🚀\",\"❤\",\"❤️\"]")
        let adapter = ProviderEmojiSemanticSearch(service: service)
        _ = try await adapter.selections()
        #expect(await service.requests.isEmpty)
        let result = try await adapter.search(description: " space adventure ", selection: EmojiTestSelection.first, catalog: catalog)
        #expect(result.map(\.symbol) == ["🧑‍🚀", "❤️"])
        let request = try #require(await service.requests.first)
        #expect(request.count == 2)
        #expect(request.last == .user("space adventure"))
        #expect(request.allSatisfy { $0.toolCalls.isEmpty && $0.toolResults.isEmpty })
    }
    @Test(arguments: ["Here is 😀", "{\"emoji\":\"😀\"}", "```json\n[\"😀\"]\n```", "[\"😀\",\"not an emoji\"]", "[\"😀😀\"]", "[\"😀 https://example.com\"]", "[\"🫱🏻‍🫲🏻\"]"])
    func malformedAndOutOfCatalogOutputIsNeverRendered(_ text: String) async throws {
        let catalog = try await EmojiTestData.catalog()
        #expect(throws: UnicodeEmojiError.invalidAIResponse) { try ProviderEmojiSemanticSearch.parse(text, catalog: catalog) }
    }
    @Test func refusesTruncationAndBoundsRequestAndStreamWithoutPublishingPartialText() async throws {
        let catalog = try await EmojiTestData.catalog()
        let truncated = ProviderEmojiSemanticSearch(service: EmojiQuickAIFake(reply: "[\"😀\"]", reason: .length))
        await #expect(throws: UnicodeEmojiError.invalidAIResponse) { try await truncated.search(description: "hello", selection: EmojiTestSelection.first, catalog: catalog) }
        let oversized = ProviderEmojiSemanticSearch(service: EmojiQuickAIFake(reply: "[\"😀\"]", delta: String(repeating: "x", count: 8_193)))
        await #expect(throws: UnicodeEmojiError.responseTooLarge) { try await oversized.search(description: "hello", selection: EmojiTestSelection.first, catalog: catalog) }
        let service = EmojiQuickAIFake(reply: "[]")
        let adapter = ProviderEmojiSemanticSearch(service: service)
        await #expect(throws: UnicodeEmojiError.queryTooLong) { try await adapter.search(description: String(repeating: "é", count: 513), selection: EmojiTestSelection.first, catalog: catalog) }
        #expect(await service.requests.isEmpty)
        #expect(try ProviderEmojiSemanticSearch.parse("[]", catalog: catalog).isEmpty)
        #expect(throws: UnicodeEmojiError.invalidAIResponse) {
            try ProviderEmojiSemanticSearch.parse("[" + Array(repeating: "\"😀\"", count: 13).joined(separator: ",") + "]", catalog: catalog)
        }
    }
}

nonisolated enum EmojiTestSelection {
    static let first = QuickAISelection(providerID: "fixture", providerName: "Fixture provider", modelID: "model-a", modelName: "Model A", connectionRevision: "first", supportsStreaming: true)
    static let second = QuickAISelection(providerID: "fixture", providerName: "Fixture provider", modelID: "model-b", modelName: "Model B", connectionRevision: "first", supportsStreaming: true)
    static let catalog = QuickAICatalog(selections: [first, second], preferredID: first.id)
}

actor EmojiQuickAIFake: QuickAIServicing {
    let reply: String
    let reason: AIFinishReason
    let delta: String
    private(set) var requests: [[AIMessage]] = []
    init(reply: String, reason: AIFinishReason = .completed, delta: String = "") { self.reply = reply; self.reason = reason; self.delta = delta }
    func catalog() async throws -> QuickAICatalog { EmojiTestSelection.catalog }
    func respond(messages: [AIMessage], selection: QuickAISelection, onTextDelta: @escaping @Sendable (String) async throws -> Void) async throws -> AICompletionResponse {
        requests.append(messages)
        if !delta.isEmpty { try await onTextDelta(delta) }
        return AICompletionResponse(id: nil, message: .assistant(reply), finishReason: reason)
    }
}
