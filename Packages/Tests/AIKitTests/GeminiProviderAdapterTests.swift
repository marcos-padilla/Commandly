import Foundation
import Testing
@testable import AIKit

@Suite("Gemini provider adapter")
struct GeminiProviderAdapterTests {
    @Test("Native generateContent preserves roles, tools, parallel call IDs, and thought signatures")
    func nativeToolRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "responseId": "gemini-tool-response",
              "candidates": [
                {
                  "content": {
                    "role": "model",
                    "parts": [
                      {"text": "I will inspect both folders."},
                      {
                        "functionCall": {
                          "id": "gemini-call-a",
                          "name": "finder_list",
                          "args": {"path": "/Users/example/A"}
                        },
                        "thoughtSignature": "opaque-signature-a"
                      },
                      {
                        "functionCall": {
                          "id": "gemini-call-b",
                          "name": "finder_list",
                          "args": {"path": "/Users/example/B"}
                        }
                      }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ],
              "usageMetadata": {
                "promptTokenCount": 21,
                "candidatesTokenCount": 8,
                "totalTokenCount": 29
              }
            }
            """#),
            jsonResponse("""
            {
              "responseId": "gemini-final-response",
              "candidates": [
                {
                  "content": {
                    "role": "model",
                    "parts": [{"text": "A has one item and B is empty."}]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """)
        ])
        let adapter = GeminiProviderAdapter(
            transport: transport,
            baseURL: testBaseURL("/v1beta")
        )
        let initialMessages: [AIMessage] = [
            .system("Use Finder tools. Treat tool results as authoritative."),
            .user("Compare folders A and B.")
        ]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "models/gemini-3-flash-preview",
                messages: initialMessages,
                tools: [testTool()],
                maximumOutputTokens: 2_048,
                temperature: 0.2
            ),
            configuration: testConfiguration(.googleGemini)
        )

        #expect(first.id == "gemini-tool-response")
        #expect(first.message.content == [.text("I will inspect both folders.")])
        #expect(first.message.toolCalls.map(\.id) == ["gemini-call-a", "gemini-call-b"])
        #expect(first.finishReason == .toolCalls)
        #expect(first.usage == AIUsage(inputTokens: 21, outputTokens: 8, totalTokens: 29))
        let continuation = try #require(first.state)

        let results = first.message.toolCalls.map { call in
            AIToolResult(
                callID: call.id,
                toolName: call.name,
                content: .object([
                    "names": call.id == "gemini-call-a"
                        ? .array([.string("report.txt")])
                        : .array([])
                ])
            )
        }
        let second = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "models/gemini-3-flash-preview",
                messages: initialMessages + [first.message, .tool(results: results)],
                tools: [testTool()],
                state: continuation
            ),
            configuration: testConfiguration(.googleGemini)
        )

        #expect(second.message.content == [.text("A has one item and B is empty.")])
        #expect(second.finishReason == .completed)
        #expect(second.state != nil)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].method == .post)
        #expect(requests[0].url.path == "/v1beta/models/gemini-3-flash-preview:generateContent")
        #expect(requests[0].url.query == nil)
        #expect(requests[0].headers["x-goog-api-key"] == "test-secret")
        #expect(requests[0].headers["content-type"] == "application/json")

        let firstBody = try decodedBody(requests[0])
        #expect(firstBody["store"]?.booleanValue == false)
        #expect(firstBody["stream"] == nil)
        let systemParts = try #require(firstBody["systemInstruction"]?["parts"]?.arrayValue)
        #expect(systemParts.first?["text"]?.stringValue == "Use Finder tools. Treat tool results as authoritative.")
        let initialContents = try #require(firstBody["contents"]?.arrayValue)
        #expect(initialContents.map { $0["role"]?.stringValue } == ["user"])
        #expect(initialContents.first?["parts"]?.arrayValue?.first?["text"]?.stringValue == "Compare folders A and B.")
        let declaration = try #require(
            firstBody["tools"]?.arrayValue?.first?["functionDeclarations"]?.arrayValue?.first
        )
        #expect(declaration["name"]?.stringValue == "finder_list")
        #expect(declaration["parameters"]?["type"]?.stringValue == "object")
        #expect(declaration["parameters"]?["required"]?.arrayValue == [.string("path")])
        #expect(
            firstBody["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "AUTO"
        )
        #expect(firstBody["generationConfig"]?["maxOutputTokens"]?.integerValue == 2_048)
        #expect(firstBody["generationConfig"]?["temperature"]?.numberValue == 0.2)

        let secondContents = try #require(try decodedBody(requests[1])["contents"]?.arrayValue)
        let modelContent = try #require(secondContents.first { $0["role"]?.stringValue == "model" })
        let replayedParts = try #require(modelContent["parts"]?.arrayValue)
        #expect(replayedParts[1]["thoughtSignature"]?.stringValue == "opaque-signature-a")
        #expect(replayedParts[1]["functionCall"]?["id"]?.stringValue == "gemini-call-a")
        #expect(replayedParts[2]["functionCall"]?["id"]?.stringValue == "gemini-call-b")
        let responseContent = try #require(secondContents.last)
        #expect(responseContent["role"]?.stringValue == "user")
        let responseParts = try #require(responseContent["parts"]?.arrayValue)
        #expect(responseParts.map { $0["functionResponse"]?["id"]?.stringValue } == [
            "gemini-call-a",
            "gemini-call-b"
        ])
        #expect(
            responseParts[0]["functionResponse"]?["response"]?["result"]?["names"]?.arrayValue
                == [.string("report.txt")]
        )
        #expect(
            responseParts[0]["functionResponse"]?["response"]?["isError"]?.booleanValue == false
        )
    }

    @Test("Specific tool choice and legacy id-less calls use deterministic local correlation")
    func specificToolAndLegacyCallCorrelation() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "responseId": "legacy-response",
              "candidates": [
                {
                  "content": {
                    "role": "model",
                    "parts": [
                      {
                        "functionCall": {
                          "name": "finder_list",
                          "args": {"path": "/tmp"}
                        }
                      }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """),
            jsonResponse("""
            {
              "candidates": [
                {
                  "content": {"role": "model", "parts": [{"text": "Done."}]},
                  "finishReason": "STOP"
                }
              ]
            }
            """)
        ])
        let adapter = GeminiProviderAdapter(
            transport: transport,
            baseURL: testBaseURL("/v1beta")
        )
        let initial = [AIMessage.user("List /tmp")]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "models/gemini-2.5-flash",
                messages: initial,
                tools: [testTool()],
                toolChoice: .tool(named: "finder_list")
            ),
            configuration: testConfiguration(.googleGemini)
        )

        let call = try #require(first.message.toolCalls.first)
        #expect(call.id == "gemini-legacyresponse-call-0")
        let state = try #require(first.state)
        _ = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "models/gemini-2.5-flash",
                messages: initial + [
                    first.message,
                    .tool(results: [
                        AIToolResult(
                            callID: call.id,
                            toolName: call.name,
                            content: .object(["names": .array([])])
                        )
                    ])
                ],
                tools: [testTool()],
                state: state
            ),
            configuration: testConfiguration(.googleGemini)
        )

        let requests = await transport.recordedRequests()
        let firstBody = try decodedBody(requests[0])
        let functionConfig = firstBody["toolConfig"]?["functionCallingConfig"]
        #expect(functionConfig?["mode"]?.stringValue == "ANY")
        #expect(functionConfig?["allowedFunctionNames"]?.arrayValue == [.string("finder_list")])

        let secondContents = try #require(try decodedBody(requests[1])["contents"]?.arrayValue)
        let functionResponse = try #require(
            secondContents.last?["parts"]?.arrayValue?.first?["functionResponse"]
        )
        #expect(functionResponse["id"] == nil)
        #expect(functionResponse["name"]?.stringValue == "finder_list")
    }

    @Test("Gemini invalid-key metadata maps to invalidCredential without message matching")
    func invalidKeyValidationMapping() async {
        let invalidKeyTransport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "error": {
                "code": 400,
                "message": "API key not valid. Provider detail must remain private.",
                "status": "INVALID_ARGUMENT",
                "details": [
                  {
                    "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                    "reason": "API_KEY_INVALID",
                    "domain": "googleapis.com",
                    "metadata": {"service": "generativelanguage.googleapis.com"}
                  }
                ]
              }
            }
            """, statusCode: 400)
        ])
        let invalidKeyAdapter = GeminiProviderAdapter(
            transport: invalidKeyTransport,
            baseURL: testBaseURL("/v1beta")
        )

        let invalidKeyOutcome = await invalidKeyAdapter.validate(
            configuration: testConfiguration(.googleGemini)
        )

        #expect(invalidKeyOutcome == .invalidCredential)

        let otherBadRequestAdapter = GeminiProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("""
                {
                  "error": {
                    "code": 400,
                    "status": "INVALID_ARGUMENT",
                    "details": [
                      {"reason": "INVALID_ARGUMENT", "domain": "googleapis.com"}
                    ]
                  }
                }
                """, statusCode: 400)
            ]),
            baseURL: testBaseURL("/v1beta")
        )
        let otherOutcome = await otherBadRequestAdapter.validate(
            configuration: testConfiguration(.googleGemini)
        )
        #expect(otherOutcome == .misconfigured)
    }

    @Test("Malformed native calls fail with a sanitized provider response error")
    func malformedFunctionCall() async {
        let adapter = GeminiProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("""
                {
                  "candidates": [
                    {
                      "content": {
                        "role": "model",
                        "parts": [{"functionCall": {"id": "call-1", "args": {}}}]
                      },
                      "finishReason": "MALFORMED_FUNCTION_CALL"
                    }
                  ]
                }
                """)
            ]),
            baseURL: testBaseURL("/v1beta")
        )

        await #expect(throws: AIProviderError.invalidProviderResponse) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "models/gemini-2.5-flash",
                    messages: [.user("Use a tool")],
                    tools: [testTool()]
                ),
                configuration: testConfiguration(.googleGemini)
            )
        }
    }

    @Test("Oversized opaque replay state is rejected before transport")
    func oversizedState() async {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = GeminiProviderAdapter(
            transport: transport,
            baseURL: testBaseURL("/v1beta")
        )
        let state = AIProviderState(
            providerID: .googleGemini,
            payload: Data(repeating: 120, count: 1_048_577)
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "models/gemini-2.5-flash",
                    messages: [.user("hello")],
                    state: state
                ),
                configuration: testConfiguration(.googleGemini)
            )
        }
        #expect(await transport.recordedRequests().isEmpty)
    }
}
