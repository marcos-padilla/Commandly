import AIKit
import Foundation
import SecurityKit
import Testing
@testable import Commandly

struct AISettingsModelTests {
    @Test @MainActor func credentialPersistsOnlyAfterValidationAndModelSelection() async throws {
        let secureStore = InMemorySecureStore()
        let credentialStore = SecureAIProviderCredentialStore(secureStore: secureStore)
        let connectionStore = InMemoryAIConnectionStore()
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )

        await model.load()
        model.selectProvider("openai")
        model.credentialInput = "test-key"
        await model.validateNow()

        #expect(model.phase == .selectingModel)
        #expect(model.discoveredModels.isEmpty == false)
        #expect(try await credentialStore.credential(for: "openai") == nil)
        #expect(await connectionStore.load() == .empty)

        await model.saveSelectionNow()

        #expect(try await credentialStore.credential(for: "openai") == "test-key")
        #expect(await connectionStore.load().activeProviderID == "openai")
        #expect(model.credentialInput.isEmpty)
    }

    @Test @MainActor func pastedCredentialIsExcludedImmediatelyAndAgainBeforeValidation() async {
        var excludedValues: [String] = []
        let model = AISettingsModel(
            connectionStore: InMemoryAIConnectionStore(),
            credentialStore: SecureAIProviderCredentialStore(
                secureStore: InMemorySecureStore()
            ),
            connectionService: InMemoryAIConnectionService(),
            excludeCredentialFromClipboardHistory: { excludedValues.append($0) }
        )
        model.selectProvider("openai")
        model.credentialInput = "  pasted-key  "
        model.credentialDraftDidChange()

        #expect(excludedValues == ["pasted-key"])

        await model.validateNow()

        #expect(excludedValues == ["pasted-key", "pasted-key"])
        #expect(model.phase == .selectingModel)
    }

    @Test @MainActor func eachSaveRotatesAndAtomicallyBindsConnectionRevision() async throws {
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        let connectionStore = InMemoryAIConnectionStore()
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )
        await model.load()
        model.selectProvider("openai")
        model.credentialInput = "test-key"
        await model.validateNow()
        await model.saveSelectionNow()
        let firstConnection = try #require(await connectionStore.load().activeConnection)
        let firstCredential = try #require(
            await credentialStore.credentialRecord(for: "openai")
        )
        #expect(firstCredential.connectionRevision == firstConnection.connectionRevision)

        model.selectProvider("openai")
        await model.validateNow()
        await model.saveSelectionNow()

        let secondConnection = try #require(await connectionStore.load().activeConnection)
        let secondCredential = try #require(
            await credentialStore.credentialRecord(for: "openai")
        )
        #expect(secondConnection.connectionRevision != firstConnection.connectionRevision)
        #expect(secondCredential.connectionRevision == secondConnection.connectionRevision)
        #expect(secondCredential.reveal() == "test-key")
    }

    @Test @MainActor func failedValidationNeverPersistsCredential() async throws {
        let secureStore = InMemorySecureStore()
        let credentialStore = SecureAIProviderCredentialStore(secureStore: secureStore)
        let service = InMemoryAIConnectionService(
            errorByProvider: ["openai": .invalidCredential]
        )
        let model = AISettingsModel(
            connectionStore: InMemoryAIConnectionStore(),
            credentialStore: credentialStore,
            connectionService: service
        )

        model.selectProvider("openai")
        model.credentialInput = "rejected-key"
        await model.validateNow()

        #expect(model.phase == .idle)
        #expect(model.errorMessage?.contains("rejected") == true)
        #expect(try await credentialStore.credential(for: "openai") == nil)
    }

    @Test @MainActor func savedCredentialCanBeRevalidatedWithoutReentry() async throws {
        let secureStore = InMemorySecureStore()
        let credentialStore = SecureAIProviderCredentialStore(secureStore: secureStore)
        try await credentialStore.storeCredential("saved-key", for: "anthropic")
        let saved = StoredAIConnection(
            providerID: "anthropic",
            modelID: "claude-model",
            modelDisplayName: "Claude Model",
            capabilities: ["text", "tools"]
        )
        let connectionStore = InMemoryAIConnectionStore(
            preferences: AIConnectionPreferences(
                activeProviderID: "anthropic",
                connections: [saved]
            )
        )
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )

        await model.load()
        model.selectProvider("anthropic")
        await model.validateNow()

        #expect(model.phase == .selectingModel)
        #expect(model.selectedModelID == "claude-model")
        #expect(model.credentialInput.isEmpty)
    }

    @Test @MainActor func disconnectDeletesCredentialAndNonSecretSelection() async throws {
        let secureStore = InMemorySecureStore()
        let credentialStore = SecureAIProviderCredentialStore(secureStore: secureStore)
        try await credentialStore.storeCredential("saved-key", for: "openai")
        let connection = StoredAIConnection(
            providerID: "openai",
            modelID: "openai-model",
            modelDisplayName: "OpenAI Model"
        )
        let connectionStore = InMemoryAIConnectionStore(
            preferences: AIConnectionPreferences(
                activeProviderID: "openai",
                connections: [connection]
            )
        )
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )

        await model.load()
        await model.disconnectNow("openai")

        #expect(try await credentialStore.credential(for: "openai") == nil)
        #expect(await connectionStore.load() == .empty)
    }

    @Test @MainActor func localProviderRejectsNonLoopbackEndpoint() async {
        let model = AISettingsModel(
            connectionStore: InMemoryAIConnectionStore(),
            credentialStore: SecureAIProviderCredentialStore(
                secureStore: InMemorySecureStore()
            ),
            connectionService: InMemoryAIConnectionService()
        )
        model.selectProvider("ollama")
        model.endpointInput = "http://example.com:11434"

        await model.validateNow()

        #expect(model.phase == .idle)
        #expect(model.errorMessage?.contains("loopback") == true)
    }

    @Test @MainActor func changingCredentialAfterValidationRequiresRevalidation() async throws {
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        let connectionStore = InMemoryAIConnectionStore()
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )
        model.selectProvider("openai")
        model.credentialInput = "validated-key"

        await model.validateNow()
        model.credentialInput = "edited-key"

        #expect(model.canSave == false)
        await model.saveSelectionNow()
        #expect(try await credentialStore.credential(for: "openai") == nil)
        #expect(await connectionStore.load() == .empty)
    }

    @Test @MainActor func changingLocalEndpointAfterValidationRequiresRevalidation() async {
        let model = AISettingsModel(
            connectionStore: InMemoryAIConnectionStore(),
            credentialStore: SecureAIProviderCredentialStore(
                secureStore: InMemorySecureStore()
            ),
            connectionService: InMemoryAIConnectionService()
        )
        model.selectProvider("ollama")

        await model.validateNow()
        model.endpointInput = "http://127.0.0.1:11434"

        #expect(model.phase == .selectingModel)
        #expect(model.canSave == false)
    }

    @Test @MainActor func failedPreferencesSaveRemovesNewCredential() async throws {
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        let connectionStore = FailingSaveAIConnectionStore(preferences: .empty)
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )
        model.selectProvider("openai")
        model.credentialInput = "new-key"
        await model.validateNow()

        await model.saveSelectionNow()

        #expect(model.phase == .selectingModel)
        #expect(model.errorMessage != nil)
        #expect(try await credentialStore.credential(for: "openai") == nil)
    }

    @Test @MainActor func failedDisconnectPreferencesSaveRestoresCredential() async throws {
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        try await credentialStore.storeCredential("existing-key", for: "openai")
        let connection = StoredAIConnection(
            providerID: "openai",
            modelID: "openai-model",
            modelDisplayName: "OpenAI Model"
        )
        let preferences = AIConnectionPreferences(
            activeProviderID: "openai",
            connections: [connection]
        )
        let connectionStore = FailingSaveAIConnectionStore(preferences: preferences)
        let model = AISettingsModel(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            connectionService: InMemoryAIConnectionService()
        )
        await model.load()

        await model.disconnectNow("openai")

        #expect(model.phase == .idle)
        #expect(model.preferences == preferences)
        #expect(model.errorMessage != nil)
        #expect(try await credentialStore.credential(for: "openai") == "existing-key")
    }

    @Test func localEndpointValidationIsStrictAndSupportsIPv6Loopback() async throws {
        let service = InMemoryAIConnectionService()

        let validation = try await service.validate(
            providerID: "ollama",
            credential: nil,
            endpoint: "http://[::1]:11434/api"
        )
        #expect(validation.models.isEmpty == false)

        for endpoint in [
            "http://user:password@localhost:11434",
            "http://localhost:11434/unreviewed-path",
            "http://localhost:11434?redirect=example.com",
            "http://localhost:11434/" + String(repeating: "a", count: 2_048),
        ] {
            await #expect(throws: AIConnectionServiceError.invalidEndpoint) {
                _ = try await service.validate(
                    providerID: "ollama",
                    credential: nil,
                    endpoint: endpoint
                )
            }
        }
    }

    @Test func productionConnectionServiceNormalizesIPv6Loopback() async throws {
        let transport = OllamaValidationTransport()
        let registry = try AIProviderRegistry(adapters: [
            OllamaProviderAdapter(transport: transport),
        ])
        let service = AIKitConnectionService(registry: registry, transport: transport)

        let validation = try await service.validate(
            providerID: AIProviderID.ollama.rawValue,
            credential: nil,
            endpoint: "http://[::1]:11434"
        )

        #expect(validation.normalizedEndpoint == "http://[::1]:11434")
        #expect(validation.models.map(\.id) == ["local-tool-model"])
        #expect(validation.models.first?.supportsTools == true)
    }

    @Test func productionConnectionServiceRejectsOversizedLoopbackEndpoint() async throws {
        let transport = OllamaValidationTransport()
        let registry = try AIProviderRegistry(adapters: [
            OllamaProviderAdapter(transport: transport),
        ])
        let service = AIKitConnectionService(registry: registry, transport: transport)
        let endpoint = "http://localhost:11434/" + String(repeating: "a", count: 2_048)

        await #expect(throws: AIConnectionServiceError.invalidEndpoint) {
            _ = try await service.validate(
                providerID: AIProviderID.ollama.rawValue,
                credential: nil,
                endpoint: endpoint
            )
        }
    }

    @Test func runtimeRejectsPreferenceCredentialAndPinnedRevisionMismatches() async throws {
        let connection = StoredAIConnection(
            providerID: "openai",
            modelID: "model-a",
            modelDisplayName: "Model A",
            capabilities: ["tools"],
            connectionRevision: "preference-revision"
        )
        let connectionStore = InMemoryAIConnectionStore(
            preferences: AIConnectionPreferences(
                activeProviderID: "openai",
                connections: [connection]
            )
        )
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        try await credentialStore.storeCredential(
            "secret-key",
            for: "openai",
            connectionRevision: "overwritten-before-preferences-commit"
        )
        let transport = RuntimeRevisionFixtureTransport()
        let runtime = AIProviderRuntimeService(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            registry: try AIProviderRegistry(adapters: [RuntimeRevisionFixtureAdapter()]),
            transport: transport
        )
        let request = AICompletionRequest(
            modelID: "model-a",
            messages: [.user("Hello")]
        )

        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await runtime.complete(
                request,
                providerID: connection.providerID,
                connectionRevision: connection.connectionRevision
            )
        }
        try await credentialStore.storeCredential(
            "secret-key",
            for: "openai",
            connectionRevision: connection.connectionRevision
        )
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await runtime.complete(
                request,
                providerID: "different-provider",
                connectionRevision: connection.connectionRevision
            )
        }
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await runtime.complete(
                request,
                providerID: connection.providerID,
                connectionRevision: "stale-conversation"
            )
        }
        let response = try await runtime.complete(
            request,
            providerID: connection.providerID,
            connectionRevision: connection.connectionRevision
        )
        #expect(response.message == .assistant("ok"))
    }

    @Test func runtimeDiscardsACompletionWhenTheConnectionRotatesInFlight() async throws {
        let originalConnection = StoredAIConnection(
            providerID: "openai",
            modelID: "model-a",
            modelDisplayName: "Model A",
            capabilities: ["tools"],
            connectionRevision: "original-revision"
        )
        let connectionStore = InMemoryAIConnectionStore(
            preferences: AIConnectionPreferences(
                activeProviderID: originalConnection.providerID,
                connections: [originalConnection]
            )
        )
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        try await credentialStore.storeCredential(
            "secret-key",
            for: originalConnection.providerID,
            connectionRevision: originalConnection.connectionRevision
        )
        let gate = SuspendedRuntimeCompletionGate()
        let runtime = AIProviderRuntimeService(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            registry: try AIProviderRegistry(adapters: [
                SuspendedRuntimeFixtureAdapter(gate: gate),
            ]),
            transport: RuntimeRevisionFixtureTransport()
        )
        let request = AICompletionRequest(
            modelID: originalConnection.modelID,
            messages: [.user("Hello")]
        )

        let completion = Task {
            try await runtime.complete(
                request,
                providerID: originalConnection.providerID,
                connectionRevision: originalConnection.connectionRevision
            )
        }
        await gate.waitUntilStarted()
        let replacement = StoredAIConnection(
            providerID: originalConnection.providerID,
            modelID: originalConnection.modelID,
            modelDisplayName: originalConnection.modelDisplayName,
            capabilities: originalConnection.capabilities,
            connectionRevision: "replacement-revision"
        )
        await connectionStore.save(AIConnectionPreferences(
            activeProviderID: replacement.providerID,
            connections: [replacement]
        ))
        await gate.resume()

        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await completion.value
        }
    }

    @Test func runtimeDiscardsACompletionWhenTheCredentialRotatesInFlight() async throws {
        let connection = StoredAIConnection(
            providerID: "openai",
            modelID: "model-a",
            modelDisplayName: "Model A",
            capabilities: ["tools"],
            connectionRevision: "original-revision"
        )
        let connectionStore = InMemoryAIConnectionStore(
            preferences: AIConnectionPreferences(
                activeProviderID: connection.providerID,
                connections: [connection]
            )
        )
        let credentialStore = SecureAIProviderCredentialStore(
            secureStore: InMemorySecureStore()
        )
        try await credentialStore.storeCredential(
            "original-secret",
            for: connection.providerID,
            connectionRevision: connection.connectionRevision
        )
        let gate = SuspendedRuntimeCompletionGate()
        let runtime = AIProviderRuntimeService(
            connectionStore: connectionStore,
            credentialStore: credentialStore,
            registry: try AIProviderRegistry(adapters: [
                SuspendedRuntimeFixtureAdapter(gate: gate),
            ]),
            transport: RuntimeRevisionFixtureTransport()
        )
        let completion = Task {
            try await runtime.complete(
                AICompletionRequest(
                    modelID: connection.modelID,
                    messages: [.user("Hello")]
                ),
                providerID: connection.providerID,
                connectionRevision: connection.connectionRevision
            )
        }
        await gate.waitUntilStarted()
        try await credentialStore.storeCredential(
            "replacement-secret",
            for: connection.providerID,
            connectionRevision: "replacement-revision"
        )
        await gate.resume()

        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await completion.value
        }
    }

    @Test func connectionBridgeSanitizesDeduplicatesAndCapsModelOptions() async throws {
        let transport = RuntimeRevisionFixtureTransport()
        let service = AIKitConnectionService(
            registry: try AIProviderRegistry(adapters: [ModelSanitizationFixtureAdapter()]),
            transport: transport
        )

        let validation = try await service.validate(
            providerID: AIProviderID.anthropic.rawValue,
            credential: SensitiveValue("fixture-key"),
            endpoint: nil
        )

        #expect(validation.models.count == 256)
        #expect(validation.models.first?.id == "stable-model")
        #expect(validation.models.first?.displayName == "First Name Wins")
        #expect(Set(validation.models.map(\.id)).count == validation.models.count)
        #expect(validation.models.allSatisfy { option in
            option.id.isEmpty == false
                && option.id.utf8.count <= 1_024
                && option.displayName.isEmpty == false
                && option.displayName.utf8.count <= 1_024
        })
    }
}

