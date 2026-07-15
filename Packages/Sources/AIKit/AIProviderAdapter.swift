import Foundation

/// Vendor adapter boundary for model discovery and non-streaming tool completions.
public protocol AIProviderAdapter: Sendable {
    var descriptor: AIProviderDescriptor { get }

    /// Validates configuration through a free model/key endpoint and returns selectable models.
    func validate(configuration: AIProviderConfiguration) async -> AIProviderValidationOutcome

    /// Lists compatible models visible to the configured key.
    func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor]

    /// Performs one normalized, non-streaming completion.
    func complete(
        request: AICompletionRequest,
        configuration: AIProviderConfiguration
    ) async throws -> AICompletionResponse
}

public extension AIProviderAdapter {
    func validate(configuration: AIProviderConfiguration) async -> AIProviderValidationOutcome {
        do {
            return .valid(models: try await models(configuration: configuration))
        } catch let error as AIProviderError {
            return AIProviderSupport.validationOutcome(for: error)
        } catch {
            return .unavailable
        }
    }
}

/// Immutable registry of installed provider adapters.
public struct AIProviderRegistry: Sendable {
    private let adapters: [AIProviderID: any AIProviderAdapter]

    public init(adapters: [any AIProviderAdapter]) throws {
        var indexed: [AIProviderID: any AIProviderAdapter] = [:]
        for adapter in adapters {
            guard indexed[adapter.descriptor.id] == nil else {
                throw AIProviderRegistryError.duplicateProvider(adapter.descriptor.id)
            }
            indexed[adapter.descriptor.id] = adapter
        }
        self.adapters = indexed
    }

    /// Returns the adapter for an identifier.
    public func adapter(for providerID: AIProviderID) throws -> any AIProviderAdapter {
        guard let adapter = adapters[providerID] else {
            throw AIProviderRegistryError.providerNotRegistered(providerID)
        }
        return adapter
    }

    /// Metadata for all registered providers, ordered for stable presentation.
    public var providers: [AIProviderDescriptor] {
        adapters.values.map(\.descriptor).sorted { $0.displayName < $1.displayName }
    }

    /// Registry containing Commandly's built-in adapters.
    public static func standard(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) throws -> AIProviderRegistry {
        try AIProviderRegistry(adapters: [
            OpenAIProviderAdapter(transport: transport),
            AnthropicProviderAdapter(transport: transport),
            MistralProviderAdapter(transport: transport),
            GroqProviderAdapter(transport: transport),
            XAIProviderAdapter(transport: transport),
            OpenRouterProviderAdapter(transport: transport),
            GeminiProviderAdapter(transport: transport),
            OllamaProviderAdapter(transport: transport)
        ])
    }
}

public enum AIProviderRegistryError: Error, Sendable, Equatable {
    case duplicateProvider(AIProviderID)
    case providerNotRegistered(AIProviderID)
}

/// Provider-independent entry point used by settings to validate keys and discover models.
public struct AIModelCatalog: Sendable {
    private let registry: AIProviderRegistry

    public init(registry: AIProviderRegistry) {
        self.registry = registry
    }

    public func validate(
        configuration: AIProviderConfiguration
    ) async -> AIProviderValidationOutcome {
        do {
            let adapter = try registry.adapter(for: configuration.providerID)
            return await adapter.validate(configuration: configuration)
        } catch {
            return .misconfigured
        }
    }

    public func models(configuration: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let adapter = try registry.adapter(for: configuration.providerID)
        return try await adapter.models(configuration: configuration)
    }
}

enum AIProviderSupport {
    static let maximumCredentialBytes = 8_192

    static func checkCancellation() throws {
        guard !Task.isCancelled else { throw AIProviderError.cancelled }
    }

    static func validationOutcome(for error: AIProviderError) -> AIProviderValidationOutcome {
        switch error {
        case .credentialMissing:
            .credentialMissing
        case .invalidCredential:
            .invalidCredential
        case .insufficientPermission:
            .insufficientPermission
        case .billingUnavailable:
            .billingUnavailable
        case let .rateLimited(retryAfterSeconds):
            .rateLimited(retryAfterSeconds: retryAfterSeconds)
        case .configurationMismatch, .invalidRequest:
            .misconfigured
        case .modelUnavailable, .serviceUnavailable, .networkUnavailable,
             .invalidProviderResponse, .cancelled, .unsupportedCapability:
            .unavailable
        }
    }

    static func validate(
        configuration: AIProviderConfiguration,
        for descriptor: AIProviderDescriptor
    ) throws -> AICredential? {
        guard configuration.providerID == descriptor.id else {
            throw AIProviderError.configurationMismatch
        }
        switch descriptor.authentication {
        case .apiKey:
            guard let credential = configuration.credential, !credential.isEmpty else {
                throw AIProviderError.credentialMissing
            }
            guard credential.rawValue.utf8.count <= maximumCredentialBytes,
                  credential.rawValue.unicodeScalars.contains(
                      where: CharacterSet.controlCharacters.contains
                  ) == false else {
                throw AIProviderError.invalidCredential
            }
            return credential
        case .none:
            return nil
        case .optionalAPIKey:
            if let credential = configuration.credential, credential.isEmpty {
                throw AIProviderError.credentialMissing
            }
            if let credential = configuration.credential,
               credential.rawValue.utf8.count > maximumCredentialBytes
                || credential.rawValue.unicodeScalars.contains(
                    where: CharacterSet.controlCharacters.contains
                ) {
                throw AIProviderError.invalidCredential
            }
            return configuration.credential
        }
    }

    static func validatedHeaderValue(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard
            !value.isEmpty,
            value.count <= 1_024,
            !value.contains("\n"),
            !value.contains("\r")
        else {
            throw AIProviderError.invalidRequest
        }
        return value
    }

    static func endpoint(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    static func encode(_ value: AIJSONValue) throws -> Data {
        do {
            return try value.encodedData()
        } catch {
            throw AIProviderError.invalidRequest
        }
    }

    static func decode(_ response: AIHTTPResponse) throws -> AIJSONValue {
        if let error = AIHTTPStatusMapper.error(for: response) {
            throw error
        }
        do {
            return try AIJSONValue(data: response.body)
        } catch {
            throw AIProviderError.invalidProviderResponse
        }
    }

    static func compactJSONString(_ value: AIJSONValue) throws -> String {
        guard let string = String(data: try encode(value), encoding: .utf8) else {
            throw AIProviderError.invalidRequest
        }
        return string
    }

    static func toolOutputString(_ value: AIJSONValue) throws -> String {
        if let string = value.stringValue { return string }
        return try compactJSONString(value)
    }

    static func sortedModels(_ models: [AIModelDescriptor]) -> [AIModelDescriptor] {
        models.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
