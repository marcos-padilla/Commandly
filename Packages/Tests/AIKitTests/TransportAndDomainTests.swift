import Foundation
import Testing
@testable import AIKit

@Suite("Transport and domain safety")
struct TransportAndDomainTests {
    @Test("HTTP request and response diagnostics redact credentials, query values, and bodies")
    func HTTPDiagnosticRedaction() throws {
        let url = try #require(URL(string: "https://provider.test/models?pageToken=sensitive-token"))
        let request = AIHTTPRequest(
            method: .post,
            url: url,
            headers: ["Authorization": "Bearer secret-key"],
            body: Data("private Finder contents".utf8)
        )

        let description = String(reflecting: request)
        #expect(description.contains("https://provider.test/models"))
        #expect(!description.contains("secret-key"))
        #expect(!description.contains("sensitive-token"))
        #expect(!description.contains("private Finder contents"))

        var requestDump = ""
        dump(request, to: &requestDump)
        #expect(requestDump.contains("https://provider.test/models"))
        #expect(!requestDump.contains("secret-key"))
        #expect(!requestDump.contains("sensitive-token"))
        #expect(!requestDump.contains("private Finder contents"))

        let response = AIHTTPResponse(
            statusCode: 401,
            headers: ["Set-Cookie": "provider-session-secret"],
            body: Data("private provider response".utf8)
        )
        let responseDescription = String(reflecting: response)
        #expect(responseDescription.contains("statusCode: 401"))
        #expect(!responseDescription.contains("provider-session-secret"))
        #expect(!responseDescription.contains("private provider response"))

        var responseDump = ""
        dump(response, to: &responseDump)
        #expect(!responseDump.contains("provider-session-secret"))
        #expect(!responseDump.contains("private provider response"))
    }

    @Test("Production transport configuration does not share cookies, credentials, or caches")
    func productionSessionPrivacy() {
        let configuration = URLSessionAIHTTPTransport.productionConfiguration()

        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("Redirect policy permits only the exact scheme, host, and effective port")
    func sameOriginRedirectPolicy() throws {
        let origin = try #require(URL(string: "https://api.example.test/v1/models"))
        let sameEffectivePort = try #require(
            URL(string: "https://API.EXAMPLE.TEST:443/v1/models?page=2")
        )
        let changedScheme = try #require(URL(string: "http://api.example.test/v1/models"))
        let changedHost = try #require(URL(string: "https://attacker.example/v1/models"))
        let changedPort = try #require(URL(string: "https://api.example.test:444/v1/models"))
        let loopbackAlias = try #require(URL(string: "https://127.0.0.1/v1/models"))

        #expect(AIHTTPRedirectPolicy.isSameOrigin(origin, sameEffectivePort))
        #expect(!AIHTTPRedirectPolicy.isSameOrigin(origin, changedScheme))
        #expect(!AIHTTPRedirectPolicy.isSameOrigin(origin, changedHost))
        #expect(!AIHTTPRedirectPolicy.isSameOrigin(origin, changedPort))
        #expect(!AIHTTPRedirectPolicy.isSameOrigin(origin, loopbackAlias))
    }

