import Foundation

/// Adapter for OpenAI's Responses API.
///
/// Responses remain stateless at the provider boundary (`store: false`). When a reasoning model
/// requests local tools, the adapter retains a bounded, redacted copy of the native output items
/// needed to replay encrypted reasoning and function-call correlation on the next tool round.
public struct OpenAIProviderAdapter: AIProviderAdapter {
    private static let maximumRetainedToolRounds = 16
    private static let maximumRetainedOutputItems = 256
    private static let maximumRetainedStateBytes = 1_048_576

    public let descriptor = AIProviderDescriptor(
        id: .openAI,
        displayName: "OpenAI",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    private struct NativeToolRound {
        let outputItems: [AIJSONValue]
        let toolCalls: [AIToolCall]
        let containsReasoning: Bool
    }

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://api.openai.com/v1") ?? URL(fileURLWithPath: "/")
    }

    init(transport: any AIHTTPTransport, baseURL: URL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let credential = try requiredCredential(configuration)
        let response = try await transport.send(
            AIHTTPRequest(
                method: .get,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "models"),
                headers: try headers(credential: credential, configuration: configuration)
            )
        )
        let root = try AIProviderSupport.decode(response)
        guard let data = root["data"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        let models = data.compactMap { value -> AIModelDescriptor? in
            guard let id = value["id"]?.stringValue, Self.isToolCompatibleModel(id) else {
                return nil
            }
            return AIModelDescriptor(
                providerID: .openAI,
                id: id,
                displayName: id,
                capabilities: [.textInput, .textOutput, .toolCalling],
                capabilityEvidence: .curated
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
        let retainedToolRounds = try decodeRetainedToolRounds(request.state)

        let body = try makeRequestBody(request, retainedToolRounds: retainedToolRounds)
        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "responses"),
                headers: try headers(credential: credential, configuration: configuration),
                body: AIProviderSupport.encode(body)
            )
        )
        return try parseCompletion(
            AIProviderSupport.decode(response),
            retainedToolRounds: retainedToolRounds
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
    ) throws -> [String: String] {
        var result = [
            "Authorization": "Bearer \(credential.rawValue)",
            "Content-Type": "application/json"
        ]
        if let organization = try AIProviderSupport.validatedHeaderValue(configuration[.organizationID]) {
            result["OpenAI-Organization"] = organization
        }
        if let project = try AIProviderSupport.validatedHeaderValue(configuration[.projectID]) {
            result["OpenAI-Project"] = project
        }
        return result
    }

