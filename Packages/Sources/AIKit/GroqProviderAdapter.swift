import Foundation

/// Adapter for Groq's Models and OpenAI-compatible Chat Completions APIs.
public struct GroqProviderAdapter: AIProviderAdapter {
    public let descriptor = AIProviderDescriptor(
        id: .groq,
        displayName: "Groq",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    private let transport: any AIHTTPTransport
    private let baseURL: URL

    public init(transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) {
        self.transport = transport
        self.baseURL = URL(string: "https://api.groq.com/openai/v1") ?? URL(fileURLWithPath: "/")
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
                value["active"]?.booleanValue != false,
                Self.isReviewedToolModel(id)
            else {
                return nil
            }
            return AIModelDescriptor(
                providerID: .groq,
                id: id,
                displayName: id,
                contextWindow: value["context_window"]?.integerValue,
                maximumOutputTokens: value["max_completion_tokens"]?.integerValue,
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
            maximumOutputTokensKey: "max_completion_tokens"
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

    private static func isReviewedToolModel(_ id: String) -> Bool {
        let lowered = id.lowercased()
        let reviewedModelIDs: Set<String> = [
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "openai/gpt-oss-20b",
            "openai/gpt-oss-120b",
            "qwen/qwen3-32b",
            "qwen/qwen3.6-27b",
        ]
        return reviewedModelIDs.contains(lowered)
    }
}
