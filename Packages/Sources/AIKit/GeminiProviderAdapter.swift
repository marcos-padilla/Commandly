import Foundation

/// Adapter for Google's native Gemini `generateContent` API.
///
/// Gemini is stateless at the HTTP boundary. The opaque response state retained here contains only
/// native function-call parts needed to correlate local function responses and replay Gemini 3
/// thought signatures without exposing provider-specific wire data to application code.
public struct GeminiProviderAdapter: AIProviderAdapter {
    private static let maximumModelPages = 20
    private static let modelsPerPage = 1_000
    private static let maximumRetainedToolCalls = 512
    private static let maximumRetainedStateBytes = 1_048_576

    public let descriptor = AIProviderDescriptor(
        id: .googleGemini,
        displayName: "Google Gemini",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")
            ?? URL(fileURLWithPath: "/")
    }

    init(transport: any AIHTTPTransport, baseURL: URL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let credential = try requiredCredential(configuration)
        var pageToken: String?
        var seenTokens: Set<String> = []
        var seenModelIDs: Set<String> = []
        var discovered: [AIModelDescriptor] = []

        for pageIndex in 0 ..< Self.maximumModelPages {
            try AIProviderSupport.checkCancellation()
            let response = try await transport.send(
                AIHTTPRequest(
                    method: .get,
                    url: try modelsURL(pageToken: pageToken),
                    headers: authenticationHeaders(credential: credential)
                )
            )
            try AIProviderSupport.checkCancellation()
            let root = try decode(response)
            guard let models = root["models"]?.arrayValue else {
                throw AIProviderError.invalidProviderResponse
            }
            for model in models {
                guard
                    let descriptor = modelDescriptor(model),
                    seenModelIDs.insert(descriptor.id).inserted
                else {
                    continue
                }
                discovered.append(descriptor)
            }

            guard let nextPageToken = root["nextPageToken"]?.stringValue,
                  !nextPageToken.isEmpty else {
                break
            }
            guard
                pageIndex + 1 < Self.maximumModelPages,
                seenTokens.insert(nextPageToken).inserted
            else {
                throw AIProviderError.invalidProviderResponse
            }
            pageToken = nextPageToken
        }

        return AIProviderSupport.sortedModels(discovered)
    }

    public func complete(
        request: AICompletionRequest,
        configuration: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        let credential = try requiredCredential(configuration)
        try request.validate(for: descriptor.id)
        try AIProviderSupport.checkCancellation()

        let retainedToolParts = try decodeRetainedToolParts(request.state)
        let response = try await transport.send(
            AIHTTPRequest(
                method: .post,
                url: try generateContentURL(modelID: request.modelID),
                headers: authenticationHeaders(
                    credential: credential,
                    contentType: "application/json"
                ),
                body: AIProviderSupport.encode(
                    try makeRequestBody(request, retainedToolParts: retainedToolParts)
                )
            )
        )
        try AIProviderSupport.checkCancellation()
        return try parseCompletion(
            decode(response),
            retainedToolParts: retainedToolParts
        )
    }

    private func requiredCredential(_ configuration: AIProviderConfiguration) throws -> AICredential {
        guard let credential = try AIProviderSupport.validate(
            configuration: configuration,
            for: descriptor
        ) else {
            throw AIProviderError.credentialMissing
        }
        return credential
    }

    private func authenticationHeaders(
        credential: AICredential,
        contentType: String? = nil
    ) -> [String: String] {
        var headers = ["x-goog-api-key": credential.rawValue]
        if let contentType {
            headers["content-type"] = contentType
        }
        return headers
    }

