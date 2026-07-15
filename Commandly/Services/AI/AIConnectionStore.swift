import Foundation
import SecurityKit

/// Non-secret, persisted selection for one AI provider.
///
/// API credentials are deliberately absent. They are stored separately through
/// `AIProviderCredentialStoring`.
nonisolated struct StoredAIConnection: Codable, Equatable, Identifiable, Sendable {
    static let legacyConnectionRevision = "legacy-v1"

    var id: String { providerID }

    let providerID: String
    let modelID: String
    let modelDisplayName: String
    let endpoint: String?
    let capabilities: Set<String>
    /// Opaque, non-secret identity that changes whenever this connection is saved.
    let connectionRevision: String

    init(
        providerID: String,
        modelID: String,
        modelDisplayName: String,
        endpoint: String? = nil,
        capabilities: Set<String> = [],
        connectionRevision: String = UUID().uuidString
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.endpoint = endpoint
        self.capabilities = capabilities
        self.connectionRevision = connectionRevision
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case modelID
        case modelDisplayName
        case endpoint
        case capabilities
        case connectionRevision
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        modelID = try container.decode(String.self, forKey: .modelID)
        modelDisplayName = try container.decode(String.self, forKey: .modelDisplayName)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        capabilities = try container.decodeIfPresent(Set<String>.self, forKey: .capabilities) ?? []
        if let decodedRevision = try container.decodeIfPresent(
            String.self,
            forKey: .connectionRevision
        ), decodedRevision.isEmpty == false {
            connectionRevision = decodedRevision
        } else {
            connectionRevision = Self.legacyConnectionRevision
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(modelDisplayName, forKey: .modelDisplayName)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(connectionRevision, forKey: .connectionRevision)
    }
}

/// Versioned, non-secret AI connection preferences.
nonisolated struct AIConnectionPreferences: Codable, Equatable, Sendable {
    static let empty = AIConnectionPreferences(activeProviderID: nil, connections: [])

    var activeProviderID: String?
    var connections: [StoredAIConnection]

    var activeConnection: StoredAIConnection? {
        guard let activeProviderID else { return nil }
        return connections.first { $0.providerID == activeProviderID }
    }

    func connection(for providerID: String) -> StoredAIConnection? {
        connections.first { $0.providerID == providerID }
    }

    mutating func upsert(_ connection: StoredAIConnection, makeActive: Bool) {
        connections.removeAll { $0.providerID == connection.providerID }
        connections.append(connection)
        connections.sort {
            $0.providerID.localizedCaseInsensitiveCompare($1.providerID) == .orderedAscending
        }
        if makeActive || activeProviderID == nil {
            activeProviderID = connection.providerID
        }
    }

    mutating func remove(providerID: String) {
        connections.removeAll { $0.providerID == providerID }
        if activeProviderID == providerID {
            activeProviderID = connections.first?.providerID
        }
    }
}

nonisolated enum AIConnectionStoreError: Error, Equatable, Sendable {
    case corruptPreferences
    case invalidCredentialEncoding
    case invalidProviderID
}

/// Persistence boundary for non-secret provider/model selections.
nonisolated protocol AIConnectionStoring: Sendable {
    func load() async throws -> AIConnectionPreferences
    func save(_ preferences: AIConnectionPreferences) async throws
}

/// UserDefaults-backed non-secret AI preferences.
///
/// The actor serializes read/modify/write operations. The encoded payload contains no API key,
/// prompts, conversation text, filenames, paths, or tool results.
actor UserDefaultsAIConnectionStore: AIConnectionStoring {
    private enum Key {
        static let preferences = "ai.connections.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> AIConnectionPreferences {
        guard let data = defaults.data(forKey: Key.preferences) else {
            return .empty
        }
        do {
            return try decoder.decode(AIConnectionPreferences.self, from: data)
        } catch {
            throw AIConnectionStoreError.corruptPreferences
        }
    }

    func save(_ preferences: AIConnectionPreferences) throws {
        do {
            defaults.set(try encoder.encode(preferences), forKey: Key.preferences)
        } catch {
            throw AIConnectionStoreError.corruptPreferences
        }
    }
}

/// Deterministic, actor-isolated AI preferences used by tests and previews.
actor InMemoryAIConnectionStore: AIConnectionStoring {
    private var preferences: AIConnectionPreferences

    init(preferences: AIConnectionPreferences = .empty) {
        self.preferences = preferences
    }

    func load() -> AIConnectionPreferences {
        preferences
    }

    func save(_ preferences: AIConnectionPreferences) {
        self.preferences = preferences
    }
}

/// A Keychain-only credential payload bound to one non-secret connection revision.
nonisolated struct StoredAIProviderCredential: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    let connectionRevision: String
    private let value: String

    init(value: String, connectionRevision: String) {
        self.value = value
        self.connectionRevision = connectionRevision
    }

    var description: String { "<redacted-ai-credential>" }
    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "connectionRevision": connectionRevision,
                "value": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    func reveal() -> String {
        value
    }
}

