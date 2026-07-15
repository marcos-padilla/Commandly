import Foundation
import SecurityKit
import Testing
@testable import Commandly

struct AIConnectionStoreTests {
    @Test func preferencesRoundTripWithoutCredentialMaterial() async throws {
        let suiteName = "CommandlyTests.AIConnections.\(UUID().uuidString)"
        let cleanupDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { cleanupDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAIConnectionStore(
            defaults: try #require(UserDefaults(suiteName: suiteName))
        )
        let connection = StoredAIConnection(
            providerID: "openai",
            modelID: "model-a",
            modelDisplayName: "Model A",
            capabilities: ["tools"]
        )
        var preferences = AIConnectionPreferences.empty
        preferences.upsert(connection, makeActive: true)

        try await store.save(preferences)

        #expect(try await store.load() == preferences)
        let inspectionDefaults = try #require(UserDefaults(suiteName: suiteName))
        let encoded = try #require(inspectionDefaults.data(forKey: "ai.connections.v1"))
        let payload = try #require(String(data: encoded, encoding: .utf8))
        #expect(payload.contains("model-a"))
        #expect(payload.contains("api-key") == false)
    }

    @Test func removingActiveConnectionSelectsAStableFallback() {
        var preferences = AIConnectionPreferences.empty
        preferences.upsert(
            StoredAIConnection(
                providerID: "openai",
                modelID: "one",
                modelDisplayName: "One"
            ),
            makeActive: true
        )
        preferences.upsert(
            StoredAIConnection(
                providerID: "anthropic",
                modelID: "two",
                modelDisplayName: "Two"
            ),
            makeActive: false
        )

        preferences.remove(providerID: "openai")

        #expect(preferences.connections.map(\.providerID) == ["anthropic"])
        #expect(preferences.activeProviderID == "anthropic")
    }

    @Test func credentialStoreKeepsSecretsOutOfDescriptionsAndPreferences() async throws {
        let secureStore = InMemorySecureStore()
        let credentials = SecureAIProviderCredentialStore(secureStore: secureStore)

        try await credentials.storeCredential(
            "secret-value",
            for: "anthropic",
            connectionRevision: "revision-a"
        )

        #expect(try await credentials.credential(for: "anthropic") == "secret-value")
        #expect(try await credentials.credential(
            for: "anthropic",
            matching: "revision-a"
        ) == "secret-value")
        #expect(try await credentials.credential(
            for: "anthropic",
            matching: "revision-b"
        ) == nil)
        let record = try #require(await credentials.credentialRecord(for: "anthropic"))
        #expect(record.description.contains("secret-value") == false)
        #expect(record.debugDescription.contains("secret-value") == false)
        #expect(String(reflecting: record).contains("secret-value") == false)
        #expect(Mirror(reflecting: record).children.allSatisfy { child in
            String(describing: child.value).contains("secret-value") == false
        })
        try await credentials.deleteCredential(for: "anthropic")
        #expect(try await credentials.credential(for: "anthropic") == nil)
    }

    @Test func legacyConnectionPayloadGetsStableBackwardCompatibleRevision() throws {
        let payload = Data(#"""
        {
            "providerID":"openai",
            "modelID":"model-a",
            "modelDisplayName":"Model A",
            "endpoint":null,
            "capabilities":["tools"]
        }
        """#.utf8)

        let first = try JSONDecoder().decode(StoredAIConnection.self, from: payload)
        let second = try JSONDecoder().decode(StoredAIConnection.self, from: payload)

        #expect(first.connectionRevision == StoredAIConnection.legacyConnectionRevision)
        #expect(second.connectionRevision == first.connectionRevision)
    }

    @Test func credentialStoreRejectsUnsafeProviderIdentifiers() async {
        let credentials = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )

        await #expect(throws: AIConnectionStoreError.invalidProviderID) {
            try await credentials.storeCredential("secret", for: "../provider")
        }
    }

    @Test func corruptPreferencesAreReportedInsteadOfSilentlyReset() async throws {
        let suiteName = "CommandlyTests.AIConnections.Corrupt.\(UUID().uuidString)"
        let setupDefaults = try #require(UserDefaults(suiteName: suiteName))
        setupDefaults.set(Data("not-json".utf8), forKey: "ai.connections.v1")
        defer { setupDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAIConnectionStore(
            defaults: try #require(UserDefaults(suiteName: suiteName))
        )

        await #expect(throws: AIConnectionStoreError.corruptPreferences) {
            _ = try await store.load()
        }
    }
}
