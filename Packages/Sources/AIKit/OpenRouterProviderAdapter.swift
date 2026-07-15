import Foundation

/// Adapter for OpenRouter's OpenAI-compatible Chat Completions API.
public struct OpenRouterProviderAdapter: AIProviderAdapter {
    private static let maximumRetainedToolRounds = 64
    private static let maximumRetainedStateBytes = 1_048_576

    public let descriptor = AIProviderDescriptor(
        id: .openRouter,
        displayName: "OpenRouter",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://openrouter.ai/api/v1") ?? URL(fileURLWithPath: "/")
    }

    init(transport: any AIHTTPTransport, baseURL: URL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func validate(configuration: AIProviderConfiguration) async -> AIProviderValidationOutcome {
        do {
            let credential = try requiredCredential(configuration)
            let response = try await transport.send(
                AIHTTPRequest(
                    method: .get,
                    url: AIProviderSupport.endpoint(baseURL: baseURL, path: "key"),
                    headers: headers(credential: credential, configuration: configuration)
                )
            )
            if let error = AIHTTPStatusMapper.error(for: response) { throw error }
            return .valid(models: try await models(configuration: configuration))
        } catch let error as AIProviderError {
            return AIProviderSupport.validationOutcome(for: error)
        } catch {
            return .unavailable
        }
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let credential = try requiredCredential(configuration)
        let response = try await transport.send(
            AIHTTPRequest(
                method: .get,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "models/user"),
                headers: headers(credential: credential, configuration: configuration)
            )
        )
        let root = try AIProviderSupport.decode(response)
        guard let data = root["data"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        let models = data.compactMap { value -> AIModelDescriptor? in
            guard
                let id = value["id"]?.stringValue,
                let parameters = value["supported_parameters"]?.arrayValue?.compactMap(\.stringValue),
                parameters.contains("tools")
            else {
                return nil
            }
            let outputModalities = value["architecture"]?["output_modalities"]?
                .arrayValue?.compactMap(\.stringValue)
            if let outputModalities, !outputModalities.contains("text") { return nil }

            return AIModelDescriptor(
                providerID: .openRouter,
                id: id,
                displayName: value["name"]?.stringValue ?? id,
                contextWindow: value["context_length"]?.integerValue,
                maximumOutputTokens: value["top_provider"]?["max_completion_tokens"]?.integerValue,
                capabilities: [.textInput, .textOutput, .toolCalling],
                capabilityEvidence: .providerReported
            )
        }
        return AIProviderSupport.sortedModels(models)
    }

    public func complete(
        request: AICompletionRequest,
        configuration: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        let credential = try requiredCredential(configuration)
        try request.validate(for: descriptor.id)
        let retainedReasoning = try decodeRetainedReasoning(request.state)

        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "chat/completions"),
                headers: headers(credential: credential, configuration: configuration),
                body: AIProviderSupport.encode(
                    try makeRequestBody(request, retainedReasoning: retainedReasoning)
                )
            )
        )
        return try parseCompletion(
            AIProviderSupport.decode(response),
            retainedReasoning: retainedReasoning
        )
    }

    private func requiredCredential(_ configuration: AIProviderConfiguration) throws -> AICredential {
        guard let credential = try AIProviderSupport.validate(configuration: configuration, for: descriptor) else {
            throw AIProviderError.credentialMissing
        }
        return credential
    }

    private func headers(
        credential: AICredential,
        configuration: AIProviderConfiguration
    ) -> [String: String] {
        var result = [
            "Authorization": "Bearer \(credential.rawValue)",
            "Content-Type": "application/json"
        ]
        if let applicationURL = safeHeaderValue(configuration[.applicationURL]) {
            result["HTTP-Referer"] = applicationURL
        }
        if let applicationName = safeHeaderValue(configuration[.applicationName]) {
            result["X-OpenRouter-Title"] = applicationName
        }
        return result
    }

    private func safeHeaderValue(_ value: String?) -> String? {
        guard
            let value,
            !value.isEmpty,
            value.count <= 1_024,
            !value.contains("\n"),
            !value.contains("\r")
        else {
            return nil
        }
        return value
    }

    private func makeRequestBody(
        _ request: AICompletionRequest,
        retainedReasoning: [String: AIJSONValue]
    ) throws -> AIJSONValue {
        var body: [String: AIJSONValue] = [
            "model": .string(request.modelID),
            "messages": .array(try request.messages.flatMap {
                try makeMessages($0, retainedReasoning: retainedReasoning)
            }),
            "provider": .object(["require_parameters": .boolean(true)])
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.inputSchema.jsonValue,
                        // OpenRouter can route to providers whose strict function-schema rules
                        // require every property to be listed in `required`. Commandly's portable
                        // schema intentionally supports optional fields, so keep provider-side
                        // strict mode disabled; the typed tool executor validates arguments locally.
                        "strict": .boolean(false)
                    ])
                ])
            })
            body["tool_choice"] = toolChoice(request.toolChoice)
        }
        if let maximumOutputTokens = request.maximumOutputTokens {
            body["max_tokens"] = .number(Double(maximumOutputTokens))
        }
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        return .object(body)
    }

    private func makeMessages(
        _ message: AIMessage,
        retainedReasoning: [String: AIJSONValue]
    ) throws -> [AIJSONValue] {
        if message.role == .tool {
            return try message.toolResults.map { result in
                .object([
                    "role": .string("tool"),
                    "tool_call_id": .string(result.callID),
                    "name": .string(result.toolName),
                    "content": .string(try AIProviderSupport.toolOutputString(result.content))
                ])
            }
        }

        var object: [String: AIJSONValue] = ["role": .string(message.role.rawValue)]
        if !message.content.isEmpty {
            object["content"] = .string(
                try message.content.map(contentString).joined(separator: "\n")
            )
        } else {
            object["content"] = .null
        }
        if !message.toolCalls.isEmpty {
            let synthesizedCalls: [AIJSONValue] = try message.toolCalls.map { call in
                AIJSONValue.object([
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(try AIProviderSupport.compactJSONString(call.arguments))
                    ])
                ])
            }
            if let firstCallID = message.toolCalls.first?.id,
               let entry = retainedReasoning[firstCallID] {
                guard let nativeCalls = entry["tool_calls"]?.arrayValue else {
                    throw AIProviderError.invalidRequest
                }
                let parsedNativeCalls: [AIToolCall]
                do {
                    parsedNativeCalls = try nativeCalls.map(parseToolCall)
                } catch {
                    throw AIProviderError.invalidRequest
                }
                guard parsedNativeCalls == message.toolCalls else {
                    throw AIProviderError.invalidRequest
                }
                object["tool_calls"] = .array(nativeCalls)
                if let details = entry["reasoning_details"] {
                    guard details.arrayValue != nil else {
                        throw AIProviderError.invalidRequest
                    }
                    object["reasoning_details"] = details
                } else if let reasoning = entry["reasoning"] {
                    guard reasoning.stringValue != nil else {
                        throw AIProviderError.invalidRequest
                    }
                    object["reasoning"] = reasoning
                }
            } else {
                object["tool_calls"] = .array(synthesizedCalls)
            }
        }
        return [.object(object)]
    }

    private func contentString(_ content: AIMessageContent) throws -> String {
        switch content {
        case let .text(text): text
        case let .json(value): try AIProviderSupport.compactJSONString(value)
        }
    }

    private func toolChoice(_ choice: AIToolChoice) -> AIJSONValue {
        switch choice {
        case .automatic: .string("auto")
        case .none: .string("none")
        case .required: .string("required")
        case let .tool(name):
            .object([
                "type": .string("function"),
                "function": .object(["name": .string(name)])
            ])
        }
    }

    private func parseCompletion(
        _ root: AIJSONValue,
        retainedReasoning: [String: AIJSONValue]
    ) throws -> AICompletionResponse {
        guard
            let choice = root["choices"]?.arrayValue?.first,
            let messageValue = choice["message"]
        else {
            throw AIProviderError.invalidProviderResponse
        }

        let text = responseText(messageValue["content"])
        let nativeCalls = messageValue["tool_calls"]?.arrayValue ?? []
        let calls = try nativeCalls.map(parseToolCall)
        guard text != nil || !calls.isEmpty else {
            throw AIProviderError.invalidProviderResponse
        }

        var nextRetainedReasoning = retainedReasoning
        if let firstCallID = calls.first?.id,
           let entry = try retainedReasoningEntry(
               message: messageValue,
               nativeCalls: nativeCalls
           ) {
            guard nextRetainedReasoning[firstCallID] == nil,
                  nextRetainedReasoning.count < Self.maximumRetainedToolRounds else {
                throw AIProviderError.invalidProviderResponse
            }
            nextRetainedReasoning[firstCallID] = entry
        }

        return AICompletionResponse(
            id: root["id"]?.stringValue,
            message: .assistant(text, toolCalls: calls),
            finishReason: finishReason(choice["finish_reason"]?.stringValue),
            usage: usage(root["usage"]),
            state: try encodeRetainedReasoning(nextRetainedReasoning)
        )
    }

    private func parseToolCall(_ value: AIJSONValue) throws -> AIToolCall {
        guard
            let id = value["id"]?.stringValue,
            id.isEmpty == false,
            let name = value["function"]?["name"]?.stringValue,
            name.isEmpty == false,
            let argumentsString = value["function"]?["arguments"]?.stringValue,
            let data = argumentsString.data(using: .utf8)
        else {
            throw AIProviderError.invalidProviderResponse
        }
        do {
            return AIToolCall(
                id: id,
                name: name,
                arguments: try AIJSONValue(data: data)
            )
        } catch {
            throw AIProviderError.invalidProviderResponse
        }
    }

    private func retainedReasoningEntry(
        message: AIJSONValue,
        nativeCalls: [AIJSONValue]
    ) throws -> AIJSONValue? {
        var entry: [String: AIJSONValue] = ["tool_calls": .array(nativeCalls)]
        if let details = message["reasoning_details"] {
            guard let values = details.arrayValue else {
                throw AIProviderError.invalidProviderResponse
            }
            if values.isEmpty == false {
                guard isValidReasoningDetails(details) else {
                    throw AIProviderError.invalidProviderResponse
                }
                entry["reasoning_details"] = details
                return .object(entry)
            }
        }

        guard let reasoning = try plaintextReasoning(message) else { return nil }
        entry["reasoning"] = .string(reasoning)
        return .object(entry)
    }

    private func plaintextReasoning(_ message: AIJSONValue) throws -> String? {
        for key in ["reasoning", "reasoning_content"] {
            guard let value = message[key] else { continue }
            if value == .null { continue }
            guard let reasoning = value.stringValue else {
                throw AIProviderError.invalidProviderResponse
            }
            if reasoning.isEmpty == false { return reasoning }
        }
        return nil
    }

    private func isValidReasoningDetails(_ value: AIJSONValue) -> Bool {
        guard let details = value.arrayValue, details.isEmpty == false else {
            return false
        }
        return details.allSatisfy { $0.objectValue != nil }
    }

    private func decodeRetainedReasoning(
        _ state: AIProviderState?
    ) throws -> [String: AIJSONValue] {
        guard let state else { return [:] }
        guard
            state.providerID == .openRouter,
            state.encodedByteCount <= Self.maximumRetainedStateBytes,
            let encoded = state.decodedString()?.data(using: .utf8),
            let root = try? AIJSONValue(data: encoded),
            let rootObject = root.objectValue,
            Set(rootObject.keys) == ["toolReasoning"],
            let entries = root["toolReasoning"]?.objectValue,
            entries.count <= Self.maximumRetainedToolRounds
        else {
            throw AIProviderError.invalidRequest
        }

        for (firstCallID, value) in entries {
            guard
                let entry = value.objectValue,
                let nativeCalls = entry["tool_calls"]?.arrayValue,
                nativeCalls.isEmpty == false,
                let parsedCalls = try? nativeCalls.map(parseToolCall),
                parsedCalls.first?.id == firstCallID,
                Set(parsedCalls.map(\.id)).count == parsedCalls.count
            else {
                throw AIProviderError.invalidRequest
            }

            if let reasoningDetails = entry["reasoning_details"] {
                guard
                    entry["reasoning"] == nil,
                    Set(entry.keys) == ["tool_calls", "reasoning_details"],
                    isValidReasoningDetails(reasoningDetails)
                else {
                    throw AIProviderError.invalidRequest
                }
            } else {
                guard
                    Set(entry.keys) == ["tool_calls", "reasoning"],
                    entry["reasoning"]?.stringValue?.isEmpty == false
                else {
                    throw AIProviderError.invalidRequest
                }
            }
        }
        return entries
    }

    private func encodeRetainedReasoning(
        _ entries: [String: AIJSONValue]
    ) throws -> AIProviderState? {
        guard entries.isEmpty == false else { return nil }
        guard entries.count <= Self.maximumRetainedToolRounds else {
            throw AIProviderError.invalidProviderResponse
        }
        let payload = try AIProviderSupport.encode(
            .object(["toolReasoning": .object(entries)])
        )
        guard payload.count <= Self.maximumRetainedStateBytes else {
            throw AIProviderError.invalidProviderResponse
        }
        return AIProviderState(providerID: .openRouter, payload: payload)
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

    private func finishReason(_ rawValue: String?) -> AIFinishReason {
        switch rawValue {
        case "stop": .completed
        case "tool_calls": .toolCalls
        case "length": .length
        case "content_filter": .contentFiltered
        case nil: .unknown
        default: .unknown
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