/// Secure boundary for provider credentials. Local providers may have no stored credential.
nonisolated protocol AIProviderCredentialStoring: Sendable {
    func credentialRecord(for providerID: String) async throws -> StoredAIProviderCredential?
    func storeCredential(
        _ credential: String,
        for providerID: String,
        connectionRevision: String
    ) async throws
    func deleteCredential(for providerID: String) async throws
}

extension AIProviderCredentialStoring {
    func credential(for providerID: String) async throws -> String? {
        try await credentialRecord(for: providerID)?.reveal()
    }

    func credential(
        for providerID: String,
        matching connectionRevision: String
    ) async throws -> String? {
        guard let record = try await credentialRecord(for: providerID),
              record.connectionRevision == connectionRevision else {
            return nil
        }
        return record.reveal()
    }

    func storeCredential(_ credential: String, for providerID: String) async throws {
        try await storeCredential(
            credential,
            for: providerID,
            connectionRevision: StoredAIConnection.legacyConnectionRevision
        )
    }
}

/// Stores provider credentials through SecurityKit without exposing them to preferences.
nonisolated struct SecureAIProviderCredentialStore: AIProviderCredentialStoring, Sendable {
    private struct CredentialEnvelope: Codable {
        let connectionRevision: String
        let credential: String
    }

    private let secureStore: any SecureStoring

    init(secureStore: any SecureStoring) {
        self.secureStore = secureStore
    }

    func credentialRecord(for providerID: String) async throws -> StoredAIProviderCredential? {
        guard let data = try await secureStore.read(try key(for: providerID)) else {
            return nil
        }
        if let envelope = try? JSONDecoder().decode(CredentialEnvelope.self, from: data),
           envelope.connectionRevision.isEmpty == false {
            return StoredAIProviderCredential(
                value: envelope.credential,
                connectionRevision: envelope.connectionRevision
            )
        }
        guard let legacyCredential = String(data: data, encoding: .utf8) else {
            throw AIConnectionStoreError.invalidCredentialEncoding
        }
        return StoredAIProviderCredential(
            value: legacyCredential,
            connectionRevision: StoredAIConnection.legacyConnectionRevision
        )
    }

    func storeCredential(
        _ credential: String,
        for providerID: String,
        connectionRevision: String
    ) async throws {
        let envelope = CredentialEnvelope(
            connectionRevision: connectionRevision,
            credential: credential
        )
        try await secureStore.write(
            try key(for: providerID),
            value: try JSONEncoder().encode(envelope)
        )
    }

    func deleteCredential(for providerID: String) async throws {
        try await secureStore.delete(try key(for: providerID))
    }

    private func key(for providerID: String) throws -> SecureStoreKey {
        let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false,
              normalized.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
              }) else {
            throw AIConnectionStoreError.invalidProviderID
        }
        return SecureStoreKey(rawValue: "ai.provider.\(normalized).api-key")
    }
}
