import Foundation
import Testing
@testable import AIKit

@Suite("Provider discovery")
struct ProviderDiscoveryTests {
    @Test("OpenAI discovery keeps reviewed Responses function families and sends scoped headers")
    func openAIDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "data": [
            {"id": "gpt-4"},
            {"id": "gpt-4-0613"},
            {"id": "gpt-4o"},
            {"id": "gpt-4o-mini-2024-07-18"},
            {"id": "gpt-4.1"},
            {"id": "gpt-4.1-nano"},
            {"id": "gpt-5"},
            {"id": "gpt-5.6-sol"},
            {"id": "gpt-50"},
            {"id": "gpt-5-image-1"},
            {"id": "gpt-4o-realtime-preview"},
            {"id": "o1-pro"},
            {"id": "o3"},
            {"id": "o4-mini"},
            {"id": "chatgpt-4o-latest"},
            {"id": "text-embedding-3-large"},
            {"id": "gpt-image-1"}
          ]
        }
        """)])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let configuration = AIProviderConfiguration(
            providerID: .openAI,
            credential: AICredential("openai-secret"),
            values: [.organizationID: "org_123", .projectID: "proj_123"]
        )

        let models = try await adapter.models(configuration: configuration)

        #expect(Set(models.map(\.id)) == Set([
            "gpt-4o",
            "gpt-4o-mini-2024-07-18",
            "gpt-4.1",
            "gpt-4.1-nano",
            "gpt-5",
            "gpt-5.6-sol",
            "o1-pro",
            "o3",
            "o4-mini"
        ]))
        #expect(models.count == 9)
        #expect(models.allSatisfy { $0.capabilities.contains(.toolCalling) })
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path == "/v1/models")
        #expect(request.headers["Authorization"] == "Bearer openai-secret")
        #expect(request.headers["OpenAI-Organization"] == "org_123")
        #expect(request.headers["OpenAI-Project"] == "proj_123")
    }

    @Test("Anthropic discovery uses provider metadata when available")
    func anthropicDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "data": [
            {
              "id": "claude-sonnet-4-5",
              "display_name": "Claude Sonnet 4.5",
              "max_input_tokens": 200000,
              "max_tokens": 64000,
              "capabilities": {"tool_use": true}
            },
            {"id": "claude-2.1"},
            {"id": "claude-instant-1.2"},
            {"id": "not-a-claude-model"}
          ]
        }
        """)])
        let adapter = AnthropicProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.anthropic))

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "claude-sonnet-4-5")
        #expect(model.contextWindow == 200_000)
        #expect(model.maximumOutputTokens == 64_000)
        #expect(model.capabilityEvidence == .providerReported)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.headers["x-api-key"] == "test-secret")
        #expect(request.headers["anthropic-version"] == "2023-06-01")
    }

    @Test("Anthropic discovery follows bounded after_id pagination")
    func anthropicPaginatedDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {
              "data": [{"id": "claude-opus-first", "display_name": "Claude Opus"}],
              "has_more": true,
              "last_id": "model_cursor_1"
            }
            """),
            jsonResponse("""
            {
              "data": [{"id": "claude-sonnet-second", "display_name": "Claude Sonnet"}],
              "has_more": false,
              "last_id": "model_cursor_2"
            }
            """)
        ])
        let adapter = AnthropicProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.anthropic))

        #expect(models.map(\.id) == ["claude-opus-first", "claude-sonnet-second"])
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let firstQuery = URLComponents(
            url: requests[0].url,
            resolvingAgainstBaseURL: false
        )?.queryItems
        let secondQuery = URLComponents(
            url: requests[1].url,
            resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(firstQuery?.contains(URLQueryItem(name: "limit", value: "1000")) == true)
        #expect(firstQuery?.contains(where: { $0.name == "after_id" }) == false)
        #expect(secondQuery?.contains(URLQueryItem(name: "after_id", value: "model_cursor_1")) == true)
    }

    @Test("Anthropic discovery rejects a repeated pagination cursor")
    func anthropicRepeatedCursor() async {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {"data": [], "has_more": true, "last_id": "repeated_cursor"}
            """),
            jsonResponse("""
            {"data": [], "has_more": true, "last_id": "repeated_cursor"}
            """)
        ])
        let adapter = AnthropicProviderAdapter(transport: transport, baseURL: testBaseURL())

        await #expect(throws: AIProviderError.invalidProviderResponse) {
            try await adapter.models(configuration: testConfiguration(.anthropic))
        }
        #expect(await transport.recordedRequests().count == 2)
    }

    @Test("OpenRouter discovery includes only text models that advertise tools")
    func openRouterDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "data": [
            {
              "id": "vendor/tool-model",
              "name": "Tool Model",
              "context_length": 128000,
              "supported_parameters": ["tools", "temperature"],
              "architecture": {"output_modalities": ["text"]},
              "top_provider": {"max_completion_tokens": 8192}
            },
            {
              "id": "vendor/plain-model",
              "supported_parameters": ["temperature"],
              "architecture": {"output_modalities": ["text"]}
            },
            {
              "id": "vendor/image-model",
              "supported_parameters": ["tools"],
              "architecture": {"output_modalities": ["image"]}
            }
          ]
        }
        """)])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())

        let models = try await adapter.models(configuration: testConfiguration(.openRouter))

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "vendor/tool-model")
        #expect(model.contextWindow == 128_000)
        #expect(model.maximumOutputTokens == 8_192)
        #expect(model.capabilityEvidence == .providerReported)
    }

    @Test("Gemini discovers key-visible generateContent models with native tool capability")
    func geminiDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [jsonResponse("""
        {
          "models": [
            {
              "name": "models/gemini-2.5-pro",
              "displayName": "Gemini 2.5 Pro",
              "inputTokenLimit": 1048576,
              "outputTokenLimit": 65536,
              "supportedGenerationMethods": ["generateContent"]
            },
            {
              "name": "models/text-embedding-004",
              "supportedGenerationMethods": ["embedContent"]
            },
            {
              "name": "models/gemini-2.5-flash-image-preview",
              "supportedGenerationMethods": ["generateContent"]
            },
            {
              "name": "models/gemma-3-27b-it",
              "supportedGenerationMethods": ["generateContent"]
            }
          ]
        }
        """)])
        let adapter = GeminiProviderAdapter(transport: transport, baseURL: testBaseURL("/v1beta"))

        let models = try await adapter.models(configuration: testConfiguration(.googleGemini))

        #expect(models.map(\.id) == ["models/gemini-2.5-pro"])
        #expect(models.first?.capabilities == [.textInput, .textOutput, .toolCalling])
        #expect(models.first?.capabilityEvidence == .curated)
        #expect(adapter.descriptor.capabilities == [.modelDiscovery, .textGeneration, .toolCalling])
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.headers["x-goog-api-key"] == "test-secret")
        #expect(!request.url.absoluteString.contains("test-secret"))
    }

    @Test("Ollama inspects model capabilities and filters models without tools")
    func ollamaDiscovery() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("""
            {"models": [{"name": "llama-tools:latest"}, {"name": "embed:latest"}]}
            """),
            jsonResponse("""
            {
              "capabilities": ["completion", "tools"],
              "model_info": {"llama.context_length": 131072}
            }
            """),
            jsonResponse("""
            {"capabilities": ["embedding"]}
            """)
        ])
        let adapter = try OllamaProviderAdapter(
            transport: transport,
            baseURL: URL(string: "http://127.0.0.1:11434") ?? URL(fileURLWithPath: "/")
        )
        let configuration = AIProviderConfiguration(providerID: .ollama)

        let models = try await adapter.models(configuration: configuration)

        let model = try #require(models.first)
        #expect(models.count == 1)
        #expect(model.id == "llama-tools:latest")
        #expect(model.contextWindow == 131_072)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.url.path) == ["/api/tags", "/api/show", "/api/show"])
        #expect(requests.allSatisfy(\.headers.isEmpty) == false)
        #expect(requests[0].headers.isEmpty)
    }

    @Test("Ollama discovery inspects at most 256 unique model IDs")
    func ollamaDiscoveryInspectionLimit() async throws {
        let invalidEntries = [
            #"{"name":""}"#,
            #"{"name":" padded "}"#,
            #"{"name":"\#(String(repeating: "x", count: 1_025))"}"#
        ]
        let modelEntries = (invalidEntries + (0 ..< 300)
            .map { #"{"name":"model-\#($0)"}"# }
        )
            .joined(separator: ",")
        let tagsResponse = jsonResponse(#"{"models":[\#(modelEntries)]}"#)
        let showResponse = jsonResponse("""
        {"capabilities": ["completion", "tools"]}
        """)
        let transport = ScriptedAIHTTPTransport(
            responses: [tagsResponse] + Array(repeating: showResponse, count: 256)
        )
        let adapter = try OllamaProviderAdapter(
            transport: transport,
            baseURL: URL(string: "http://127.0.0.1:11434") ?? URL(fileURLWithPath: "/")
        )

        let models = try await adapter.models(
            configuration: AIProviderConfiguration(providerID: .ollama)
        )

        #expect(models.count == 256)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 257)
        #expect(requests.first?.url.path == "/api/tags")
        #expect(requests.dropFirst().allSatisfy { $0.url.path == "/api/show" })
        let finalShowRequest = try #require(requests.last)
        let finalShowBody = try #require(finalShowRequest.body)
        #expect(try AIJSONValue(data: finalShowBody)["model"]?.stringValue == "model-255")
    }

    @Test("HTTP authentication errors map to sanitized typed errors")
    func authenticationErrorMapping() async {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("{\"error\": \"secret provider detail\"}", statusCode: 401)
        ])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        await #expect(throws: AIProviderError.invalidCredential) {
            try await adapter.models(configuration: testConfiguration(.openAI))
        }
        let outcome = await OpenAIProviderAdapter(
            transport: ScriptedAIHTTPTransport(responses: [
                jsonResponse("{}", statusCode: 403)
            ]),
            baseURL: testBaseURL()
        ).validate(configuration: testConfiguration(.openAI))
        #expect(outcome == .insufficientPermission)
    }
}
