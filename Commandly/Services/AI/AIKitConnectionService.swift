import AIKit
import Foundation
import SecurityKit

/// Production bridge from Commandly settings to AIKit's explicit provider adapters.
nonisolated struct AIKitConnectionService: AIConnectionServicing, Sendable {
    private static let maximumSelectableModels = 256
    private static let maximumModelTextBytes = 1_024

    private let resolver: AIKitProviderResolver

    init(
        registry: AIProviderRegistry,
        transport: any AIHTTPTransport
    ) {
        self.resolver = AIKitProviderResolver(registry: registry, transport: transport)
    }

    static func standard(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) throws -> AIKitConnectionService {
        AIKitConnectionService(
            registry: try AIProviderRegistry.standard(transport: transport),
            transport: transport
        )
    }

    var providers: [AIProviderOption] {
        let preferredOrder: [AIProviderID] = [
            .openAI, .anthropic, .googleGemini, .mistral, .groq, .xAI,
            .openRouter, .ollama,
        ]
        return resolver.registry.providers.sorted { left, right in
            let leftIndex = preferredOrder.firstIndex(of: left.id) ?? preferredOrder.count
            let rightIndex = preferredOrder.firstIndex(of: right.id) ?? preferredOrder.count
            return leftIndex == rightIndex
                ? left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
                : leftIndex < rightIndex
        }.map(Self.option)
    }

    func validate(
        providerID: String,
        credential: SensitiveValue<String>?,
        endpoint: String?
    ) async throws -> AIConnectionValidation {
        try Task.checkCancellation()
        let id = AIProviderID(rawValue: providerID)
        let adapter: any AIProviderAdapter
        do {
            adapter = try resolver.adapter(for: id, endpoint: endpoint)
        } catch {
            throw AIConnectionServiceError.invalidEndpoint
        }
        let configuration = AIProviderConfiguration(
            providerID: id,
            credential: credential.map { AICredential($0.reveal()) }
        )
        let outcome = await adapter.validate(configuration: configuration)
        try Task.checkCancellation()

        switch outcome {
        case .valid(let models):
            let compatible = Self.sanitizedModelOptions(models)
            guard compatible.isEmpty == false else {
                throw AIConnectionServiceError.noCompatibleModels
            }
            return AIConnectionValidation(
                models: compatible,
                normalizedEndpoint: id == .ollama
                    ? try resolver.normalizedLoopbackEndpoint(endpoint)
                    : nil
            )
        case .credentialMissing, .invalidCredential:
            throw AIConnectionServiceError.invalidCredential
        case .insufficientPermission:
            throw AIConnectionServiceError.insufficientPermission
        case .billingUnavailable:
            throw AIConnectionServiceError.billingUnavailable
        case .rateLimited:
            throw AIConnectionServiceError.rateLimited
        case .unavailable:
            throw AIConnectionServiceError.unavailable
        case .misconfigured:
            throw id == .ollama
                ? AIConnectionServiceError.invalidEndpoint
                : AIConnectionServiceError.unavailable
        }
    }

    private static func option(_ descriptor: AIProviderDescriptor) -> AIProviderOption {
        AIProviderOption(
            id: descriptor.id.rawValue,
            title: descriptor.displayName,
            subtitle: subtitle(for: descriptor.id),
            systemImage: systemImage(for: descriptor.id),
            requiresCredential: descriptor.authentication == .apiKey,
            defaultEndpoint: descriptor.id == .ollama ? "http://localhost:11434" : nil,
            allowsEndpointEditing: descriptor.id == .ollama,
            supportsToolRuntime: descriptor.capabilities.contains(.textGeneration)
                && descriptor.capabilities.contains(.toolCalling)
        )
    }

    private static func modelOption(_ descriptor: AIModelDescriptor) -> AIModelOption {
        AIModelOption(
            id: descriptor.id,
            displayName: descriptor.displayName,
            capabilities: Set(descriptor.capabilities.map(capabilityName))
        )
    }

    private static func sanitizedModelOptions(
        _ descriptors: [AIModelDescriptor]
    ) -> [AIModelOption] {
        var seenModelIDs: Set<String> = []
        var models: [AIModelOption] = []
        models.reserveCapacity(min(descriptors.count, maximumSelectableModels))

        for descriptor in descriptors {
            guard descriptor.capabilities.contains(.textOutput),
                  isValidModelText(descriptor.id),
                  isValidModelText(descriptor.displayName),
                  seenModelIDs.insert(descriptor.id).inserted else {
                continue
            }
            models.append(modelOption(descriptor))
            if models.count == maximumSelectableModels { break }
        }
        return models
    }

    private static func isValidModelText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false
            && trimmed == value
            && value.utf8.count <= maximumModelTextBytes
    }

    private static func capabilityName(_ capability: AIModelCapability) -> String {
        switch capability {
        case .textInput: "text-input"
        case .textOutput: "text-output"
        case .toolCalling: "tools"
        case .structuredOutput: "structured-output"
        case .imageInput: "image-input"
        case .reasoning: "reasoning"
        }
    }

    private static func subtitle(for providerID: AIProviderID) -> String {
        switch providerID {
        case .openAI: "GPT and reasoning models"
        case .anthropic: "Claude models"
        case .googleGemini: "Gemini models with native tool calling"
        case .mistral: "Mistral chat and tool-capable models"
        case .groq: "Fast hosted models with local tool calling"
        case .xAI: "Grok language models"
        case .openRouter: "A broad routed model catalog"
        case .ollama: "Models running locally on this Mac"
        default: "Provider-managed models"
        }
    }

    private static func systemImage(for providerID: AIProviderID) -> String {
        switch providerID {
        case .openAI: "brain.head.profile"
        case .anthropic: "a.circle.fill"
        case .googleGemini: "sparkles"
        case .mistral: "m.circle.fill"
        case .groq: "bolt.fill"
        case .xAI: "x.circle.fill"
        case .openRouter: "arrow.triangle.branch"
        case .ollama: "desktopcomputer"
        default: "cpu"
        }
    }
}

