import Foundation
import Testing
@testable import AIKit

@Suite("Mistral, Groq, and xAI providers")
struct CompatibleProviderAdapterTests {
    @Test("Mistral discovery requires provider-reported chat and function capabilities")
    func mistralDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "object": "list",
          "data": [
            {
              "id": "mistral-large-latest",
              "archived": false,
              "max_context_length": 131072,
              "capabilities": {
                "completion_chat": true,
                "function_calling": true,
                "vision": true
              }
            },
            {
              "id": "chat-without-functions",
              "capabilities": {
                "completion_chat": true,
                "function_calling": false
              }
            },
            {
              "id": "archived-tool-model",
              "archived": true,
              "capabilities": {
                "completion_chat": true,
                "function_calling": true
              }
            }
          ]
        }
        """)])
        let adapter = MistralProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.mistral))

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "mistral-large-latest")
        #expect(model.contextWindow == 131_072)
        #expect(model.capabilities == [.textInput, .textOutput, .toolCalling])
        #expect(model.capabilityEvidence == .providerReported)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path == "/v1/models")
        #expect(request.headers["Authorization"] == "Bearer test-secret")
        #expect(request.headers["Accept"] == "application/json")
    }

    @Test("Groq discovery filters inactive and non-local-tool model families")
    func groqDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "object": "list",
          "data": [
            {
              "id": "llama-3.3-70b-versatile",
              "active": true,
              "context_window": 131072,
              "max_completion_tokens": 32768
            },
            {"id": "groq/compound", "active": true},
            {"id": "whisper-large-v3", "active": true},
            {"id": "canopylabs/orpheus-v1-english", "active": true},
            {"id": "meta-llama/llama-prompt-guard-2-86m", "active": true},
            {"id": "openai/gpt-oss-safeguard-20b", "active": true},
            {"id": "unknown-future-model", "active": true},
            {"id": "retired-chat-model", "active": false}
          ]
        }
        """)])
        let adapter = GroqProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.groq))

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "llama-3.3-70b-versatile")
        #expect(model.contextWindow == 131_072)
        #expect(model.maximumOutputTokens == 32_768)
        #expect(model.capabilities == [.textInput, .textOutput, .toolCalling])
        #expect(model.capabilityEvidence == .curated)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path == "/v1/models")
        #expect(request.headers["Authorization"] == "Bearer test-secret")
    }

    @Test("xAI discovery uses the language-model catalog and text modalities")
    func xAIDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "models": [
            {
              "id": "grok-4",
              "input_modalities": ["text", "image"],
              "output_modalities": ["text"]
            },
            {
              "id": "grok-4.20-multi-agent",
              "input_modalities": ["text"],
              "output_modalities": ["text"]
            },
            {
              "id": "image-only",
              "input_modalities": ["text"],
              "output_modalities": ["image"]
            },
            {
              "id": "non-text-input",
              "input_modalities": ["audio"],
              "output_modalities": ["text"]
            }
          ]
        }
        """)])
        let adapter = XAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.xAI))

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "grok-4")
        #expect(model.capabilities == [.textInput, .textOutput, .toolCalling])
        #expect(model.capabilityEvidence == .curated)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path == "/v1/language-models")
        #expect(request.headers["Authorization"] == "Bearer test-secret")
    }

    @Test("Mistral tool calls round-trip through the shared chat codec")
    func mistralToolRoundTrip() async throws {
        let transport = compatibleRoundTripTransport()
        let adapter = MistralProviderAdapter(transport: transport, baseURL: testBaseURL())

        try await assertToolRoundTrip(
            adapter: adapter,
            transport: transport,
            providerID: .mistral,
            modelID: "mistral-large-latest",
            maximumOutputTokensKey: "max_tokens"
        )
    }

    @Test("Groq tool calls round-trip through the shared chat codec")
    func groqToolRoundTrip() async throws {
        let transport = compatibleRoundTripTransport()
        let adapter = GroqProviderAdapter(transport: transport, baseURL: testBaseURL())

        try await assertToolRoundTrip(
            adapter: adapter,
            transport: transport,
            providerID: .groq,
            modelID: "llama-3.3-70b-versatile",
            maximumOutputTokensKey: "max_completion_tokens"
        )
    }

    @Test("xAI tool calls round-trip through the stateless compatibility API")
    func xAIToolRoundTrip() async throws {
        let transport = compatibleRoundTripTransport()
        let adapter = XAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        try await assertToolRoundTrip(
            adapter: adapter,
            transport: transport,
            providerID: .xAI,
            modelID: "grok-4",
            maximumOutputTokensKey: "max_tokens"
        )
    }

    @Test("All three providers map authentication failures without exposing response bodies")
    func authenticationFailureMapping() async {
        let mistral = MistralProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("{\"error\": \"mistral-secret-detail\"}", statusCode: 401)
            ]),
            baseURL: testBaseURL()
        )
        await #expect(throws: AIProviderError.invalidCredential) {
            try await mistral.models(configuration: testConfiguration(.mistral))
        }

        let groq = GroqProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("{\"error\": \"groq-secret-detail\"}", statusCode: 401)
            ]),
            baseURL: testBaseURL()
        )
        await #expect(throws: AIProviderError.invalidCredential) {
            try await groq.models(configuration: testConfiguration(.groq))
        }

        let xAI = XAIProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("{\"error\": \"xai-secret-detail\"}", statusCode: 401)
            ]),
            baseURL: testBaseURL()
        )
        await #expect(throws: AIProviderError.invalidCredential) {
            try await xAI.models(configuration: testConfiguration(.xAI))
        }
    }

    @Test("Provider cancellation stops before issuing an HTTP request")
    func cancellationBeforeTransport() async {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = GroqProviderAdapter(transport: transport, baseURL: testBaseURL())

        let error = await Task { () -> AIProviderError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await adapter.models(configuration: testConfiguration(.groq))
                return nil
            } catch let error as AIProviderError {
                return error
            } catch {
                return .invalidProviderResponse
            }
        }.value

        #expect(error == .cancelled)
        #expect(await transport.recordedRequests().isEmpty)
    }
}

private func compatibleRoundTripTransport() -> ScriptedAIHTTPTransport {
    ScriptedAIHTTPTransport(responses: [
        jsonResponse(#"""
        {
          "id": "chat-tool",
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": null,
                "tool_calls": [
                  {
                    "id": "call_compatible_1",
                    "type": "function",
                    "function": {
                      "name": "finder_list",
                      "arguments": "{\"path\":\"opaque-root-id\"}"
                    }
                  }
                ]
              },
              "finish_reason": "tool_calls"
            }
          ],
          "usage": {"prompt_tokens": 6, "completion_tokens": 2, "total_tokens": 8}
        }
        """#),
        jsonResponse("""
        {
          "id": "chat-final",
          "choices": [
            {
              "message": {"role": "assistant", "content": "Done."},
              "finish_reason": "stop"
            }
          ]
        }
        """)
    ])
}

private func assertToolRoundTrip(
    adapter: any AIProviderAdapter,
    transport: ScriptedAIHTTPTransport,
    providerID: AIProviderID,
    modelID: String,
    maximumOutputTokensKey: String
) async throws {
    let initialMessages = [AIMessage.user("List my authorized root")]
    let first = try await adapter.complete(
        request: AICompletionRequest(
            modelID: modelID,
            messages: initialMessages,
            tools: [testTool()],
            maximumOutputTokens: 1_024
        ),
        configuration: testConfiguration(providerID)
    )
    let call = try #require(first.message.toolCalls.first)
    #expect(call.id == "call_compatible_1")
    #expect(call.name == "finder_list")
    #expect(call.arguments["path"]?.stringValue == "opaque-root-id")
    #expect(first.finishReason == .toolCalls)
    #expect(first.usage?.totalTokens == 8)

    let second = try await adapter.complete(
        request: AICompletionRequest(
            modelID: modelID,
            messages: initialMessages + [
                first.message,
                .tool(results: [
                    AIToolResult(
                        callID: call.id,
                        toolName: call.name,
                        content: .object(["names": .array([.string("Example.txt")])])
                    )
                ])
            ],
            tools: [testTool()]
        ),
        configuration: testConfiguration(providerID)
    )
    #expect(second.message.content == [.text("Done.")])
    #expect(second.finishReason == .completed)

    let requests = await transport.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.url.path == "/v1/chat/completions" })
    #expect(requests.allSatisfy { $0.headers["Authorization"] == "Bearer test-secret" })
    let firstBody = try decodedBody(requests[0])
    #expect(firstBody["stream"]?.booleanValue == false)
    #expect(firstBody[maximumOutputTokensKey]?.integerValue == 1_024)
    #expect(firstBody["tools"]?.arrayValue?.first?["function"]?["name"]?.stringValue == "finder_list")

    let secondMessages = try #require(try decodedBody(requests[1])["messages"]?.arrayValue)
    let assistant = secondMessages.first { $0["role"]?.stringValue == "assistant" }
    let result = secondMessages.first { $0["role"]?.stringValue == "tool" }
    #expect(assistant?["tool_calls"]?.arrayValue?.first?["id"]?.stringValue == "call_compatible_1")
    #expect(result?["tool_call_id"]?.stringValue == "call_compatible_1")
    #expect(result?["name"] == nil)
}