    private func modelsURL(pageToken: String?) throws -> URL {
        let endpoint = AIProviderSupport.endpoint(baseURL: baseURL, path: "models")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AIProviderError.invalidRequest
        }
        var queryItems = [
            URLQueryItem(name: "pageSize", value: String(Self.modelsPerPage))
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw AIProviderError.invalidRequest }
        return url
    }

    private func generateContentURL(modelID: String) throws -> URL {
        guard Self.isValidModelID(modelID) else { throw AIProviderError.invalidRequest }
        return AIProviderSupport.endpoint(
            baseURL: baseURL,
            path: "\(modelID):generateContent"
        )
    }

    private static func isValidModelID(_ modelID: String) -> Bool {
        let prefix = "models/"
        guard modelID.hasPrefix(prefix) else { return false }
        let name = modelID.dropFirst(prefix.count)
        guard !name.isEmpty, name.count <= 256 else { return false }
        return name.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 45
                || byte == 46
                || byte == 95
        }
    }

    private func modelDescriptor(_ value: AIJSONValue) -> AIModelDescriptor? {
        guard
            let id = value["name"]?.stringValue,
            Self.isValidModelID(id),
            Self.isCuratedToolModelID(id),
            let methods = value["supportedGenerationMethods"]?.arrayValue?.compactMap(\.stringValue),
            methods.contains("generateContent")
        else {
            return nil
        }
        return AIModelDescriptor(
            providerID: .googleGemini,
            id: id,
            displayName: value["displayName"]?.stringValue ?? id,
            contextWindow: value["inputTokenLimit"]?.integerValue,
            maximumOutputTokens: value["outputTokenLimit"]?.integerValue,
            capabilities: [.textInput, .textOutput, .toolCalling],
            capabilityEvidence: .curated
        )
    }

    private static func isCuratedToolModelID(_ modelID: String) -> Bool {
        let name = modelID.dropFirst("models/".count).lowercased()
        guard name.hasPrefix("gemini-") else { return false }
        let unsupportedRuntimeMarkers = [
            "embedding",
            "image",
            "native-audio",
            "tts"
        ]
        return !unsupportedRuntimeMarkers.contains { name.contains($0) }
    }

    private func makeRequestBody(
        _ request: AICompletionRequest,
        retainedToolParts: [String: AIJSONValue]
    ) throws -> AIJSONValue {
        if request.tools.isEmpty {
            switch request.toolChoice {
            case .required, .tool:
                throw AIProviderError.invalidRequest
            case .automatic, .none:
                break
            }
        }

        let systemParts = try request.messages
            .filter { $0.role == .system }
            .flatMap(\.content)
            .map(textPart)
        let contents = try request.messages
            .filter { $0.role != .system }
            .map { try makeContent($0, retainedToolParts: retainedToolParts) }

        var body: [String: AIJSONValue] = [
            "contents": .array(contents),
            "store": .boolean(false)
        ]
        if !systemParts.isEmpty {
            body["systemInstruction"] = .object(["parts": .array(systemParts)])
        }
        if !request.tools.isEmpty {
            body["tools"] = .array([
                .object([
                    "functionDeclarations": .array(request.tools.map(functionDeclaration))
                ])
            ])
            body["toolConfig"] = toolConfig(request.toolChoice)
        }

        var generationConfig: [String: AIJSONValue] = [:]
        if let maximumOutputTokens = request.maximumOutputTokens {
            generationConfig["maxOutputTokens"] = .number(Double(maximumOutputTokens))
        }
        if let temperature = request.temperature {
            generationConfig["temperature"] = .number(temperature)
        }
        if !generationConfig.isEmpty {
            body["generationConfig"] = .object(generationConfig)
        }
        return .object(body)
    }

    private func makeContent(
        _ message: AIMessage,
        retainedToolParts: [String: AIJSONValue]
    ) throws -> AIJSONValue {
        var parts = try message.content.map(textPart)

        switch message.role {
        case .assistant:
            for call in message.toolCalls {
                guard let part = retainedToolParts[call.id],
                      let functionCall = part["functionCall"],
                      functionCall["name"]?.stringValue == call.name,
                      (functionCall["args"] ?? .object([:])) == call.arguments,
                      functionCall["id"]?.stringValue.map({ $0 == call.id }) ?? true else {
                    throw AIProviderError.invalidRequest
                }
                parts.append(part)
            }

        case .tool:
            for result in message.toolResults {
                guard let originalPart = retainedToolParts[result.callID],
                      let originalCall = originalPart["functionCall"],
                      originalCall["name"]?.stringValue == result.toolName else {
                    throw AIProviderError.invalidRequest
                }
                var functionResponse: [String: AIJSONValue] = [
                    "name": .string(result.toolName),
                    "response": .object([
                        "result": result.content,
                        "isError": .boolean(result.isError)
                    ])
                ]
                if let nativeID = originalCall["id"]?.stringValue {
                    guard nativeID == result.callID else {
                        throw AIProviderError.invalidRequest
                    }
                    functionResponse["id"] = .string(nativeID)
                }
                parts.append(.object(["functionResponse": .object(functionResponse)]))
            }

        case .system, .user:
            break
        }

        let role = message.role == .assistant ? "model" : "user"
        return .object([
            "role": .string(role),
            "parts": .array(parts)
        ])
    }

    private func textPart(_ content: AIMessageContent) throws -> AIJSONValue {
        .object(["text": .string(try contentString(content))])
    }

    private func contentString(_ content: AIMessageContent) throws -> String {
        switch content {
        case let .text(text):
            text
        case let .json(value):
            try AIProviderSupport.compactJSONString(value)
        }
    }

    private func functionDeclaration(_ tool: AIToolDefinition) -> AIJSONValue {
        .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "parameters": tool.inputSchema.jsonValue
        ])
    }

    private func toolConfig(_ choice: AIToolChoice) -> AIJSONValue {
        var functionCallingConfig: [String: AIJSONValue]
        switch choice {
        case .automatic:
            functionCallingConfig = ["mode": .string("AUTO")]
        case .none:
            functionCallingConfig = ["mode": .string("NONE")]
        case .required:
            functionCallingConfig = ["mode": .string("ANY")]
        case let .tool(name):
            functionCallingConfig = [
                "mode": .string("ANY"),
                "allowedFunctionNames": .array([.string(name)])
            ]
        }
        return .object([
            "functionCallingConfig": .object(functionCallingConfig)
        ])
    }

    private func parseCompletion(
        _ root: AIJSONValue,
        retainedToolParts: [String: AIJSONValue]
    ) throws -> AICompletionResponse {
        guard
            let candidate = root["candidates"]?.arrayValue?.first,
            let parts = candidate["content"]?["parts"]?.arrayValue
        else {
            throw AIProviderError.invalidProviderResponse
        }

        var text: [AIMessageContent] = []
        var toolCalls: [AIToolCall] = []
        var nextToolParts = retainedToolParts

        for (partIndex, part) in parts.enumerated() {
            if let value = part["text"]?.stringValue, !value.isEmpty {
                text.append(.text(value))
            }
            guard let functionCall = part["functionCall"] else { continue }
            guard
                let name = functionCall["name"]?.stringValue,
                !name.isEmpty
            else {
                throw AIProviderError.invalidProviderResponse
            }
            let arguments = functionCall["args"] ?? .object([:])
            guard arguments.objectValue != nil else {
                throw AIProviderError.invalidProviderResponse
            }

            let callID: String
            if let nativeID = functionCall["id"]?.stringValue, !nativeID.isEmpty {
                callID = nativeID
            } else {
                callID = syntheticCallID(
                    responseID: root["responseId"]?.stringValue,
                    partIndex: partIndex,
                    retainedToolParts: nextToolParts
                )
            }
            guard nextToolParts[callID] == nil else {
                throw AIProviderError.invalidProviderResponse
            }
            nextToolParts[callID] = part
            toolCalls.append(AIToolCall(id: callID, name: name, arguments: arguments))
        }

        guard !text.isEmpty || !toolCalls.isEmpty,
              nextToolParts.count <= Self.maximumRetainedToolCalls else {
            throw AIProviderError.invalidProviderResponse
        }

        return AICompletionResponse(
            id: root["responseId"]?.stringValue,
            message: AIMessage(role: .assistant, content: text, toolCalls: toolCalls),
            finishReason: toolCalls.isEmpty
                ? finishReason(candidate["finishReason"]?.stringValue)
                : .toolCalls,
            usage: usage(root["usageMetadata"]),
            state: try encodeRetainedToolParts(nextToolParts)
        )
    }

    private func syntheticCallID(
        responseID: String?,
        partIndex: Int,
        retainedToolParts: [String: AIJSONValue]
    ) -> String {
        let responseComponent = responseID?
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(64)
            .map(String.init)
            .joined()
        let base = "gemini-\(responseComponent?.isEmpty == false ? responseComponent ?? "" : "response")-call-\(partIndex)"
        var candidate = base
        var suffix = 1
        while retainedToolParts[candidate] != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func finishReason(_ rawValue: String?) -> AIFinishReason {
        switch rawValue {
        case "STOP": .completed
        case "MAX_TOKENS": .length
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY":
            .contentFiltered
        case "MALFORMED_FUNCTION_CALL", "LANGUAGE", "OTHER", nil:
            .unknown
        default:
            .unknown
        }
    }

    private func usage(_ value: AIJSONValue?) -> AIUsage? {
        guard let value else { return nil }
        return AIUsage(
            inputTokens: value["promptTokenCount"]?.integerValue,
            outputTokens: value["candidatesTokenCount"]?.integerValue,
            totalTokens: value["totalTokenCount"]?.integerValue
        )
    }

    private func decodeRetainedToolParts(
        _ state: AIProviderState?
    ) throws -> [String: AIJSONValue] {
        guard let state else { return [:] }
        guard
            state.providerID == .googleGemini,
            state.encodedByteCount <= Self.maximumRetainedStateBytes,
            let encodedString = state.decodedString(),
            let encoded = encodedString.data(using: .utf8),
            let root = try? AIJSONValue(data: encoded),
            let parts = root["functionCallParts"]?.objectValue,
            parts.count <= Self.maximumRetainedToolCalls
        else {
            throw AIProviderError.invalidRequest
        }
        for (callID, part) in parts {
            guard
                !callID.isEmpty,
                callID.count <= 256,
                let functionCall = part["functionCall"],
                functionCall["name"]?.stringValue?.isEmpty == false,
                (functionCall["args"] ?? .object([:])).objectValue != nil,
                functionCall["id"]?.stringValue.map({ $0 == callID }) ?? true
            else {
                throw AIProviderError.invalidRequest
            }
        }
        return parts
    }

    private func encodeRetainedToolParts(
        _ parts: [String: AIJSONValue]
    ) throws -> AIProviderState? {
        guard !parts.isEmpty else { return nil }
        let payload = try AIProviderSupport.encode(
            .object(["functionCallParts": .object(parts)])
        )
        guard payload.count <= Self.maximumRetainedStateBytes else {
            throw AIProviderError.invalidProviderResponse
        }
        return AIProviderState(
            providerID: .googleGemini,
            payload: payload
        )
    }

    private func decode(_ response: AIHTTPResponse) throws -> AIJSONValue {
        if isInvalidCredentialResponse(response) {
            throw AIProviderError.invalidCredential
        }
        return try AIProviderSupport.decode(response)
    }

    private func isInvalidCredentialResponse(_ response: AIHTTPResponse) -> Bool {
        guard
            response.statusCode == 400,
            let root = try? AIJSONValue(data: response.body),
            root["error"]?["status"]?.stringValue == "INVALID_ARGUMENT",
            let details = root["error"]?["details"]?.arrayValue
        else {
            return false
        }
        return details.contains { detail in
            detail["reason"]?.stringValue == "API_KEY_INVALID"
                && detail["domain"]?.stringValue == "googleapis.com"
        }
    }
}
