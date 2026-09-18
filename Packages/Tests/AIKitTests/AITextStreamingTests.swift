import Foundation
import Testing
@testable import AIKit

struct AITextStreamingTests {
    @Test(arguments: [AIProviderID.openAI, .anthropic, .googleGemini, .mistral, .groq, .xAI, .openRouter, .ollama])
    func reviewedProviderFormatsDeliverDeltasAndUseExistingFinalDecoders(_ provider: AIProviderID) async throws {
        let source = ScriptedAIStreamTransport(lines: Self.lines(for: provider))
        let text = StreamTextRecorder()
        let bridge = AITextStreamingTransport(providerID: provider, transport: source) { await text.append($0) }
        let registry = try AIProviderRegistry.standard(transport: bridge)
        let adapter = try registry.adapter(for: provider)
        let response = try await adapter.complete(request: .init(modelID: provider == .googleGemini ? "models/gemini-test" : "fixture-model",
            messages: [.user("Fixture question")], toolChoice: .none, maximumOutputTokens: 128),
            configuration: .init(providerID: provider, credential: AICredential("fixture-key")))
        #expect(await text.parts == ["Hello", " world"])
        #expect(response.message == .assistant("Hello world"))
        #expect(response.finishReason == .completed)
        let request = try #require(await source.requests.first)
        let body = try AIJSONValue(data: try #require(request.body))
        if provider == .googleGemini {
            #expect(request.url.path.hasSuffix(":streamGenerateContent"))
            #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "alt", value: "sse")) == true)
        } else { #expect(body["stream"]?.booleanValue == true) }
        if provider == .openAI { #expect(body["store"]?.booleanValue == false) }
        #expect(request.description.contains("fixture-key") == false)
        #expect(request.description.contains("Fixture question") == false)
    }

    @Test func sseMultilineCommentsAndRepeatedOpenRouterUsageAreAccepted() async throws {
        let lines = [": OPENROUTER PROCESSING", "event: message", "data: {\"choices\":", "data: [{\"index\":0,\"delta\":{\"content\":\"Hi\"}}]}", "",
            "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}", "",
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\"},\"finish_reason\":\"stop\"}],\"usage\":{\"total_tokens\":9}}", "",
            "data: [DONE]", ""]
        let source = ScriptedAIStreamTransport(lines: lines)
        let text = StreamTextRecorder()
        let bridge = AITextStreamingTransport(providerID: .openRouter, transport: source) { await text.append($0) }
        let request = try Self.request()
        let response = try await bridge.send(request)
        let body = try AIJSONValue(data: response.body)
        #expect(await text.parts == ["Hi"])
        #expect(body["usage"]?["total_tokens"]?.integerValue == 9)
    }

    @Test func missingTerminalMalformedAndProviderErrorsNeverBecomeCompleteResponses() async throws {
        let cases = [
            ["data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}", ""],
            ["data: not-json", ""],
            ["data: {\"error\":{\"message\":\"secret provider detail\"}}", ""],
            ["data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"function\":{\"name\":\"execute\"}}]}}]}", ""]
        ]
        for lines in cases {
            let bridge = AITextStreamingTransport(providerID: .groq,
                transport: ScriptedAIStreamTransport(lines: lines), onTextDelta: { _ in })
            await #expect(throws: AIProviderError.self) { try await bridge.send(Self.request()) }
        }
    }

    @Test func textBoundsAndMismatchedFinalOpenAITextFailClosed() throws {
        var codec = AITextStreamCodec(providerID: .openAI)
        _ = try codec.consume("{\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}")
        _ = try codec.consume("{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"different\"}]}]}}")
        #expect(throws: AIProviderError.invalidProviderResponse) { try codec.finalJSON() }
        var oversized = AITextStreamCodec(providerID: .ollama)
        let payload = try AIJSONValue.object(["message": .object(["content": .string(String(repeating: "x", count: 256 * 1_024 + 1))])]).encodedData()
        let string = try #require(String(data: payload, encoding: .utf8))
        #expect(throws: AIProviderError.invalidProviderResponse) { try oversized.consume(string) }
    }

    @Test func callbackCancellationStopsFurtherFramesWithBackpressure() async throws {
        let source = ScriptedAIStreamTransport(lines: Self.lines(for: .groq))
        let bridge = AITextStreamingTransport(providerID: .groq, transport: source) { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await bridge.send(Self.request()) }
        #expect(await source.deliveredLineCount == 2)
    }

    @Test func unexpectedHostedToolsAndNonTextBlocksAreRejected() throws {
        var openAI = AITextStreamCodec(providerID: .openAI)
        #expect(throws: AIProviderError.unsupportedCapability) {
            try openAI.consume(#"{"type":"response.output_item.added","item":{"type":"web_search_call"}}"#)
        }
        var anthropic = AITextStreamCodec(providerID: .anthropic)
        _ = try anthropic.consume(#"{"type":"message_start","message":{"content":[]}}"#)
        #expect(throws: AIProviderError.unsupportedCapability) {
            try anthropic.consume(#"{"type":"content_block_start","content_block":{"type":"web_search_tool_result"}}"#)
        }
        var gemini = AITextStreamCodec(providerID: .googleGemini)
        #expect(throws: AIProviderError.unsupportedCapability) {
            try gemini.consume(#"{"candidates":[{"content":{"parts":[{"codeExecutionResult":{"output":"result"}}]}}]}"#)
        }
    }

    private static func request() throws -> AIHTTPRequest {
        let url = try #require(URL(string: "https://fixture.invalid/chat/completions"))
        return AIHTTPRequest(method: .post, url: url, body: try AIJSONValue.object(["model": .string("test")]).encodedData())
    }

    static func lines(for provider: AIProviderID) -> [String] {
        let payloads: [String]
        switch provider {
        case .openAI:
            payloads = [
                #"{"type":"response.output_text.delta","delta":"Hello"}"#,
                #"{"type":"response.output_text.delta","delta":" world"}"#,
                #"{"type":"response.completed","response":{"id":"fixture","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Hello world"}]}]}}"#
            ]
        case .anthropic:
            payloads = [
                #"{"type":"message_start","message":{"id":"fixture","role":"assistant","content":[],"usage":{"input_tokens":1}}}"#,
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}"#,
                #"{"type":"content_block_stop","index":0}"#,
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
                #"{"type":"message_stop"}"#
            ]
        case .googleGemini:
            payloads = [
                #"{"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}"#,
                #"{"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]},"finishReason":"STOP"}],"usageMetadata":{"totalTokenCount":3}}"#
            ]
        case .ollama:
            return [
                #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#,
                #"{"message":{"role":"assistant","content":" world"},"done":false}"#,
                #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","eval_count":2}"#
            ]
        default:
            payloads = [
                #"{"id":"fixture","choices":[{"index":0,"delta":{"content":"Hello"}}]}"#,
                #"{"id":"fixture","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":"stop"}]}"#,
                "[DONE]"
            ]
        }
        return payloads.flatMap { ["data: " + $0, ""] }
    }
}

private actor StreamTextRecorder {
    private(set) var parts: [String] = []
    func append(_ value: String) { parts.append(value) }
}

private actor ScriptedAIStreamTransport: AIHTTPStreamingTransport {
    let lines: [String]
    private(set) var requests: [AIHTTPRequest] = []
    private(set) var deliveredLineCount = 0
    init(lines: [String]) { self.lines = lines }
    func send(_ request: AIHTTPRequest, onLine: @escaping @Sendable (String) async throws -> Void) async throws -> AIHTTPResponse {
        requests.append(request)
        for line in lines {
            try Task.checkCancellation()
            deliveredLineCount += 1
            try await onLine(line)
        }
        return .init(statusCode: 200)
    }
}
