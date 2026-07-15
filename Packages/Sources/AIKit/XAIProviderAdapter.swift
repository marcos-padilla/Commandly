import Foundation

/// Adapter for xAI's language-model discovery and stateless Chat Completions compatibility API.
///
/// xAI recommends its Responses API for new native capabilities. This adapter intentionally uses
/// only client-executed function tools and does not expose xAI-hosted tools or persisted state.
public struct XAIProviderAdapter: AIProviderAdapter {
    public let descriptor = AIProviderDescriptor(
        id: .xAI,
        displayName: "xAI",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://api.x.ai/v1") ?? URL(fileURLWithPath: "/")
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
                url: AIProviderSupport.endpoint(baseURL: baseURL, path: "language-models"),
                headers: headers(credential: credential)
            )
        )
        try AIProviderSupport.checkCancellation()
        let root = try AIProviderSupport.decode(response)
        guard let data = root["models"]?.arrayValue else {
            throw AIProviderError.invalidProviderResponse
        }

        let models = data.compactMap { value -> AIModelDescriptor? in
            guard
                let id = value["id"]?.stringValue,
                !id.isEmpty,
                id.lowercased().contains("multi-agent") == false,
                value["input_modalities"]?.arrayValue?.compactMap(\.stringValue)
                    .contains("text") == true,
                value["output_modalities"]?.arrayValue?.compactMap(\.stringValue)
                    .contains("text") == true
            else {
                return nil
            }
            return AIModelDescriptor(
                providerID: .xAI,
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