private nonisolated enum AISettingsTestFailure: Error, Sendable {
    case saveFailed
}

private actor FailingSaveAIConnectionStore: AIConnectionStoring {
    private let preferences: AIConnectionPreferences

    init(preferences: AIConnectionPreferences) {
        self.preferences = preferences
    }

    func load() -> AIConnectionPreferences {
        preferences
    }

    func save(_: AIConnectionPreferences) throws {
        throw AISettingsTestFailure.saveFailed
    }
}

private nonisolated struct OllamaValidationTransport: AIHTTPTransport {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        let body: Data
        switch request.url.path {
        case "/api/tags":
            body = Data(#"{"models":[{"name":"local-tool-model"}]}"#.utf8)
        case "/api/show":
            body = Data(#"{"capabilities":["completion","tools"]}"#.utf8)
        default:
            body = Data(#"{"error":"unexpected fixture request"}"#.utf8)
        }
        return AIHTTPResponse(
            statusCode: request.url.path == "/api/tags" || request.url.path == "/api/show"
                ? 200
                : 404,
            body: body
        )
    }
}

private nonisolated struct RuntimeRevisionFixtureAdapter: AIProviderAdapter {
    let descriptor = AIProviderDescriptor(
        id: .openAI,
        displayName: "Revision Fixture",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    func models(configuration _: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        []
    }

    func complete(
        request _: AICompletionRequest,
        configuration _: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        AICompletionResponse(
            id: "fixture",
            message: .assistant("ok"),
            finishReason: .completed
        )
    }
}

private nonisolated struct SuspendedRuntimeFixtureAdapter: AIProviderAdapter {
    let gate: SuspendedRuntimeCompletionGate
    let descriptor = AIProviderDescriptor(
        id: .openAI,
        displayName: "Suspended Revision Fixture",
        authentication: .apiKey,
        capabilities: [.modelDiscovery, .textGeneration, .toolCalling]
    )

    func models(configuration _: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        []
    }

    func complete(
        request _: AICompletionRequest,
        configuration _: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        await gate.complete()
    }
}

private actor SuspendedRuntimeCompletionGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete() async -> AICompletionResponse {
        didStart = true
        let waiters = startWaiters
        startWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            completionContinuation = continuation
        }
        return AICompletionResponse(
            id: "suspended-fixture",
            message: .assistant("stale"),
            finishReason: .completed
        )
    }

    func resume() {
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume()
    }
}

private nonisolated struct RuntimeRevisionFixtureTransport: AIHTTPTransport {
    func send(_: AIHTTPRequest) async throws -> AIHTTPResponse {
        AIHTTPResponse(statusCode: 500, body: Data())
    }
}

private nonisolated struct ModelSanitizationFixtureAdapter: AIProviderAdapter {
    let descriptor = AIProviderDescriptor(
        id: .anthropic,
        displayName: "Model Sanitization Fixture",
        authentication: .apiKey,
        capabilities: [.modelDiscovery]
    )

    func models(configuration _: AIProviderConfiguration) async throws -> [AIModelDescriptor] {
        let invalid = [
            model(id: "", displayName: "Empty ID"),
            model(id: String(repeating: "x", count: 1_025), displayName: "Long ID"),
            model(id: "empty-name", displayName: ""),
            model(id: "long-name", displayName: String(repeating: "x", count: 1_025)),
        ]
        let duplicates = [
            model(id: "stable-model", displayName: "First Name Wins"),
            model(id: "stable-model", displayName: "Duplicate"),
        ]
        let valid = (0 ..< 300).map { index in
            model(id: "model-\(index)", displayName: "Model \(index)")
        }
        return invalid + duplicates + valid
    }

    func complete(
        request _: AICompletionRequest,
        configuration _: AIProviderConfiguration
    ) async throws -> AICompletionResponse {
        throw AIProviderError.unsupportedCapability
    }

    private func model(id: String, displayName: String) -> AIModelDescriptor {
        AIModelDescriptor(
            providerID: .anthropic,
            id: id,
            displayName: displayName,
            capabilities: [.textInput, .textOutput],
            capabilityEvidence: .providerReported
        )
    }
}