/// Non-secret summary of the active provider/model used by an AI extension.
nonisolated struct AIActiveProviderSelection: Equatable, Sendable {
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let supportsTools: Bool
    let connectionRevision: String
}

nonisolated enum AIProviderRuntimeError: Error, Equatable, Sendable {
    case noActiveConnection
    case credentialUnavailable
    case providerUnavailable
    case modelMismatch
    case connectionMismatch
    case toolsUnsupported
}

/// Active-provider runtime boundary used by built-in AI extensions.
nonisolated protocol AIProviderRuntimeServicing: Sendable {
    func activeSelection() async throws -> AIActiveProviderSelection?
    func complete(
        _ request: AICompletionRequest,
        providerID: String,
        connectionRevision: String
    ) async throws -> AICompletionResponse
}

nonisolated struct AIProviderRuntimeService: AIProviderRuntimeServicing, Sendable {
    private let connectionStore: any AIConnectionStoring
    private let credentialStore: any AIProviderCredentialStoring
    private let resolver: AIKitProviderResolver

    init(
        connectionStore: any AIConnectionStoring,
        credentialStore: any AIProviderCredentialStoring,
        registry: AIProviderRegistry,
        transport: any AIHTTPTransport
    ) {
        self.connectionStore = connectionStore
        self.credentialStore = credentialStore
        self.resolver = AIKitProviderResolver(registry: registry, transport: transport)
    }

    func activeSelection() async throws -> AIActiveProviderSelection? {
        let preferences = try await connectionStore.load()
        guard let connection = preferences.activeConnection else { return nil }
        let providerID = AIProviderID(rawValue: connection.providerID)
        let descriptor: AIProviderDescriptor
        do {
            descriptor = try resolver.adapter(
                for: providerID,
                endpoint: connection.endpoint
            ).descriptor
        } catch {
            throw AIProviderRuntimeError.providerUnavailable
        }
        return AIActiveProviderSelection(
            providerID: connection.providerID,
            providerName: descriptor.displayName,
            modelID: connection.modelID,
            modelName: connection.modelDisplayName,
            supportsTools: connection.capabilities.contains("tools")
                && descriptor.capabilities.contains(.toolCalling)
                && descriptor.capabilities.contains(.textGeneration),
            connectionRevision: connection.connectionRevision
        )
    }

    func complete(
        _ request: AICompletionRequest,
        providerID: String,
        connectionRevision: String
    ) async throws -> AICompletionResponse {
        try Task.checkCancellation()
        let preferences = try await connectionStore.load()
        guard let connection = preferences.activeConnection else {
            throw AIProviderRuntimeError.noActiveConnection
        }
        guard connection.providerID == providerID,
              connection.connectionRevision == connectionRevision else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        guard connection.modelID == request.modelID else {
            throw AIProviderRuntimeError.modelMismatch
        }
        let providerID = AIProviderID(rawValue: connection.providerID)
        let adapter: any AIProviderAdapter
        do {
            adapter = try resolver.adapter(for: providerID, endpoint: connection.endpoint)
        } catch {
            throw AIProviderRuntimeError.providerUnavailable
        }
        guard adapter.descriptor.capabilities.contains(.textGeneration) else {
            throw AIProviderRuntimeError.providerUnavailable
        }
        if request.tools.isEmpty == false {
            guard connection.capabilities.contains("tools"),
                  adapter.descriptor.capabilities.contains(.toolCalling) else {
                throw AIProviderRuntimeError.toolsUnsupported
            }
        }

        let credential: AICredential?
        switch adapter.descriptor.authentication {
        case .apiKey:
            guard let record = try await credentialStore.credentialRecord(
                for: connection.providerID
            ) else {
                throw AIProviderRuntimeError.credentialUnavailable
            }
            guard record.connectionRevision == connection.connectionRevision else {
                throw AIProviderRuntimeError.connectionMismatch
            }
            credential = AICredential(record.reveal())
        case .optionalAPIKey:
            if let record = try await credentialStore.credentialRecord(
                for: connection.providerID
            ) {
                guard record.connectionRevision == connection.connectionRevision else {
                    throw AIProviderRuntimeError.connectionMismatch
                }
                credential = AICredential(record.reveal())
            } else {
                credential = nil
            }
        case .none:
            credential = nil
        }

        let response = try await adapter.complete(
            request: request,
            configuration: AIProviderConfiguration(
                providerID: providerID,
                credential: credential
            )
        )
        try Task.checkCancellation()

        let currentPreferences = try await connectionStore.load()
        guard currentPreferences.activeConnection == connection else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        switch adapter.descriptor.authentication {
        case .apiKey:
            guard let currentCredential = try await credentialStore.credentialRecord(
                for: connection.providerID
            ), currentCredential.connectionRevision == connection.connectionRevision else {
                throw AIProviderRuntimeError.connectionMismatch
            }
        case .optionalAPIKey:
            let currentCredential = try await credentialStore.credentialRecord(
                for: connection.providerID
            )
            if credential == nil {
                guard currentCredential == nil else {
                    throw AIProviderRuntimeError.connectionMismatch
                }
            } else {
                guard currentCredential?.connectionRevision == connection.connectionRevision else {
                    throw AIProviderRuntimeError.connectionMismatch
                }
            }
        case .none:
            break
        }
        return response
    }
}