    @Test("Redirect delegate rejects a cross-origin Location without network access")
    func redirectDelegateRejection() async throws {
        let origin = try #require(URL(string: "http://localhost:11434/api/chat"))
        let external = try #require(URL(string: "https://attacker.example/collect"))
        let response = try #require(HTTPURLResponse(
            url: origin,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": external.absoluteString]
        ))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: origin)
        let redirectedRequest = URLRequest(url: external)
        let delegate = AISameOriginRedirectDelegate()

        let decision = await withCheckedContinuation { continuation in
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: redirectedRequest
            ) { request in
                continuation.resume(returning: request)
            }
        }
        session.invalidateAndCancel()

        #expect(decision == nil)
    }

    @Test("Payload size policy accepts exact bounds and rejects oversized data")
    func payloadSizeLimits() throws {
        try AIHTTPPayloadSizePolicy.validateRequestBodySize(
            AIHTTPPayloadSizePolicy.maximumRequestBodyBytes
        )
        try AIHTTPPayloadSizePolicy.validateResponseBodySize(
            AIHTTPPayloadSizePolicy.maximumResponseBodyBytes
        )

        #expect(throws: AIProviderError.invalidRequest) {
            try AIHTTPPayloadSizePolicy.validateRequestBodySize(
                AIHTTPPayloadSizePolicy.maximumRequestBodyBytes + 1
            )
        }
        #expect(throws: AIProviderError.invalidProviderResponse) {
            try AIHTTPPayloadSizePolicy.validateResponseBodySize(
                AIHTTPPayloadSizePolicy.maximumResponseBodyBytes + 1
            )
        }

        _ = try AIHTTPResponseBodyAccumulator(declaredByteCount: 3, maximumBytes: 3)
        #expect(throws: AIProviderError.invalidProviderResponse) {
            _ = try AIHTTPResponseBodyAccumulator(declaredByteCount: 4, maximumBytes: 3)
        }

        var streamedBody = try AIHTTPResponseBodyAccumulator(
            declaredByteCount: -1,
            maximumBytes: 3
        )
        try streamedBody.append(1)
        try streamedBody.append(2)
        try streamedBody.append(3)
        #expect(streamedBody.body == Data([1, 2, 3]))
        #expect(throws: AIProviderError.invalidProviderResponse) {
            try streamedBody.append(4)
        }
    }

    @Test("HTTP status mapping is deterministic and never includes provider bodies")
    func statusMapping() {
        let cases: [(Int, AIProviderError)] = [
            (400, .invalidRequest),
            (401, .invalidCredential),
            (402, .billingUnavailable),
            (403, .insufficientPermission),
            (404, .modelUnavailable),
            (500, .serviceUnavailable)
        ]

        for (status, expected) in cases {
            let response = AIHTTPResponse(
                statusCode: status,
                body: Data("credential=should-never-escape".utf8)
            )
            let error = AIHTTPStatusMapper.error(for: response)
            #expect(error == expected)
            #expect(!String(describing: error).contains("should-never-escape"))
        }

        let rateLimit = AIHTTPResponse(
            statusCode: 429,
            headers: ["retry-after": "2.5"]
        )
        #expect(AIHTTPStatusMapper.error(for: rateLimit) == .rateLimited(retryAfterSeconds: 2.5))
    }

    @Test("Portable schemas encode closed objects and reject inconsistent requirements")
    func schemaValidationAndEncoding() throws {
        let schema = AIJSONSchema.closedObject(
            properties: [
                "path": .string(allowedValues: nil, description: nil),
                "limit": .integer(minimum: 1, maximum: 100, description: nil)
            ],
            required: ["path"]
        )

        try schema.validate()
        let encoded = try AIJSONValue(data: JSONEncoder().encode(schema))
        #expect(encoded["type"]?.stringValue == "object")
        #expect(encoded["additionalProperties"]?.booleanValue == false)
        #expect(encoded["properties"]?["limit"]?["maximum"]?.integerValue == 100)

        let invalid = AIJSONSchema.closedObject(
            properties: [:],
            required: ["missing"]
        )
        #expect(throws: AIJSONSchemaError.requiredPropertyMissingFromSchema) {
            try invalid.validate()
        }
    }

    @Test("Tool definitions retain local execution policy but serialize portable schemas")
    func toolPolicy() throws {
        let tool = testTool()
        try tool.validate()

        #expect(tool.effect == .readOnly)
        #expect(tool.confirmation == .never)
        #expect(tool.inputSchema.jsonValue["additionalProperties"]?.booleanValue == false)
    }

    @Test("Custom Ollama endpoints accept only normalized loopback URLs")
    func ollamaEndpointValidation() throws {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let root = try #require(URL(string: "http://localhost:22334"))
        _ = try OllamaProviderAdapter(transport: transport, baseURL: root)

        let remote = try #require(URL(string: "https://example.com"))
        #expect(throws: OllamaEndpointError.nonLoopbackHost) {
            _ = try OllamaProviderAdapter(transport: transport, baseURL: remote)
        }

        let deceptiveHost = try #require(URL(string: "http://127.evil.example"))
        #expect(throws: OllamaEndpointError.nonLoopbackHost) {
            _ = try OllamaProviderAdapter(transport: transport, baseURL: deceptiveHost)
        }

        let unexpectedPath = try #require(URL(string: "http://localhost:11434/private"))
        #expect(throws: OllamaEndpointError.invalidBasePath) {
            _ = try OllamaProviderAdapter(transport: transport, baseURL: unexpectedPath)
        }
    }

    @Test("Registry exposes stable provider metadata")
    func standardRegistry() throws {
        let registry = try AIProviderRegistry.standard(
            transport: ScriptedAIHTTPTransport(responses: [])
        )

        #expect(registry.providers.count == 8)
        #expect(try registry.adapter(for: .openAI).descriptor.displayName == "OpenAI")
        #expect(try registry.adapter(for: .mistral).descriptor.displayName == "Mistral AI")
        #expect(try registry.adapter(for: .groq).descriptor.displayName == "Groq")
        #expect(try registry.adapter(for: .xAI).descriptor.displayName == "xAI")
        #expect(try registry.adapter(for: .ollama).descriptor.capabilities.contains(.localExecution))
    }

    @Test("Provider and continuation-state mismatches fail before transport")
    func configurationMismatch() async {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())

        await #expect(throws: AIProviderError.configurationMismatch) {
            try await adapter.complete(
                request: AICompletionRequest(modelID: "gpt-5", messages: [.user("hello")]),
                configuration: testConfiguration(.anthropic)
            )
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("Oversized credentials fail before transport")
    func oversizedCredentialFailsBeforeTransport() async {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = OpenAIProviderAdapter(transport: transport, baseURL: testBaseURL())
        let configuration = AIProviderConfiguration(
            providerID: .openAI,
            credential: AICredential(String(repeating: "k", count: 8_193))
        )

        await #expect(throws: AIProviderError.invalidCredential) {
            _ = try await adapter.models(configuration: configuration)
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("Gemini rejects model path injection before transport")
    func geminiRejectsUnsafeModelID() async {
        let transport = ScriptedAIHTTPTransport(responses: [])
        let adapter = GeminiProviderAdapter(
            transport: transport,
            baseURL: testBaseURL("/v1beta")
        )

        await #expect(throws: AIProviderError.invalidRequest) {
            try await adapter.complete(
                request: AICompletionRequest(
                    modelID: "models/gemini-2.5-pro/../../secrets",
                    messages: [.user("hello")]
                ),
                configuration: testConfiguration(.googleGemini)
            )
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("OpenRouter validation checks the key before returning key-scoped models")
    func openRouterValidation() async throws {
        let transport = ScriptedAIHTTPTransport(responses: [
            jsonResponse("{\"data\": {\"label\": \"commandly\"}}"),
            jsonResponse("{\"data\": []}")
        ])
        let adapter = OpenRouterProviderAdapter(transport: transport, baseURL: testBaseURL())

        let outcome = await adapter.validate(configuration: testConfiguration(.openRouter))

        #expect(outcome == .valid(models: []))
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.url.path) == ["/v1/key", "/v1/models/user"])
    }
}
