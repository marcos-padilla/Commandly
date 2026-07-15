import Foundation

/// Adapter for Anthropic's Messages API.
public struct AnthropicProviderAdapter: AIProviderAdapter {
    private static let maximumModelPages = 20
    private static let modelsPerPage = 1_000

    public let descriptor = AIProviderDescriptor(
        id: .anthropic,
        displayName: "Anthropic",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://api.anthropic.com/v1") ?? URL(fileURLWithPath: "/")
    }

    init(transport: any AIHTTPTransport, baseURL: URL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let credential = try requiredCredential(configuration)
        var values: [AIJSONValue] = []
        var afterID: String?
        var seenCursors: Set<String> = []

        for pageIndex in 0 ..< Self.maximumModelPages {
            try AIProviderSupport.checkCancellation()
            let response = try await transport.send(
                AIHTTPRequest(
                    method: .get,
                    url: try modelsURL(afterID: afterID),
                    headers: headers(credential: credential)
                )
            )
            try AIProviderSupport.checkCancellation()
            let root = try AIProviderSupport.decode(response)
            guard let data = root["data"]?.arrayValue else {
                throw AIProviderError.invalidProviderResponse
            }
            values.append(contentsOf: data)

            guard root["has_more"]?.booleanValue == true else { break }
            guard
                pageIndex + 1 < Self.maximumModelPages,
                let cursor = root["last_id"]?.stringValue,
                !cursor.isEmpty,
                seenCursors.insert(cursor).inserted
            else {
                throw AIProviderError.invalidProviderResponse
            }
            afterID = cursor
        }

        var seenModelIDs: Set<String> = []
        let models = values.compactMap { value -> AIModelDescriptor? in
            guard
                let id = value["id"]?.stringValue,
                Self.isReviewedToolModel(id),
                seenModelIDs.insert(id).inserted
            else {
                return nil
            }
            let displayName = value["display_name"]?.stringValue ?? id
            let providerReportsTools = value["capabilities"]?["tool_use"]?.booleanValue
                ?? value["capabilities"]?["tools"]?.booleanValue
            if providerReportsTools == false { return nil }
            return AIModelDescriptor(
                providerID: .anthropic,
                id: id,
                displayName: displayName,
                contextWindow: value["max_input_tokens"]?.integerValue,
                maximumOutputTokens: value["max_tokens"]?.integerValue,
                capabilities: [.textInput, .textOutput, .toolCalling],
                capabilityEvidence: providerReportsTools == true ? .providerReported : .curated
            )
        }
        return AIProviderSupport.sortedModels(models)
    }

    private static func isReviewedToolModel(_ id: String) -> Bool {
        let lowered = id.lowercased()
        guard lowered.hasPrefix("claude") else { return false }
        return lowered.hasPrefix("claude-1") == false
            && lowered.hasPrefix("claude-2") == false
            && lowered.hasPrefix("claude-instant") == false
    }

