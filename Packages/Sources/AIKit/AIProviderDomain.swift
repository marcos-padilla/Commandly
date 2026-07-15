import Foundation

/// Stable identifier for an AI provider adapter.
public struct AIProviderID: RawRepresentable, Hashable, Sendable, Codable, Comparable {
    public let rawValue: String

    /// Creates a provider identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: AIProviderID, rhs: AIProviderID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let openAI = AIProviderID(rawValue: "openai")
    public static let anthropic = AIProviderID(rawValue: "anthropic")
    public static let googleGemini = AIProviderID(rawValue: "google-gemini")
    public static let openRouter = AIProviderID(rawValue: "openrouter")
    public static let ollama = AIProviderID(rawValue: "ollama")
    public static let mistral = AIProviderID(rawValue: "mistral")
    public static let groq = AIProviderID(rawValue: "groq")
    public static let xAI = AIProviderID(rawValue: "xai")
}

/// Authentication expected by a provider.
public enum AIAuthenticationRequirement: String, Sendable, Codable, Equatable {
    case apiKey
    case none
    case optionalAPIKey
}

/// Provider-level capabilities implemented by an adapter.
public enum AIProviderCapability: String, Sendable, Codable, Hashable, CaseIterable {
    case modelDiscovery
    case textGeneration
    case toolCalling
    case streaming
    case localExecution
}

/// Public metadata for an AI provider adapter.
public struct AIProviderDescriptor: Sendable, Codable, Equatable, Identifiable {
    public let id: AIProviderID
    public let displayName: String
    public let authentication: AIAuthenticationRequirement
    public let capabilities: Set<AIProviderCapability>

    /// Creates provider metadata.
    public init(
        id: AIProviderID,
        displayName: String,
        authentication: AIAuthenticationRequirement,
        capabilities: Set<AIProviderCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.authentication = authentication
        self.capabilities = capabilities
    }
}

/// API credential that redacts itself from string and debug output.
///
/// Credentials deliberately do not conform to `Codable` or `Equatable`. Persist them through the
/// application's secure-storage boundary, never preferences or ordinary serialized state.
public struct AICredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let value: String

    /// Wraps an API credential.
    public init(_ value: String) {
        self.value = value
    }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror {
        Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
    }

    var rawValue: String { value }
    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Key for a non-secret provider-specific configuration value.
public struct AIProviderConfigurationKey: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    /// Creates a configuration key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let organizationID = AIProviderConfigurationKey(rawValue: "organization-id")
    public static let projectID = AIProviderConfigurationKey(rawValue: "project-id")
    public static let applicationURL = AIProviderConfigurationKey(rawValue: "application-url")
    public static let applicationName = AIProviderConfigurationKey(rawValue: "application-name")
}

/// Runtime configuration for one provider.
public struct AIProviderConfiguration: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let providerID: AIProviderID
    public let credential: AICredential?
    public let values: [AIProviderConfigurationKey: String]

    /// Creates a provider configuration.
    ///
    /// `values` must contain non-secret metadata only. Put API keys exclusively in `credential`.
    public init(
        providerID: AIProviderID,
        credential: AICredential? = nil,
        values: [AIProviderConfigurationKey: String] = [:]
    ) {
        self.providerID = providerID
        self.credential = credential
        self.values = values
    }

    /// Returns a non-secret provider-specific value.
    public subscript(key: AIProviderConfigurationKey) -> String? {
        values[key]
    }

    public var description: String {
        "AIProviderConfiguration(providerID: \(providerID.rawValue), credential: <redacted>, values: <redacted>)"
    }

    public var debugDescription: String { description }
}

/// Model capabilities relevant to Commandly's AI runtime.
public enum AIModelCapability: String, Sendable, Codable, Hashable, CaseIterable {
    case textInput
    case textOutput
    case toolCalling
    case structuredOutput
    case imageInput
    case reasoning
}

/// Where the adapter obtained capability information.
public enum AIModelCapabilityEvidence: String, Sendable, Codable, Equatable {
    case providerReported
    case curated
    case compatibilityLayer
}

/// A model available to a configured provider credential.
public struct AIModelDescriptor: Sendable, Codable, Equatable, Identifiable {
    public let providerID: AIProviderID
    public let id: String
    public let displayName: String
    public let contextWindow: Int?
    public let maximumOutputTokens: Int?
    public let capabilities: Set<AIModelCapability>
    public let capabilityEvidence: AIModelCapabilityEvidence

    /// Creates model metadata.
    public init(
        providerID: AIProviderID,
        id: String,
        displayName: String,
        contextWindow: Int? = nil,
        maximumOutputTokens: Int? = nil,
        capabilities: Set<AIModelCapability>,
        capabilityEvidence: AIModelCapabilityEvidence
    ) {
        self.providerID = providerID
        self.id = id
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.maximumOutputTokens = maximumOutputTokens
        self.capabilities = capabilities
        self.capabilityEvidence = capabilityEvidence
    }
}
