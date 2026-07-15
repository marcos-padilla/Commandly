import Foundation
import SecurityKit

/// Provider metadata rendered by Commandly's BYOK settings flow.
nonisolated struct AIProviderOption: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let requiresCredential: Bool
    let defaultEndpoint: String?
    let allowsEndpointEditing: Bool
    let supportsToolRuntime: Bool
}

/// A credential-scoped model that can be selected by the user.
nonisolated struct AIModelOption: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let capabilities: Set<String>

    var supportsTools: Bool {
        capabilities.contains("tools")
    }
}

/// Result of validating one provider connection and discovering its available models.
nonisolated struct AIConnectionValidation: Equatable, Sendable {
    let models: [AIModelOption]
    let normalizedEndpoint: String?
}

/// User-actionable, sanitized provider connection failures.
nonisolated enum AIConnectionServiceError: Error, Equatable, Sendable {
    case invalidCredential
    case insufficientPermission
    case billingUnavailable
    case rateLimited
    case noCompatibleModels
    case invalidEndpoint
    case unsupportedRuntime
    case unavailable
}

/// Provider catalog, validation, and model-discovery boundary used by Settings.
nonisolated protocol AIConnectionServicing: Sendable {
    var providers: [AIProviderOption] { get }

    func validate(
        providerID: String,
        credential: SensitiveValue<String>?,
        endpoint: String?
    ) async throws -> AIConnectionValidation
}

/// Deterministic provider service for tests and previews. It never touches the network.
nonisolated struct InMemoryAIConnectionService: AIConnectionServicing, Sendable {
    private static let maximumEndpointBytes = 2_048

    let providers: [AIProviderOption]
    private let modelsByProvider: [String: [AIModelOption]]
    private let errorByProvider: [String: AIConnectionServiceError]

    init(
        providers: [AIProviderOption] = Self.previewProviders,
        modelsByProvider: [String: [AIModelOption]] = Self.previewModels,
        errorByProvider: [String: AIConnectionServiceError] = [:]
    ) {
        self.providers = providers
        self.modelsByProvider = modelsByProvider
        self.errorByProvider = errorByProvider
    }

    func validate(
        providerID: String,
        credential: SensitiveValue<String>?,
        endpoint: String?
    ) async throws -> AIConnectionValidation {
        try Task.checkCancellation()
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            throw AIConnectionServiceError.unavailable
        }
        if let error = errorByProvider[providerID] {
            throw error
        }
        if provider.requiresCredential {
            guard let credential,
                  credential.reveal().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    == false else {
                throw AIConnectionServiceError.invalidCredential
            }
        }
        if provider.allowsEndpointEditing,
           let endpoint,
           Self.isAllowedLoopbackEndpoint(endpoint) == false {
            throw AIConnectionServiceError.invalidEndpoint
        }
        let models = modelsByProvider[providerID] ?? []
        guard models.isEmpty == false else {
            throw AIConnectionServiceError.noCompatibleModels
        }
        return AIConnectionValidation(models: models, normalizedEndpoint: endpoint)
    }

    private static func isAllowedLoopbackEndpoint(_ value: String) -> Bool {
        guard value.utf8.count <= maximumEndpointBytes,
              let components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              components.scheme == "http" || components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }
        let normalizedHost = host.trimmingCharacters(
            in: CharacterSet(charactersIn: "[]")
        )
        let path = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return (normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1")
            && (path.isEmpty || path == "api")
    }

    static let previewProviders: [AIProviderOption] = [
        AIProviderOption(
            id: "openai",
            title: "OpenAI",
            subtitle: "GPT and reasoning models",
            systemImage: "brain.head.profile",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "anthropic",
            title: "Anthropic",
            subtitle: "Claude models",
            systemImage: "a.circle.fill",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "google-gemini",
            title: "Google Gemini",
            subtitle: "Gemini models with native tool calling",
            systemImage: "sparkles",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "mistral",
            title: "Mistral AI",
            subtitle: "Mistral chat and tool-capable models",
            systemImage: "m.circle.fill",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "groq",
            title: "Groq",
            subtitle: "Fast hosted models with local tool calling",
            systemImage: "bolt.fill",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "xai",
            title: "xAI",
            subtitle: "Grok language models",
            systemImage: "x.circle.fill",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "openrouter",
            title: "OpenRouter",
            subtitle: "A broad routed model catalog",
            systemImage: "arrow.triangle.branch",
            requiresCredential: true,
            defaultEndpoint: nil,
            allowsEndpointEditing: false,
            supportsToolRuntime: true
        ),
        AIProviderOption(
            id: "ollama",
            title: "Ollama",
            subtitle: "Models running locally on this Mac",
            systemImage: "desktopcomputer",
            requiresCredential: false,
            defaultEndpoint: "http://localhost:11434",
            allowsEndpointEditing: true,
            supportsToolRuntime: true
        ),
    ]

    static let previewModels: [String: [AIModelOption]] = [
        "openai": [AIModelOption(id: "openai-model", displayName: "OpenAI Model", capabilities: ["text", "tools"])],
        "anthropic": [AIModelOption(id: "claude-model", displayName: "Claude Model", capabilities: ["text", "tools"])],
        "google-gemini": [AIModelOption(id: "gemini-model", displayName: "Gemini Model", capabilities: ["text", "tools"])],
        "mistral": [AIModelOption(id: "mistral-model", displayName: "Mistral Model", capabilities: ["text", "tools"])],
        "groq": [AIModelOption(id: "groq-model", displayName: "Groq Model", capabilities: ["text", "tools"])],
        "xai": [AIModelOption(id: "grok-model", displayName: "Grok Model", capabilities: ["text", "tools"])],
        "openrouter": [AIModelOption(id: "routed-model", displayName: "Routed Model", capabilities: ["text", "tools"])],
        "ollama": [AIModelOption(id: "local-model", displayName: "Local Model", capabilities: ["text", "tools"])],
    ]
}
