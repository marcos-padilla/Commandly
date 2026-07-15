import Foundation

/// Adapter for Mistral's credential-scoped Models and Chat Completions APIs.
public struct MistralProviderAdapter: AIProviderAdapter {
    public let descriptor = AIProviderDescriptor(
        id: .mistral,
        displayName: "Mistral AI",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://api.mistral.ai/v1") ?? URL(fileURLWithPath: "/")
    }

    init(transport: any AIHTTPTransport, baseURL: URL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let credential = try requiredCredential(configuration)
        try AIProviderSupport.checkCancellation()
        let response = try await transport.send(
            AIHTTPRequest(
                method: .get,
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "models"),
                headers: headers(credential: credential)
            )
        )
        try AIProviderSupport.checkCancellation()
        let root = try AIProviderSupport.decode(response)
        guard let data = root["data"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        let models = data.compactMap { value -> AIModelDescriptor? in
            guard
                let id = value["id"]?.stringValue,
                !id.isEmpty,
                value["archived"]?.booleanValue != true,
                value["capabilities"]?["completion_chat"]?.booleanValue == true,
                value["capabilities"]?["function_calling"]?.booleanValue == true
            else {
                return nil
            }
            return AIModelDescriptor(
                providerID: .mistral,
                id: id,
                displayName: id,
                contextWindow: value["max_context_length"]?.integerValue,
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
        return try await OpenAIChatCompatibleAdapterCore(
            transport: transport,
            baseURL: baseURL,
            maximumOutputTokensKey: "max_tokens"
        ).complete(
            request: request,
            providerID: descriptor.id,
            headers: headers(credential: credential)
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

    private func headers(credential: AICredential) -> [String: String] {
        [
            "Authorization": "Bearer \(credential.rawValue)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }
}
