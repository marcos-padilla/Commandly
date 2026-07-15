import Foundation
import Testing
@testable import AIKit

@Suite("Provider tool round trips")
struct ProviderToolRoundTripTests {
    @Test("OpenAI function calls and outputs round-trip through Responses API items")
    func openAIRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "resp_tool",
              "status": "completed",
              "output": [
                {
                  "type": "function_call",
                  "call_id": "call_1",
                  "name": "finder_list",
                  "arguments": "{\"path\":\"/Users/example\"}"
                }
              ],
              "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
            }
            """#),
            jsonResponse(#"""
            {
              "id": "resp_final",
              "status": "completed",
              "output": [
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [{"type": "output_text", "text": "I found two files."}]
                }
              ]
            }
            """#)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let initialMessages: [AIMessage] = [
            .system("Use Finder tools and do not invent results."),
            .user("What is in my folder?")
        ]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openAI)
        )

        let call = try #require(first.message.toolCalls.first)
        #expect(first.finishReason == .toolCalls)
        #expect(call.id == "call_1")
        #expect(call.name == "finder_list")
        #expect(call.arguments["path"]?.stringValue == "/Users/example")
        #expect(first.usage == AIUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15))
        #expect(first.state == nil)

        let result = AIToolResult(
            callID: call.id,
            toolName: call.name,
            content: .object(["names": .array([.string("a.txt"), .string("b.txt")])])
        )
        let second = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: initialMessages + [first.message, .tool(results: [result])],
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openAI)
        )

        #expect(second.message.content == [.text("I found two files.")])
        #expect(second.finishReason == .completed)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let firstBody = try decodedBody(requests[0])
        #expect(firstBody["store"]?.booleanValue == false)
        #expect(firstBody["include"]?.arrayValue?.compactMap(\.stringValue) == [
            "reasoning.encrypted_content"
        ])
        #expect(firstBody["tools"]?.arrayValue?.first?["name"]?.stringValue == "finder_list")
        #expect(firstBody["tools"]?.arrayValue?.first?["strict"]?.booleanValue == false)
        let secondInput = try #require(try decodedBody(requests[1])["input"]?.arrayValue)
        #expect(secondInput.contains { $0["type"]?.stringValue == "function_call" })
        #expect(secondInput.contains { $0["type"]?.stringValue == "function_call_output" })
    }

    @Test("OpenAI explicitly disables strict mode for portable schemas with optional properties")
    func openAINonStrictOptionalToolSchema() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "id": "resp_final",
              "status": "completed",
              "output": [
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [{"type": "output_text", "text": "Ready."}]
                }
              ]
            }
            """)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let optionalTool = AIToolDefinition(
            name: "finder_search",
            description: "Search an authorized folder.",
            inputSchema: .closedObject(
                properties: [
                    "query": .string(allowedValues: nil, description: nil),
                    "limit": .integer(minimum: 1, maximum: 100, description: nil)
                ],
                required: ["query"]
            ),
            effect: .readOnly,
            confirmation: .never
        )

        _ = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-4.1",
                messages: [.user("Prepare to search")],
                tools: [optionalTool]
            ),
            configuration: testConfiguration(.openAI)
        )

        let request = try #require(await transport.recordedRequests().first)
        let tool = try #require(try decodedBody(request)["tools"]?.arrayValue?.first)
        #expect(tool["strict"]?.booleanValue == false)
        #expect(tool["parameters"]?["additionalProperties"]?.booleanValue == false)
        #expect(tool["parameters"]?["required"]?.arrayValue?.compactMap(\.stringValue) == ["query"])
        #expect(tool["parameters"]?["properties"]?["limit"] != nil)
    }

    @Test("OpenAI incomplete Responses do not masquerade as completed tool rounds")
    func openAIIncompleteToolResponse() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "resp_incomplete_tool",
              "status": "incomplete",
              "incomplete_details": {"reason": "max_output_tokens"},
              "output": [
                {
                  "id": "rs_incomplete",
                  "type": "reasoning",
                  "encrypted_content": "encrypted-incomplete-reasoning",
                  "summary": []
                },
                {
                  "id": "fc_incomplete",
                  "type": "function_call",
                  "status": "incomplete",
                  "call_id": "call_incomplete",
                  "name": "finder_list",
                  "arguments": "{}"
                }
              ]
            }
            """#)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        let response = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: [.user("Use the tool")],
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openAI)
        )

        #expect(response.finishReason == .length)
        #expect(response.message.toolCalls.map(\.id) == ["call_incomplete"])
        #expect(response.state == nil)
    }

    @Test("OpenAI stateless reasoning tool rounds replay encrypted native output items")
    func openAIReasoningToolRoundReplay() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "resp_reasoning_one",
              "status": "completed",
              "output": [
                {
                  "id": "rs_1",
                  "type": "reasoning",
                  "summary": [],
                  "encrypted_content": "encrypted-reasoning-one"
                },
                {
                  "id": "fc_1",
                  "type": "function_call",
                  "status": "completed",
                  "call_id": "call_1",
                  "name": "finder_list",
                  "arguments": "{\"path\":\"/Users/example/A\"}"
                }
              ]
            }
            """#),
            jsonResponse(#"""
            {
              "id": "resp_reasoning_two",
              "status": "completed",
              "output": [
                {
                  "id": "rs_2",
                  "type": "reasoning",
                  "summary": [],
                  "encrypted_content": "encrypted-reasoning-two"
                },
                {
                  "id": "fc_2",
                  "type": "function_call",
                  "status": "completed",
                  "call_id": "call_2",
                  "name": "finder_list",
                  "arguments": "{\"path\":\"/Users/example/B\"}"
                }
              ]
            }
            """#),
            jsonResponse("""
            {
              "id": "resp_reasoning_final",
              "status": "completed",
              "output": [
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [{"type": "output_text", "text": "A and B are both empty."}]
                }
              ]
            }
            """)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let initialMessages = [AIMessage.user("Compare folders A and B")]

        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openAI)
        )
        let firstState = try #require(first.state)
        let firstCall = try #require(first.message.toolCalls.first)
        #expect(firstState.providerID == .openAI)
        #expect(firstState.encodedByteCount < 1_048_576)
        #expect(!String(reflecting: firstState).contains("encrypted-reasoning-one"))

        let firstResult = AIMessage.tool(results: [
            AIToolResult(
                callID: firstCall.id,
                toolName: firstCall.name,
                content: .object(["names": .array([])])
            )
        ])
        let second = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: initialMessages + [first.message, firstResult],
                tools: [testTool()],
                state: firstState
            ),
            configuration: testConfiguration(.openAI)
        )
        let secondState = try #require(second.state)
        let secondCall = try #require(second.message.toolCalls.first)
        #expect(secondState.encodedByteCount < 1_048_576)

        let secondResult = AIMessage.tool(results: [
            AIToolResult(
                callID: secondCall.id,
                toolName: secondCall.name,
                content: .object(["names": .array([])])
            )
        ])
        let final = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "gpt-5",
                messages: initialMessages + [
                    first.message,
                    firstResult,
                    second.message,
                    secondResult
                ],
                tools: [testTool()],
                state: secondState
            ),
            configuration: testConfiguration(.openAI)
        )

        #expect(final.message.content == [.text("A and B are both empty.")])
        #expect(final.state == nil)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 3)
        for request in requests {
            let body = try decodedBody(request)
            #expect(body["store"]?.booleanValue == false)
            #expect(body["previous_response_id"] == nil)
            #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == [
                "reasoning.encrypted_content"
            ])
        }

        let secondInput = try #require(try decodedBody(requests[1])["input"]?.arrayValue)
        let secondNativeItems = secondInput.filter { $0["type"]?.stringValue != nil }
        #expect(secondNativeItems.map { $0["type"]?.stringValue } == [
            "reasoning", "function_call", "function_call_output"
        ])
        #expect(secondNativeItems[0]["id"]?.stringValue == "rs_1")
        #expect(secondNativeItems[0]["encrypted_content"]?.stringValue == "encrypted-reasoning-one")
        #expect(secondNativeItems[1]["id"]?.stringValue == "fc_1")
        #expect(secondNativeItems[1]["status"]?.stringValue == "completed")
        #expect(secondNativeItems.filter { $0["type"]?.stringValue == "function_call" }.count == 1)

        let finalInput = try #require(try decodedBody(requests[2])["input"]?.arrayValue)
        let finalNativeItems = finalInput.filter { $0["type"]?.stringValue != nil }
        #expect(finalNativeItems.map { $0["type"]?.stringValue } == [
            "reasoning", "function_call", "function_call_output",
            "reasoning", "function_call", "function_call_output"
        ])
        #expect(finalNativeItems[3]["id"]?.stringValue == "rs_2")
        #expect(finalNativeItems[3]["encrypted_content"]?.stringValue == "encrypted-reasoning-two")
        #expect(finalNativeItems[4]["id"]?.stringValue == "fc_2")
    }

    @Test("OpenAI rejects oversized and over-count native replay state before transport")
    func openAIReplayStateBounds() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let oversizedState = AIProviderState(
            providerID: .openAI,
            payload: Data(repeating: 120, count: 1_048_577)
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "gpt-5",
                    messages: [.user("hello")],
                    state: oversizedState
                ),
                configuration: testConfiguration(.openAI)
            )
        }

        let reasoningItem = AIJSONValue.object([
            "type": .string("reasoning"),
            "encrypted_content": .string("encrypted")
        ])
        let functionCallItem = AIJSONValue.object([
            "type": .string("function_call"),
            "call_id": .string("call_1"),
            "name": .string("finder_list"),
            "arguments": .string("{}")
        ])
        let fillerItems = Array(
            repeating: AIJSONValue.object(["type": .string("message")]),
            count: 255
        )
        let overCountPayload = try AIJSONValue.object([
            "version": .number(1),
            "toolRounds": .array([
                .array([reasoningItem, functionCallItem] + fillerItems)
            ])
        ]).encodedData()
        let overCountState = AIProviderState(
            providerID: .openAI,
            payload: overCountPayload
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "gpt-5",
                    messages: [.user("hello")],
                    state: overCountState
                ),
                configuration: testConfiguration(.openAI)
            )
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("OpenAI rejects non-replayable reasoning tool output")
    func openAIReasoningWithoutEncryptedContent() async {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "resp_missing_encrypted_reasoning",
              "status": "completed",
              "output": [
                {"id": "rs_1", "type": "reasoning", "summary": []},
                {
                  "type": "function_call",
                  "call_id": "call_1",
                  "name": "finder_list",
                  "arguments": "{}"
                }
              ]
            }
            """#)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        await #expect(throws: AIProviderError.invalidProviderResponse) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "gpt-5",
                    messages: [.user("Use the tool")],
                    tools: [testTool()]
                ),
                configuration: testConfiguration(.openAI)
            )
        }
    }

    @Test("Anthropic tool_use and tool_result blocks round-trip")
    func anthropicRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "id": "msg_tool",
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "finder_list",
                  "input": {"path": "/Users/example"}
                }
              ],
              "stop_reason": "tool_use",
              "usage": {"input_tokens": 8, "output_tokens": 4}
            }
            """),
            jsonResponse("""
            {
              "id": "msg_final",
              "content": [{"type": "text", "text": "The folder is empty."}],
              "stop_reason": "end_turn",
              "usage": {"input_tokens": 15, "output_tokens": 6}
            }
            """)
        ])
        let adapter = AnthropicProviderAdapter(transport: transport, baseURL: testBaseURL())
        let initialMessages: [AIMessage] = [
            .system("Use the supplied Finder tools."),
            .user("List this folder")
        ]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "claude-sonnet-4-5",
                messages: initialMessages,
                tools: [testTool()],
                maximumOutputTokens: 1_024
            ),
            configuration: testConfiguration(.anthropic)
        )

        let call = try #require(first.message.toolCalls.first)
        #expect(call.id == "toolu_1")
        #expect(first.finishReason == .toolCalls)
        #expect(first.usage?.totalTokens == 12)

        let second = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "claude-sonnet-4-5",
                messages: initialMessages + [
                    first.message,
                    .tool(results: [
                        AIToolResult(
                            callID: call.id,
                            toolName: call.name,
                            content: .object(["names": .array([])])
                        )
                    ])
                ],
                tools: [testTool()]
            ),
            configuration: testConfiguration(.anthropic)
        )

        #expect(second.message.content == [.text("The folder is empty.")])
        let requests = await transport.recordedRequests()
        let firstBody = try decodedBody(requests[0])
        #expect(firstBody["system"]?.stringValue == "Use the supplied Finder tools.")
        #expect(firstBody["max_tokens"]?.integerValue == 1_024)
        #expect(firstBody["tools"]?.arrayValue?.first?["input_schema"]?["type"]?.stringValue == "object")
        let secondMessages = try #require(try decodedBody(requests[1])["messages"]?.arrayValue)
        let resultBlock = secondMessages
            .flatMap { $0["content"]?.arrayValue ?? [] }
            .first { $0["type"]?.stringValue == "tool_result" }
        #expect(resultBlock?["tool_use_id"]?.stringValue == "toolu_1")
        #expect(resultBlock?["is_error"]?.booleanValue == false)
    }

    @Test("OpenRouter OpenAI-compatible tool calls round-trip with routing constraints")
    func openRouterRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "gen_tool",
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": null,
                    "reasoning_details": [
                      {
                        "type": "reasoning.encrypted",
                        "data": "encrypted-reasoning-secret",
                        "id": "reasoning-1",
                        "format": "anthropic-claude-v1",
                        "index": 0
                      },
                      {
                        "type": "reasoning.summary",
                        "summary": "The folder must be listed before answering.",
                        "id": "reasoning-2",
                        "format": "anthropic-claude-v1",
                        "index": 1
                      }
                    ],
                    "tool_calls": [
                      {
                        "id": "or_call_1",
                        "type": "function",
                        "function": {
                          "name": "finder_list",
                          "arguments": "{ \"path\" : \"/Users/example\" }"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ],
              "usage": {"prompt_tokens": 9, "completion_tokens": 3, "total_tokens": 12}
            }
            """#),
            jsonResponse("""
            {
              "id": "gen_final",
              "choices": [
                {
                  "message": {"role": "assistant", "content": "Done."},
                  "finish_reason": "stop"
                }
              ]
            }
            """)
        ])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())
        let configuration = AIProviderConfiguration(
            providerID: .openRouter,
            credential: AICredential("router-secret"),
            values: [
                .applicationURL: "https://commandly.app",
                .applicationName: "Commandly"
            ]
        )
        let initialMessages = [AIMessage.user("List the folder")]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "anthropic/claude-sonnet-4.5",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: configuration
        )

        let call = try #require(first.message.toolCalls.first)
        #expect(call.id == "or_call_1")
        #expect(first.finishReason == .toolCalls)
        let state = try #require(first.state)
        #expect(state.providerID == .openRouter)
        #expect(String(describing: state).contains("encrypted-reasoning-secret") == false)
        #expect(String(reflecting: state).contains("encrypted-reasoning-secret") == false)
        #expect(
            state.customMirror.children.contains {
                String(describing: $0.value).contains("encrypted-reasoning-secret")
            } == false
        )
        let second = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "anthropic/claude-sonnet-4.5",
                messages: initialMessages + [
                    first.message,
                    .tool(results: [
                        AIToolResult(
                            callID: call.id,
                            toolName: call.name,
                            content: .string("a.txt")
                        )
                    ])
                ],
                tools: [testTool()],
                state: state
            ),
            configuration: configuration
        )

        #expect(second.message.content == [.text("Done.")])
        let requests = await transport.recordedRequests()
        #expect(requests[0].headers["Authorization"] == "Bearer router-secret")
        #expect(requests[0].headers["HTTP-Referer"] == "https://commandly.app")
        #expect(requests[0].headers["X-OpenRouter-Title"] == "Commandly")
        let firstBody = try decodedBody(requests[0])
        #expect(firstBody["provider"]?["require_parameters"]?.booleanValue == true)
        #expect(firstBody["tools"]?.arrayValue?.first?["function"]?["name"]?.stringValue == "finder_list")
        #expect(firstBody["tools"]?.arrayValue?.first?["function"]?["strict"]?.booleanValue == false)
        let secondMessages = try #require(try decodedBody(requests[1])["messages"]?.arrayValue)
        let assistantMessage = try #require(
            secondMessages.first { $0["role"]?.stringValue == "assistant" }
        )
        #expect(
            assistantMessage["tool_calls"]?.arrayValue?.first?["function"]?["arguments"]?.stringValue
                == "{ \"path\" : \"/Users/example\" }"
        )
        #expect(
            assistantMessage["reasoning_details"] == .array([
                .object([
                    "type": .string("reasoning.encrypted"),
                    "data": .string("encrypted-reasoning-secret"),
                    "id": .string("reasoning-1"),
                    "format": .string("anthropic-claude-v1"),
                    "index": .number(0)
                ]),
                .object([
                    "type": .string("reasoning.summary"),
                    "summary": .string("The folder must be listed before answering."),
                    "id": .string("reasoning-2"),
                    "format": .string("anthropic-claude-v1"),
                    "index": .number(1)
                ])
            ])
        )
        #expect(assistantMessage["reasoning"] == nil)
        let toolMessage = secondMessages.first { $0["role"]?.stringValue == "tool" }
        #expect(toolMessage?["tool_call_id"]?.stringValue == "or_call_1")
        #expect(toolMessage?["name"]?.stringValue == "finder_list")
    }

    @Test("OpenRouter plaintext reasoning is retained with its assistant tool call")
    func openRouterPlaintextReasoningRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "gen_tool",
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": null,
                    "reasoning": "Check the authorized folder before answering.\nThen summarize it.",
                    "tool_calls": [
                      {
                        "id": "or_call_reasoning",
                        "type": "function",
                        "function": {
                          "name": "finder_list",
                          "arguments": "{\"path\":\"root-1\"}"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ]
            }
            """#),
            jsonResponse("""
            {
              "id": "gen_final",
              "choices": [
                {
                  "message": {"role": "assistant", "content": "Done."},
                  "finish_reason": "stop"
                }
              ]
            }
            """)
        ])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())
        let initialMessages = [AIMessage.user("List the folder")]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "anthropic/claude-sonnet-4.5",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openRouter)
        )
        let call = try #require(first.message.toolCalls.first)
        let state = try #require(first.state)

        _ = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "anthropic/claude-sonnet-4.5",
                messages: initialMessages + [
                    first.message,
                    .tool(results: [
                        AIToolResult(
                            callID: call.id,
                            toolName: call.name,
                            content: .string("a.txt")
                        )
                    ])
                ],
                tools: [testTool()],
                state: state
            ),
            configuration: testConfiguration(.openRouter)
        )

        let requests = await transport.recordedRequests()
        let messages = try #require(try decodedBody(requests[1])["messages"]?.arrayValue)
        let assistantMessage = try #require(
            messages.first { $0["role"]?.stringValue == "assistant" }
        )
        #expect(
            assistantMessage["reasoning"]?.stringValue
                == "Check the authorized folder before answering.\nThen summarize it."
        )
        #expect(assistantMessage["reasoning_details"] == nil)
    }

    @Test("OpenRouter accepts empty optional reasoning fields on ordinary tool calls")
    func openRouterEmptyReasoningFields() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "gen_tool",
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": null,
                    "reasoning": null,
                    "reasoning_details": [],
                    "tool_calls": [
                      {
                        "id": "or_call_without_reasoning",
                        "type": "function",
                        "function": {
                          "name": "finder_list",
                          "arguments": "{\"path\":\"root-1\"}"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ]
            }
            """#)
        ])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())

        let response = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "openai/gpt-4.1",
                messages: [.user("List the folder")],
                tools: [testTool()]
            ),
            configuration: testConfiguration(.openRouter)
        )

        #expect(response.message.toolCalls.first?.id == "or_call_without_reasoning")
        #expect(response.state == nil)
    }

    @Test("OpenRouter reasoning state is bound to the exact native tool calls")
    func openRouterRejectsTamperedToolCallReplay() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse(#"""
            {
              "id": "gen_tool",
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": null,
                    "reasoning_details": [
                      {
                        "type": "reasoning.encrypted",
                        "data": "opaque-value",
                        "id": "reasoning-1",
                        "format": "anthropic-claude-v1",
                        "index": 0
                      }
                    ],
                    "tool_calls": [
                      {
                        "id": "or_call_1",
                        "type": "function",
                        "function": {
                          "name": "finder_list",
                          "arguments": "{\"path\":\"root-1\"}"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ]
            }
            """#)
        ])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())
        let configuration = testConfiguration(.openRouter)
        let initialMessages = [AIMessage.user("List the folder")]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "anthropic/claude-sonnet-4.5",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: configuration
        )
        let originalCall = try #require(first.message.toolCalls.first)
        let state = try #require(first.state)
        let tamperedCall = AIToolCall(
            id: originalCall.id,
            name: originalCall.name,
            arguments: .object(["path": .string("different-root")])
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "anthropic/claude-sonnet-4.5",
                    messages: initialMessages + [
                        .assistant(toolCalls: [tamperedCall]),
                        .tool(results: [
                            AIToolResult(
                                callID: tamperedCall.id,
                                toolName: tamperedCall.name,
                                content: .string("a.txt")
                            )
                        ])
                    ],
                    tools: [testTool()],
                    state: state
                ),
                configuration: configuration
            )
        }
        #expect(await transport.recordedRequests().count == 1)
    }

    @Test("OpenRouter rejects malformed or oversized opaque reasoning state before transport")
    func openRouterRejectsInvalidOpaqueState() async {
        let malformedTransport = ScriptedAIHTTPTransport(responses: [])
        let malformedAdapter = OpenRouterProviderAdapter(
            transport: malformedTransport,
            baseURL: testBaseURL()
        )
        let malformedState = AIProviderState(
            providerID: .openRouter,
            payload: Data(#"""
            {
              "toolReasoning": {
                "call-1": {
                  "tool_calls": [
                    {
                      "id": "call-1",
                      "type": "function",
                      "function": {"name": "finder_list", "arguments": "{}"}
                    }
                  ],
                  "reasoning_details": [{"type": "reasoning.encrypted", "data": "opaque"}],
                  "reasoning": "ambiguous-tampering"
                }
              }
            }
            """#.utf8)
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await malformedAdapter.complete(
                request: AICompletionRequest(
                    modelID: "anthropic/claude-sonnet-4.5",
                    messages: [.user("hello")],
                    state: malformedState
                ),
                configuration: testConfiguration(.openRouter)
            )
        }
        #expect(await malformedTransport.recordedRequests().isEmpty)

        let oversizedTransport = ScriptedAIHTTPTransport(responses: [])
        let oversizedAdapter = OpenRouterProviderAdapter(
            transport: oversizedTransport,
            baseURL: testBaseURL()
        )
        let oversizedState = AIProviderState(
            providerID: .openRouter,
            payload: Data(repeating: 120, count: 1_048_577)
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await oversizedAdapter.complete(
                request: AICompletionRequest(
                    modelID: "anthropic/claude-sonnet-4.5",
                    messages: [.user("hello")],
                    state: oversizedState
                ),
                configuration: testConfiguration(.openRouter)
            )
        }
        #expect(await oversizedTransport.recordedRequests().isEmpty)
    }

    @Test("Ollama native tool calls use stable synthetic call IDs and tool names")
    func ollamaRoundTrip() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                  {"function": {"name": "finder_list", "arguments": {"path": "/tmp"}}}
                ]
              },
              "done": true,
              "done_reason": "stop",
              "prompt_eval_count": 7,
              "eval_count": 2
            }
            """),
            jsonResponse("""
            {
              "message": {"role": "assistant", "content": "There is one file."},
              "done": true,
              "done_reason": "stop"
            }
            """)
        ])
        let adapter = try OllamaProviderAdapter(
            transport: transport,
            baseURL: URL(string: "http://localhost:11434") ?? URL(fileURLWithPath: "/")
        )
        let configuration = AIProviderConfiguration(providerID: .ollama)
        let initialMessages = [AIMessage.user("List /tmp")]
        let first = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "llama3.2:latest",
                messages: initialMessages,
                tools: [testTool()]
            ),
            configuration: configuration
        )

        let call = try #require(first.message.toolCalls.first)
        #expect(call.id == "ollama-call-0")
        #expect(call.arguments["path"]?.stringValue == "/tmp")
        #expect(first.usage?.totalTokens == 9)
        _ = try await adapter.complete(
            request: AICompletionRequest(
                modelID: "llama3.2:latest",
                messages: initialMessages + [
                    first.message,
                    .tool(results: [
                        AIToolResult(
                            callID: call.id,
                            toolName: call.name,
                            content: .string("example.txt")
                        )
                    ])
                ],
                tools: [testTool()]
            ),
            configuration: configuration
        )

        let requests = await transport.recordedRequests()
        let secondMessages = try #require(try decodedBody(requests[1])["messages"]?.arrayValue)
        let toolMessage = secondMessages.first { $0["role"]?.stringValue == "tool" }
        #expect(toolMessage?["tool_name"]?.stringValue == "finder_list")
        #expect(toolMessage?["content"]?.stringValue == "example.txt")
    }
}