/// Resolves fixed-host cloud adapters and a separately validated loopback Ollama adapter.
private nonisolated struct AIKitProviderResolver: Sendable {
    private static let maximumEndpointBytes = 2_048

    let registry: AIProviderRegistry
    let transport: any AIHTTPTransport

    func adapter(
        for providerID: AIProviderID,
        endpoint: String?
    ) throws -> any AIProviderAdapter {
        if providerID == .ollama {
            let normalized = try normalizedLoopbackEndpoint(endpoint)
            guard let url = URL(string: normalized) else {
                throw AIConnectionServiceError.invalidEndpoint
            }
            return try OllamaProviderAdapter(transport: transport, baseURL: url)
        }
        return try registry.adapter(for: providerID)
    }

    func normalizedLoopbackEndpoint(_ endpoint: String?) throws -> String {
        let value = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "http://localhost:11434"
        guard value.utf8.count <= Self.maximumEndpointBytes,
              var components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              components.scheme == "http" || components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw AIConnectionServiceError.invalidEndpoint
        }
        let normalizedHost = host.trimmingCharacters(
            in: CharacterSet(charactersIn: "[]")
        )
        guard normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1" else {
            throw AIConnectionServiceError.invalidEndpoint
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty || path == "api" else {
            throw AIConnectionServiceError.invalidEndpoint
        }
        components.path = path.isEmpty ? "" : "/api"
        guard let normalized = components.url?.absoluteString else {
            throw AIConnectionServiceError.invalidEndpoint
        }
        return normalized
    }
}