    private func modelsURL(afterID: String?) throws -> URL {
        let endpoint = AIProviderSupport.endpoint(baseURL: baseURL, path: "models")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AIProviderError.invalidRequest
        }
        var queryItems = [
            URLQueryItem(name: "limit", value: String(Self.modelsPerPage))
        ]
        if let afterID {
            queryItems.append(URLQueryItem(name: "after_id", value: afterID))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw AIProviderError.invalidRequest }
        return url
    }

    public func complete(
        request: AICompletionRequest,
        configuration: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        let credential = try requiredCredential(configuration)
        try request.validate(for: descriptor.id)
        guard request.state == nil else { throw AIProviderError.unsupportedCapability }

        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "messages"),
                headers: headers(credential: credential),
                body: AIProviderSupport.encode(try makeRequestBody(request))
            )
        )
        return try parseCompletion(AIProviderSupport.decode(response))
    }

    private func requiredCredential(_ configuration: AIProviderConfiguration) throws -> AICredential {
        guard let credential = try AIProviderSupport.validate(configuration: configuration, for: descriptor) else {
            throw AIProviderError.credentialMissing
        }
        return credential
    }

    private func headers(credential: AICredential) -> [String: String] {
        [
            "x-api-key": credential.rawValue,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        ]
    }

    private func makeRequestBody(_ request: AICompletionRequest) throws -> AIJSONValue {
        let systemText = try request.messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .map(contentString)
            .joined(separator: "\n\n")

        var body: [String: AIJSONValue] = [
            "model": .string(request.modelID),
            "max_tokens": .number(Double(request.maximumOutputTokens ?? 4096)),
            "messages": .array(try request.messages
                .filter { $0.role != .system }
                .map(makeMessage))
        ]
        if !systemText.isEmpty {
            body["system"] = .string(systemText)
        }
        if !request.tools.isEmpty, request.toolChoice != .none {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.inputSchema.jsonValue,
                    "strict": .boolean(true)
                ])
            })
            body["tool_choice"] = toolChoice(request.toolChoice)
        }
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        return .object(body)
    }

    private func makeMessage(_ message: AIMessage) throws -> AIJSONValue {
        let role = message.role == .tool ? "user" : message.role.rawValue
        var content: [AIJSONValue] = try message.content.map { part in
            .object(["type": .string("text"), "text": .string(try contentString(part))])
        }
        content.append(contentsOf: message.toolCalls.map { call in
            .object([
                "type": .string("tool_use"),
                "id": .string(call.id),
                "name": .string(call.name),
                "input": call.arguments
            ])
        })
        for result in message.toolResults {
            content.append(.object([
                "type": .string("tool_result"),
                "tool_use_id": .string(result.callID),
                "content": .string(try AIProviderSupport.toolOutputString(result.content)),
                "is_error": .boolean(result.isError)
            ]))
        }
        return .object(["role": .string(role), "content": .array(content)])
    }

    private func contentString(_ content: AIMessageContent) throws -> String {
        switch content {
        case let .text(text):
            text
        case let .json(value):
            try AIProviderSupport.compactJSONString(value)
        }
    }

    private func toolChoice(_ choice: AIToolChoice) -> AIJSONValue {
        switch choice {
        case .automatic, .none:
            .object(["type": .string("auto")])
        case .required:
            .object(["type": .string("any")])
        case let .tool(name):
            .object(["type": .string("tool"), "name": .string(name)])
        }
    }

    private func parseCompletion(_ root: AIJSONValue) throws -> AICompletionResponse {
        guard let content = root["content"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }
        var textParts: [String] = []
        var toolCalls: [AIToolCall] = []

        for block in content {
            switch block["type"]?.stringValue {
            case "text":
                if let text = block["text"]?.stringValue { textParts.append(text) }
            case "tool_use":
                guard
                    let id = block["id"]?.stringValue,
                    let name = block["name"]?.stringValue,
                    let input = block["input"]
                else {
                    throw AIProviderError.invalidProviderResponse
                }
                toolCalls.append(AIToolCall(id: id, name: name, arguments: input))
            default:
                continue
            }
        }
        guard !textParts.isEmpty || !toolCalls.isEmpty else {
            throw AIProviderError.invalidProviderResponse
        }

        return AICompletionResponse(
            id: root["id"]?.stringValue,
            message: .assistant(
                textParts.isEmpty ? nil : textParts.joined(),
                toolCalls: toolCalls
            ),
            finishReason: finishReason(root["stop_reason"]?.stringValue),
            usage: usage(root["usage"]),
            state: nil
        )
    }

    private func finishReason(_ rawValue: String?) -> AIFinishReason {
        switch rawValue {
        case "end_turn", "stop_sequence": .completed
        case "tool_use": .toolCalls
        case "max_tokens": .length
        case "refusal": .refused
        case nil: .unknown
        default: .unknown
        }
    }

    private func usage(_ value: AIJSONValue?) -> AIUsage? {
        guard let value else { return nil }
        let input = value["input_tokens"]?.integerValue
        let output = value["output_tokens"]?.integerValue
        let total = input.flatMap { input in output.map { input + $0 } }
        return AIUsage(inputTokens: input, outputTokens: output, totalTokens: total)
    }
}
