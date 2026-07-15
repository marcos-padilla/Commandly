import Foundation

/// Native adapter for a loopback Ollama server.
public struct OllamaProviderAdapter: AIProviderAdapter {
    /// Matches the app bridge's maximum selectable catalog and bounds `/show` fan-out.
    private static let maximumInspectedModels = 256
    private static let maximumModelIDBytes = 1_024

    public let descriptor = AIProviderDescriptor(
        id: .ollama,
        displayName: "Ollama",
        authentication: .none,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling, .localExecution]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    /// Uses Ollama's default loopback API endpoint.
    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "http://localhost:11434/api") ?? URL(fileURLWithPath: "/")
    }

    /// Uses a custom loopback Ollama endpoint.
    ///
    /// A root URL such as `http://127.0.0.1:11434` and an API URL ending in `/api` are both
    /// accepted. Non-loopback hosts are rejected to prevent a local-provider setting from becoming
    /// an arbitrary network request primitive.
    public init(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport(),
        baseURL: URL
    ) throws {
        self.transport = transport
        self.baseURL = try Self.validatedAPIBaseURL(baseURL)
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        _ = try AIProviderSupport.validate(configuration: configuration, for: descriptor)
        try AIProviderSupport.checkCancellation()
        let tagsResponse = try await transport.send(
            AIHTTPRequest(
                method: .get,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "tags")
            )
        )
        try AIProviderSupport.checkCancellation()
        let root = try AIProviderSupport.decode(tagsResponse)
        guard let values = root["models"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        var descriptors: [AIModelDescriptor] = []
        var seen: Set<String> = []
        var inspectedModelCount = 0
        for value in values {
            try AIProviderSupport.checkCancellation()
            guard
                let id = value["name"]?.stringValue ?? value["model"]?.stringValue,
                Self.isValidModelID(id),
                seen.insert(id).inserted
            else {
                continue
            }
            guard inspectedModelCount < Self.maximumInspectedModels else { break }
            inspectedModelCount += 1
            if let descriptor = try await inspectModel(id) {
                descriptors.append(descriptor)
            }
        }
        return AIProviderSupport.sortedModels(descriptors)
    }

    private static func isValidModelID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed == id
            && id.utf8.count <= maximumModelIDBytes
    }

    public func complete(
        request: AICompletionRequest,
        configuration: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        _ = try AIProviderSupport.validate(configuration: configuration, for: descriptor)
        try request.validate(for: descriptor.id)
        guard request.state == nil else { throw AIProviderError.unsupportedCapability }
        switch request.toolChoice {
        case .automatic, .none:
            break
        case .required, .tool:
            throw AIProviderError.unsupportedCapability
        }

        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "chat"),
                headers: ["Content-Type": "application/json"],
                body: AIProviderSupport.encode(try makeRequestBody(request))
            )
        )
        return try parseCompletion(AIProviderSupport.decode(response))
    }

    private func inspectModel(_ id: String) async throws -> AIModelDescriptor? {
        try AIProviderSupport.checkCancellation()
        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "show"),
                headers: ["Content-Type": "application/json"],
                body: AIProviderSupport.encode(.object(["model": .string(id)]))
            )
        )
        try AIProviderSupport.checkCancellation()
        if response.statusCode == 404 {
            // The local model may have been removed between /tags and /show.
            return nil
        }
        let root = try AIProviderSupport.decode(response)
        let capabilities = Set(root["capabilities"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        guard capabilities.contains("completion"), capabilities.contains("tools") else {
            return nil
        }

        var modelCapabilities: Set<AIModelCapability> = [.textInput, .textOutput, .toolCalling]
        if capabilities.contains("vision") { modelCapabilities.insert(.imageInput) }
        return AIModelDescriptor(
            providerID: .ollama,
            id: id,
            displayName: id,
            contextWindow: contextWindow(root["model_info"]),
            capabilities: modelCapabilities,
            capabilityEvidence: .providerReported
        )
    }

    private func contextWindow(_ value: AIJSONValue?) -> Int? {
        guard let object = value?.objectValue else { return nil }
        return object.keys.sorted().compactMap { key -> Int? in
            guard key.lowercased().hasSuffix(".context_length") else { return nil }
            return object[key]?.integerValue
        }.first
    }

    private func makeRequestBody(_ request: AICompletionRequest) throws -> AIJSONValue {
        var body: [String: AIJSONValue] = [
            "model": .string(request.modelID),
            "messages": .array(try request.messages.flatMap(makeMessages)),
            "stream": .boolean(false)
        ]
        if !request.tools.isEmpty, request.toolChoice != .none {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.inputSchema.jsonValue
                    ])
                ])
            })
        }

        var options: [String: AIJSONValue] = [:]
        if let maximumOutputTokens = request.maximumOutputTokens {
            options["num_predict"] = .number(Double(maximumOutputTokens))
        }
        if let temperature = request.temperature {
            options["temperature"] = .number(temperature)
        }
        if !options.isEmpty { body["options"] = .object(options) }
        return .object(body)
    }

    private func makeMessages(_ message: AIMessage) throws -> [AIJSONValue] {
        if message.role == .tool {
            return try message.toolResults.map { result in
                .object([
                    "role": .string("tool"),
                    "tool_name": .string(result.toolName),
                    "content": .string(try AIProviderSupport.toolOutputString(result.content))
                ])
            }
        }

        var object: [String: AIJSONValue] = [
            "role": .string(message.role.rawValue),
            "content": .string(try message.content.map(contentString).joined(separator: "\n"))
        ]
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = .array(message.toolCalls.map { call in
                .object([
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": call.arguments
                    ])
                ])
            })
        }
        return [.object(object)]
    }

    private func contentString(_ content: AIMessageContent) throws -> String {
        switch content {
        case let .text(text): text
        case let .json(value): try AIProviderSupport.compactJSONString(value)
        }
    }

    private func parseCompletion(_ root: AIJSONValue) throws -> AICompletionResponse {
        guard let message = root["message"] else {
            throw AIProviderError.invalidProviderResponse
        }
        let text = message["content"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let calls = try (message["tool_calls"]?.arrayValue ?? []).enumerated().map { index, value in
            guard
                let name = value["function"]?["name"]?.stringValue,
                let argumentsValue = value["function"]?["arguments"]
            else {
                throw AIProviderError.invalidProviderResponse
            }
            let arguments: AIJSONValue
            if let string = argumentsValue.stringValue {
                guard
                    let data = string.data(using: .utf8),
                    let decoded = try? AIJSONValue(data: data)
                else {
                    throw AIProviderError.invalidProviderResponse
                }
                arguments = decoded
            } else {
                arguments = argumentsValue
            }
            return AIToolCall(id: "ollama-call-\(index)", name: name, arguments: arguments)
        }
        guard text != nil || !calls.isEmpty else {
            throw AIProviderError.invalidProviderResponse
        }

        let input = root["prompt_eval_count"]?.integerValue
        let output = root["eval_count"]?.integerValue
        let total = input.flatMap { input in output.map { input + $0 } }
        let usage = input == nil && output == nil
            ? nil
            : AIUsage(inputTokens: input, outputTokens: output, totalTokens: total)
        return AICompletionResponse(
            id: nil,
            message: .assistant(text, toolCalls: calls),
            finishReason: calls.isEmpty ? finishReason(root["done_reason"]?.stringValue) : .toolCalls,
            usage: usage,
            state: nil
        )
    }

    private func finishReason(_ rawValue: String?) -> AIFinishReason {
        switch rawValue {
        case "stop": .completed
        case "length": .length
        case nil: .unknown
        default: .unknown
        }
    }

    private static func validatedAPIBaseURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OllamaEndpointError.invalidURL
        }
        guard components.scheme == "http" || components.scheme == "https" else {
            throw OllamaEndpointError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw OllamaEndpointError.embeddedCredentialsOrQuery
        }
        guard let host = components.host?.lowercased(), isLoopbackHost(host) else {
            throw OllamaEndpointError.nonLoopbackHost
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch trimmedPath {
        case "":
            components.path = "/api"
        case "api":
            components.path = "/api"
        default:
            throw OllamaEndpointError.invalidBasePath
        }
        guard let validatedURL = components.url else { throw OllamaEndpointError.invalidURL }
        return validatedURL
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost")
            || host == "::1" || host == "[::1]" || host == "0:0:0:0:0:0:0:1" {
            return true
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.first == "127" else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, let value = Int(octet) else { return false }
            return (0 ... 255).contains(value)
        }
    }
}

/// Validation failures for a custom Ollama endpoint.
public enum OllamaEndpointError: Error, Sendable, Equatable {
    case invalidURL
    case unsupportedScheme
    case embeddedCredentialsOrQuery
    case nonLoopbackHost
    case invalidBasePath
}
