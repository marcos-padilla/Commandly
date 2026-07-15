import Foundation

/// Shared stateless wire codec for reviewed OpenAI Chat Completions-compatible providers.
///
/// Provider adapters remain responsible for authentication, fixed endpoints, discovery,
/// capability evidence, and error policy. This core only normalizes the common message/tool wire
/// format and deliberately does not imply that an arbitrary OpenAI-compatible endpoint is safe.
struct OpenAIChatCompatibleAdapterCore: Sendable {
    let transport: any AIHTTPTransport
    let baseURL: URL
    let maximumOutputTokensKey: String
    let includeToolResultName: Bool

    init(
        transport: any AIHTTPTransport,
        baseURL: URL,
        maximumOutputTokensKey: String,
        includeToolResultName: Bool = false
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.maximumOutputTokensKey = maximumOutputTokensKey
        self.includeToolResultName = includeToolResultName
    }

    func complete(
        request: AICompletionRequest,
        providerID: AIProviderID,
        headers: [String: String],
        additionalBodyFields: [String: AIJSONValue] = [:]
    ) async throws -> AICompletionResponse {
        try request.validate(for: providerID)
        guard request.state == nil else { throw AIProviderError.unsupportedCapability }
        try AIProviderSupport.checkCancellation()

        let body = try makeRequestBody(
            request,
            additionalBodyFields: additionalBodyFields
        )
        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "chat/completions"),
                headers: headers,
                body: AIProviderSupport.encode(body)
            )
        )
        try AIProviderSupport.checkCancellation()
        return try parseCompletion(AIProviderSupport.decode(response))
    }

    private func makeRequestBody(
        _ request: AICompletionRequest,
        additionalBodyFields: [String: AIJSONValue]
    ) throws -> AIJSONValue {
        let reservedFields = Set([
            "model", "messages", "stream", "tools", "tool_choice",
            maximumOutputTokensKey, "temperature"
        ])
        guard additionalBodyFields.keys.allSatisfy({ !reservedFields.contains($0) }) else {
            throw AIProviderError.invalidRequest
        }

        var body = additionalBodyFields
        body["model"] = .string(request.modelID)
        body["messages"] = .array(try request.messages.flatMap(makeMessages))
        body["stream"] = .boolean(false)
        if !request.tools.isEmpty {
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
            body["tool_choice"] = toolChoice(request.toolChoice)
        }
        if let maximumOutputTokens = request.maximumOutputTokens {
            body[maximumOutputTokensKey] = .number(Double(maximumOutputTokens))
        }
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        return .object(body)
    }

    private func makeMessages(_ message: AIMessage) throws -> [AIJSONValue] {
        if message.role == .tool {
            return try message.toolResults.map { result in
                var value: [String: AIJSONValue] = [
                    "role": .string("tool"),
                    "tool_call_id": .string(result.callID),
                    "content": .string(try AIProviderSupport.toolOutputString(result.content))
                ]
                if includeToolResultName {
                    value["name"] = .string(result.toolName)
                }
                return .object(value)
            }
        }

        var value: [String: AIJSONValue] = [
            "role": .string(message.role.rawValue),
            "content": message.content.isEmpty
                ? .null
                : .string(try message.content.map(contentString).joined(separator: "\n"))
        ]
        if !message.toolCalls.isEmpty {
            value["tool_calls"] = .array(try message.toolCalls.map { call in
                .object([
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(
                            try AIProviderSupport.compactJSONString(call.arguments)
                        )
                    ])
                ])
            })
        }
        return [.object(value)]
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
        case .automatic:
            .string("auto")
        case .none:
            .string("none")
        case .required:
            .string("required")
        case let .tool(name):
            .object([
                "type": .string("function"),
                "function": .object(["name": .string(name)])
            ])
        }
    }

    private func parseCompletion(_ root: AIJSONValue) throws -> AICompletionResponse {
        guard
            let choice = root["choices"]?.arrayValue?.first,
            let message = choice["message"]
        else {
            throw AIProviderError.invalidProviderResponse
        }

        let text = responseText(message["content"])
        let calls = try (message["tool_calls"]?.arrayValue ?? []).map(parseToolCall)
        guard text != nil || !calls.isEmpty else {
            throw AIProviderError.invalidProviderResponse
        }

        return AICompletionResponse(
            id: root["id"]?.stringValue,
            message: .assistant(text, toolCalls: calls),
            finishReason: finishReason(
                choice["finish_reason"]?.stringValue,
                hasToolCalls: !calls.isEmpty
            ),
            usage: usage(root["usage"]),
            state: nil
        )
    }

    private func parseToolCall(_ value: AIJSONValue) throws -> AIToolCall {
        guard
            let id = value["id"]?.stringValue,
            let name = value["function"]?["name"]?.stringValue,
            let rawArguments = value["function"]?["arguments"]
        else {
            throw AIProviderError.invalidProviderResponse
        }

        let arguments: AIJSONValue
        if let string = rawArguments.stringValue, let data = string.data(using: .utf8) {
            do {
                arguments = try AIJSONValue(data: data)
            } catch {
                throw AIProviderError.invalidProviderResponse
            }
        } else if rawArguments.objectValue != nil {
            arguments = rawArguments
        } else {
            throw AIProviderError.invalidProviderResponse
        }
        return AIToolCall(id: id, name: name, arguments: arguments)
    }

    private func responseText(_ value: AIJSONValue?) -> String? {
        if let text = value?.stringValue { return text }
        let parts = value?.arrayValue?.compactMap { block -> String? in
            guard block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        }
        guard let parts, !parts.isEmpty else { return nil }
        return parts.joined()
    }

    private func finishReason(_ rawValue: String?, hasToolCalls: Bool) -> AIFinishReason {
        if hasToolCalls { return .toolCalls }
        return switch rawValue {
        case "stop", "completed":
            .completed
        case "tool_calls":
            .toolCalls
        case "length", "max_tokens":
            .length
        case "content_filter", "safety":
            .contentFiltered
        case "refusal", "refused":
            .refused
        case nil:
            .unknown
        default:
            .unknown
        }
    }

    private func usage(_ value: AIJSONValue?) -> AIUsage? {
        guard let value else { return nil }
        return AIUsage(
            inputTokens: value["prompt_tokens"]?.integerValue,
            outputTokens: value["completion_tokens"]?.integerValue,
            totalTokens: value["total_tokens"]?.integerValue
        )
    }
}