    private func makeRequestBody(
        _ request: AICompletionRequest,
        retainedToolRounds: [NativeToolRound]
    ) throws -> AIJSONValue {
        var body: [String: AIJSONValue] = [
            "model": .string(request.modelID),
            "input": .array(
                try makeInputItems(
                    request.messages,
                    retainedToolRounds: retainedToolRounds
                )
            ),
            // Stateless reasoning tool rounds require encrypted reasoning output so the exact
            // native item can be replayed locally without storing the response provider-side.
            "include": .array([.string("reasoning.encrypted_content")]),
            "store": .boolean(false)
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.inputSchema.jsonValue,
                    // AIKit's portable schema permits optional object properties. OpenAI strict
                    // mode requires every property to be required (optional values must instead
                    // be required and nullable), which this schema type cannot currently express.
                    "strict": .boolean(false)
                ])
            })
            body["tool_choice"] = toolChoice(request.toolChoice)
        }
        if let maximumOutputTokens = request.maximumOutputTokens {
            body["max_output_tokens"] = .number(Double(maximumOutputTokens))
        }
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        return .object(body)
    }

    private func makeInputItems(
        _ messages: [AIMessage],
        retainedToolRounds: [NativeToolRound]
    ) throws -> [AIJSONValue] {
        guard !retainedToolRounds.isEmpty else {
            return try messages.flatMap(makeInputItems)
        }

        var items: [AIJSONValue] = []
        var retainedRoundIndex = 0
        let lastUserMessageIndex = messages.lastIndex { $0.role == .user }
        for (messageIndex, message) in messages.enumerated() {
            if messageIndex > (lastUserMessageIndex ?? -1),
               retainedRoundIndex < retainedToolRounds.count {
                let retainedRound = retainedToolRounds[retainedRoundIndex]
                if !message.toolCalls.isEmpty, message.toolCalls == retainedRound.toolCalls {
                    items.append(contentsOf: retainedRound.outputItems)
                    retainedRoundIndex += 1
                    continue
                }
            }
            items.append(contentsOf: try makeInputItems(message))
        }

        guard retainedRoundIndex == retainedToolRounds.count else {
            throw AIProviderError.invalidRequest
        }
        return items
    }

    private func makeInputItems(_ message: AIMessage) throws -> [AIJSONValue] {
        var items: [AIJSONValue] = []
        if !message.content.isEmpty {
            let text = try message.content.map(contentString).joined(separator: "\n")
            items.append(.object([
                "role": .string(message.role.rawValue),
                "content": .string(text)
            ]))
        }
        items.append(contentsOf: try message.toolCalls.map { call in
            .object([
                "type": .string("function_call"),
                "call_id": .string(call.id),
                "name": .string(call.name),
                "arguments": .string(try AIProviderSupport.compactJSONString(call.arguments))
            ])
        })
        for result in message.toolResults {
            items.append(.object([
                "type": .string("function_call_output"),
                "call_id": .string(result.callID),
                "output": .string(try AIProviderSupport.toolOutputString(result.content))
            ]))
        }
        return items
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
            .object(["type": .string("function"), "name": .string(name)])
        }
    }

    private func parseCompletion(
        _ root: AIJSONValue,
        retainedToolRounds: [NativeToolRound]
    ) throws -> AICompletionResponse {
        guard let output = root["output"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        var textParts: [String] = []
        var toolCalls: [AIToolCall] = []
        var refused = false

        for item in output {
            switch item["type"]?.stringValue {
            case "message":
                for content in item["content"]?.arrayValue ?? [] {
                    switch content["type"]?.stringValue {
                    case "output_text":
                        if let text = content["text"]?.stringValue { textParts.append(text) }
                    case "refusal":
                        refused = true
                        if let text = content["refusal"]?.stringValue { textParts.append(text) }
                    default:
                        continue
                    }
                }

            case "function_call":
                toolCalls.append(
                    try nativeToolCall(
                        from: item,
                        invalidError: .invalidProviderResponse
                    )
                )

            default:
                continue
            }
        }

        guard !textParts.isEmpty || !toolCalls.isEmpty else {
            throw AIProviderError.invalidProviderResponse
        }
        let text = textParts.isEmpty ? nil : textParts.joined()
        let message = AIMessage.assistant(text, toolCalls: toolCalls)
        let finishReason = finishReason(root: root, hasToolCalls: !toolCalls.isEmpty, refused: refused)
        let id = root["id"]?.stringValue
        let state = try nextRetainedState(
            outputItems: output,
            toolCalls: toolCalls,
            responseStatus: root["status"]?.stringValue,
            retainedToolRounds: retainedToolRounds
        )

        return AICompletionResponse(
            id: id,
            message: message,
            finishReason: finishReason,
            usage: usage(root["usage"]),
            state: state
        )
    }

    private func nextRetainedState(
        outputItems: [AIJSONValue],
        toolCalls: [AIToolCall],
        responseStatus: String?,
        retainedToolRounds: [NativeToolRound]
    ) throws -> AIProviderState? {
        guard responseStatus == "completed", !toolCalls.isEmpty else { return nil }

        let containsReasoning = outputItems.contains {
            $0["type"]?.stringValue == "reasoning"
        }
        guard containsReasoning || !retainedToolRounds.isEmpty else {
            // Preserve the existing normalized path for non-reasoning Responses models.
            return nil
        }

        let currentRound = try validatedNativeToolRound(
            outputItems,
            invalidError: .invalidProviderResponse
        )
        guard currentRound.toolCalls == toolCalls else {
            throw AIProviderError.invalidProviderResponse
        }
        return try encodeRetainedToolRounds(retainedToolRounds + [currentRound])
    }

    private func decodeRetainedToolRounds(
        _ state: AIProviderState?
    ) throws -> [NativeToolRound] {
        guard let state else { return [] }
        guard
            state.providerID == .openAI,
            state.encodedByteCount <= Self.maximumRetainedStateBytes,
            let encodedString = state.decodedString(),
            let encoded = encodedString.data(using: .utf8),
            let root = try? AIJSONValue(data: encoded),
            root["version"]?.integerValue == 1,
            let encodedRounds = root["toolRounds"]?.arrayValue,
            !encodedRounds.isEmpty,
            encodedRounds.count <= Self.maximumRetainedToolRounds
        else {
            throw AIProviderError.invalidRequest
        }

        var totalOutputItems = 0
        var rounds: [NativeToolRound] = []
        rounds.reserveCapacity(encodedRounds.count)
        for encodedRound in encodedRounds {
            guard let outputItems = encodedRound.arrayValue else {
                throw AIProviderError.invalidRequest
            }
            guard outputItems.count <= Self.maximumRetainedOutputItems - totalOutputItems else {
                throw AIProviderError.invalidRequest
            }
            totalOutputItems += outputItems.count
            rounds.append(
                try validatedNativeToolRound(
                    outputItems,
                    invalidError: .invalidRequest
                )
            )
        }
        guard rounds.first?.containsReasoning == true else {
            throw AIProviderError.invalidRequest
        }
        return rounds
    }

    private func encodeRetainedToolRounds(
        _ rounds: [NativeToolRound]
    ) throws -> AIProviderState {
        guard
            !rounds.isEmpty,
            rounds.count <= Self.maximumRetainedToolRounds,
            rounds.reduce(0, { $0 + $1.outputItems.count }) <= Self.maximumRetainedOutputItems
        else {
            throw AIProviderError.invalidProviderResponse
        }

        let root = AIJSONValue.object([
            "version": .number(1),
            "toolRounds": .array(rounds.map { .array($0.outputItems) })
        ])
        let payload: Data
        do {
            payload = try root.encodedData()
        } catch {
            throw AIProviderError.invalidProviderResponse
        }
        guard payload.count <= Self.maximumRetainedStateBytes else {
            throw AIProviderError.invalidProviderResponse
        }
        return AIProviderState(providerID: .openAI, payload: payload)
    }

    private func validatedNativeToolRound(
        _ outputItems: [AIJSONValue],
        invalidError: AIProviderError
    ) throws -> NativeToolRound {
        guard !outputItems.isEmpty else { throw invalidError }

        var toolCalls: [AIToolCall] = []
        var containsReasoning = false
        for item in outputItems {
            guard item.objectValue != nil, let type = item["type"]?.stringValue, !type.isEmpty else {
                throw invalidError
            }
            switch type {
            case "reasoning":
                guard
                    let encryptedContent = item["encrypted_content"]?.stringValue,
                    !encryptedContent.isEmpty
                else {
                    // `store: false` must yield encrypted reasoning that can be replayed locally.
                    throw invalidError
                }
                containsReasoning = true
            case "function_call":
                toolCalls.append(try nativeToolCall(from: item, invalidError: invalidError))
            default:
                continue
            }
        }
        guard !toolCalls.isEmpty else { throw invalidError }
        return NativeToolRound(
            outputItems: outputItems,
            toolCalls: toolCalls,
            containsReasoning: containsReasoning
        )
    }

    private func nativeToolCall(
        from item: AIJSONValue,
        invalidError: AIProviderError
    ) throws -> AIToolCall {
        guard
            let callID = item["call_id"]?.stringValue,
            !callID.isEmpty,
            let name = item["name"]?.stringValue,
            !name.isEmpty,
            let argumentsString = item["arguments"]?.stringValue,
            let argumentsData = argumentsString.data(using: .utf8),
            let arguments = try? AIJSONValue(data: argumentsData)
        else {
            throw invalidError
        }
        return AIToolCall(id: callID, name: name, arguments: arguments)
    }

    private func finishReason(
        root: AIJSONValue,
        hasToolCalls: Bool,
        refused: Bool
    ) -> AIFinishReason {
        if root["status"]?.stringValue == "incomplete" {
            switch root["incomplete_details"]?["reason"]?.stringValue {
            case "max_output_tokens": return .length
            case "content_filter": return .contentFiltered
            default: return .unknown
            }
        }
        guard root["status"]?.stringValue == "completed" else { return .unknown }
        if refused { return .refused }
        return hasToolCalls ? .toolCalls : .completed
    }

    private func usage(_ value: AIJSONValue?) -> AIUsage? {
        guard let value else { return nil }
        return AIUsage(
            inputTokens: value["input_tokens"]?.integerValue,
            outputTokens: value["output_tokens"]?.integerValue,
            totalTokens: value["total_tokens"]?.integerValue
        )
    }

    private static func isToolCompatibleModel(_ id: String) -> Bool {
        let lowered = id.lowercased()
        let excludedFragments = [
            "audio", "embedding", "image", "instruct", "moderation", "realtime",
            "search", "transcribe", "tts"
        ]
        guard !excludedFragments.contains(where: lowered.contains) else { return false }
        let reviewedFamilies = ["gpt-4o", "gpt-4.1", "gpt-5", "o1", "o3", "o4"]
        return reviewedFamilies.contains { family in
            lowered == family
                || lowered.hasPrefix("\(family)-")
                || lowered.hasPrefix("\(family).")
        }
    }
}
