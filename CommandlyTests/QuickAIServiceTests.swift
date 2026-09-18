import AIKit
import Foundation
import Testing
@testable import Commandly

@MainActor
struct QuickAIServiceTests {
    @Test func catalogUsesSavedMetadataWithoutCredentialOrProviderTraffic() async throws {
        let connection = Self.connection(provider: "groq", model: "fixture-model", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [connection]))
        let credentials = QuickAIFixtureCredentialStore()
        let stream = QuickAIFixtureStreamTransport()
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let catalog = try await service.catalog()
        #expect(catalog.selections.count == 1)
        #expect(catalog.selections.first?.modelID == "fixture-model")
        #expect(catalog.selections.first?.supportsStreaming == true)
        #expect(await credentials.readCount == 0)
        #expect(await stream.requests.isEmpty)
    }

    @Test func selectedSavedPairStreamsWithNoToolsAndDoesNotChangeGlobalActiveProvider() async throws {
        let first = Self.connection(provider: "openai", model: "first-model", revision: "first")
        let selected = Self.connection(provider: "groq", model: "chosen-model", revision: "chosen")
        let preferences = AIConnectionPreferences(activeProviderID: "openai", connections: [first, selected])
        let store = InMemoryAIConnectionStore(preferences: preferences)
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "chosen")
        let stream = QuickAIFixtureStreamTransport()
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let catalog = try await service.catalog()
        let choice = try #require(catalog.selections.first { $0.providerID == "groq" })
        let recorder = QuickAIRuntimeTextRecorder()
        let response = try await service.respond(messages: [.system("Text only"), .user("Question")], selection: choice) {
            await recorder.append($0)
        }
        #expect(await recorder.values == ["Hello", " world"])
        #expect(response.message == .assistant("Hello world"))
        #expect(await store.load() == preferences)
        let request = try #require(await stream.requests.first)
        #expect(request.url.host == "api.groq.com")
        let data = try #require(request.body)
        let body = try AIJSONValue(data: data)
        #expect(body["model"]?.stringValue == "chosen-model")
        #expect(body["tools"]?.arrayValue?.isEmpty != false)
        #expect(body["stream"]?.booleanValue == true)
    }

    @Test func staleSelectionFailsBeforeAnyRequest() async throws {
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq",
            connections: [Self.connection(provider: "groq", model: "model", revision: "old")]))
        let credentials = QuickAIFixtureCredentialStore()
        let stream = QuickAIFixtureStreamTransport()
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let catalog = try await service.catalog()
        let choice = try #require(catalog.selections.first)
        await store.save(.init(activeProviderID: "groq",
            connections: [Self.connection(provider: "groq", model: "model", revision: "new")]))
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await service.respond(messages: [.user("Question")], selection: choice, onTextDelta: { _ in })
        }
        #expect(await stream.requests.isEmpty)
        #expect(await credentials.readCount == 0)
    }

    @Test func credentialRotationBetweenChunksStopsBeforeNewTextIsExposed() async throws {
        let connection = Self.connection(provider: "groq", model: "model", revision: "original")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [connection]))
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "original")
        let stream = QuickAIFixtureStreamTransport(afterFirstDelta: {
            await credentials.storeCredential("fixture-replacement", for: "groq", connectionRevision: "changed")
        })
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let catalog = try await service.catalog()
        let choice = try #require(catalog.selections.first)
        let recorder = QuickAIRuntimeTextRecorder()
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await service.respond(messages: [.user("Question")], selection: choice) { await recorder.append($0) }
        }
        #expect(await recorder.values == ["Hello"])
    }

    @Test func toolMessagesAreRejectedBeforeCredentialOrNetworkAccess() async throws {
        let connection = Self.connection(provider: "groq", model: "model", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [connection]))
        let credentials = QuickAIFixtureCredentialStore()
        let stream = QuickAIFixtureStreamTransport()
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let catalog = try await service.catalog()
        let choice = try #require(catalog.selections.first)
        await #expect(throws: AIProviderError.invalidRequest) {
            try await service.respond(messages: [AIMessage(role: .tool)], selection: choice, onTextDelta: { _ in })
        }
        #expect(await credentials.readCount == 0)
        #expect(await stream.requests.isEmpty)
    }

    @Test func explicitDiscoveryUsesReviewedAdapterAndChosenModelWithoutSavingPreferences() async throws {
        let selected = Self.connection(provider: "groq", model: "saved-model", revision: "one")
        let preferences = AIConnectionPreferences(activeProviderID: "openai", connections: [
            Self.connection(provider: "openai", model: "other", revision: "two"), selected
        ])
        let store = InMemoryAIConnectionStore(preferences: preferences)
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "one")
        let stream = QuickAIFixtureStreamTransport()
        let metadata = QuickAIFixtureModelTransport()
        let registry = try AIProviderRegistry.standard(transport: metadata)
        let service = NativeQuickAIService(connectionStore: store, credentialStore: credentials,
            registry: registry, streamTransport: stream,
            modelDiscovery: AIKitConnectionService(registry: registry, transport: metadata))
        let catalog = try await service.catalog()
        let saved = try #require(catalog.selections.first { $0.providerID == "groq" })
        #expect(await credentials.readCount == 0)
        #expect(await metadata.requests.isEmpty)
        let discovered = try await service.refreshModels(for: saved)
        #expect(discovered.map(\.modelID) == ["llama-3.3-70b-versatile"])
        let request = try #require(await metadata.requests.first)
        #expect(request.method == .get)
        #expect(request.url.host == "api.groq.com")
        #expect(request.body == nil)
        #expect(await store.load() == preferences)
        let choice = try #require(discovered.first)
        _ = try await service.respond(messages: [.user("Use the discovered model")], selection: choice, onTextDelta: { _ in })
        let generation = try #require(await stream.requests.first)
        let data = try #require(generation.body)
        #expect(try AIJSONValue(data: data)["model"]?.stringValue == choice.modelID)
        #expect(await store.load() == preferences)
    }

    @Test func undiscoveredModelCannotBypassSavedSelection() async throws {
        let connection = Self.connection(provider: "groq", model: "saved", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [connection]))
        let credentials = QuickAIFixtureCredentialStore()
        let stream = QuickAIFixtureStreamTransport()
        let service = try makeService(store: store, credentials: credentials, stream: stream)
        let choice = QuickAISelection(providerID: "groq", providerName: "Groq", modelID: "not-discovered",
            modelName: "Not discovered", connectionRevision: "one", supportsStreaming: true)
        await #expect(throws: AIProviderRuntimeError.modelMismatch) {
            try await service.respond(messages: [.user("Question")], selection: choice, onTextDelta: { _ in })
        }
        #expect(await credentials.readCount == 0)
        #expect(await stream.requests.isEmpty)
    }

    @Test func changedCredentialDuringModelDiscoveryInvalidatesReturnedChoices() async throws {
        let connection = Self.connection(provider: "groq", model: "saved", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [connection]))
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "one")
        let metadata = QuickAIFixtureModelTransport(afterRequest: {
            await credentials.storeCredential("fixture-rotated", for: "groq", connectionRevision: "two")
        })
        let registry = try AIProviderRegistry.standard(transport: metadata)
        let service = NativeQuickAIService(connectionStore: store, credentialStore: credentials,
            registry: registry, streamTransport: QuickAIFixtureStreamTransport(),
            modelDiscovery: AIKitConnectionService(registry: registry, transport: metadata))
        let catalog = try await service.catalog()
        let selection = try #require(catalog.selections.first)
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) { try await service.refreshModels(for: selection) }
        #expect(await metadata.requests.count == 1)
    }

    @Test func discoveredChoicesExpireWhenOriginalConnectionChanges() async throws {
        let original = Self.connection(provider: "groq", model: "saved", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [original]))
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "one")
        let metadata = QuickAIFixtureModelTransport()
        let registry = try AIProviderRegistry.standard(transport: metadata)
        let stream = QuickAIFixtureStreamTransport()
        let service = NativeQuickAIService(connectionStore: store, credentialStore: credentials,
            registry: registry, streamTransport: stream,
            modelDiscovery: AIKitConnectionService(registry: registry, transport: metadata))
        let catalog = try await service.catalog()
        let saved = try #require(catalog.selections.first)
        let choices = try await service.refreshModels(for: saved)
        let selected = try #require(choices.first)
        // Even a malformed external edit that keeps the revision cannot reuse this metadata grant.
        await store.save(.init(activeProviderID: "groq", connections: [Self.connection(provider: "groq", model: "changed", revision: "one")]))
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await service.respond(messages: [.user("Question")], selection: selected, onTextDelta: { _ in })
        }
        #expect(await stream.requests.isEmpty)
    }

    @Test func discoveryFiltersCapabilitiesNamesDuplicatesAndRetainedCount() async throws {
        let original = Self.connection(provider: "groq", model: "saved", revision: "one")
        let store = InMemoryAIConnectionStore(preferences: .init(activeProviderID: "groq", connections: [original]))
        let credentials = QuickAIFixtureCredentialStore()
        await credentials.storeCredential("fixture-key", for: "groq", connectionRevision: "one")
        let valid = AIModelOption(id: "valid", displayName: "Valid", capabilities: ["text-input", "text-output"])
        var models = [valid, valid,
            AIModelOption(id: "no-input", displayName: "No input", capabilities: ["text-output"]),
            AIModelOption(id: " bad ", displayName: "Bad", capabilities: valid.capabilities),
            AIModelOption(id: "control", displayName: "Bad\nname", capabilities: valid.capabilities)]
        models += (0..<300).map { AIModelOption(id: "model-\($0)", displayName: "Model \($0)", capabilities: valid.capabilities) }
        let registry = try AIProviderRegistry.standard(transport: QuickAIDisabledHTTPTransport())
        let service = NativeQuickAIService(connectionStore: store, credentialStore: credentials,
            registry: registry, streamTransport: QuickAIFixtureStreamTransport(),
            modelDiscovery: InMemoryAIConnectionService(modelsByProvider: ["groq": models]))
        let catalog = try await service.catalog()
        let selection = try #require(catalog.selections.first)
        let choices = try await service.refreshModels(for: selection)
        #expect(choices.count == 256)
        #expect(choices.filter { $0.modelID == "valid" }.count == 1)
        #expect(choices.contains { ["no-input", " bad ", "control"].contains($0.modelID) } == false)
    }

    private static func connection(provider: String, model: String, revision: String) -> StoredAIConnection {
        StoredAIConnection(providerID: provider, modelID: model, modelDisplayName: model, connectionRevision: revision)
    }
    private func makeService(store: InMemoryAIConnectionStore, credentials: QuickAIFixtureCredentialStore,
                             stream: QuickAIFixtureStreamTransport) throws -> NativeQuickAIService {
        NativeQuickAIService(connectionStore: store, credentialStore: credentials,
            registry: try AIProviderRegistry.standard(transport: QuickAIDisabledHTTPTransport()), streamTransport: stream)
    }
}

private actor QuickAIFixtureCredentialStore: AIProviderCredentialStoring {
    private var values: [String: StoredAIProviderCredential] = [:]
    private(set) var readCount = 0
    func credentialRecord(for providerID: String) async throws -> StoredAIProviderCredential? { readCount += 1; return values[providerID] }
    func storeCredential(_ credential: String, for providerID: String, connectionRevision: String) {
        values[providerID] = .init(value: credential, connectionRevision: connectionRevision)
    }
    func deleteCredential(for providerID: String) { values.removeValue(forKey: providerID) }
}

private actor QuickAIFixtureStreamTransport: AIHTTPStreamingTransport {
    private(set) var requests: [AIHTTPRequest] = []
    let afterFirstDelta: (@Sendable () async -> Void)?
    init(afterFirstDelta: (@Sendable () async -> Void)? = nil) { self.afterFirstDelta = afterFirstDelta }
    func send(_ request: AIHTTPRequest, onLine: @escaping @concurrent @Sendable (String) async throws -> Void) async throws -> AIHTTPResponse {
        requests.append(request)
        let lines = [
            #"data: {"choices":[{"index":0,"delta":{"content":"Hello"}}]}"#, "",
            #"data: {"choices":[{"index":0,"delta":{"content":" world"},"finish_reason":"stop"}]}"#, "",
            "data: [DONE]", ""
        ]
        for (index, line) in lines.enumerated() {
            try Task.checkCancellation()
            try await onLine(line)
            if index == 1 { await afterFirstDelta?() }
        }
        return .init(statusCode: 200)
    }
}

private nonisolated struct QuickAIDisabledHTTPTransport: AIHTTPTransport {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse { throw AIProviderError.networkUnavailable }
}

private actor QuickAIRuntimeTextRecorder {
    private(set) var values: [String] = []
    func append(_ text: String) { values.append(text) }
}

/// Canned official model-list wire data; no network client or user credential is used.
private actor QuickAIFixtureModelTransport: AIHTTPTransport {
    private(set) var requests: [AIHTTPRequest] = []
    let afterRequest: (@Sendable () async -> Void)?
    init(afterRequest: (@Sendable () async -> Void)? = nil) { self.afterRequest = afterRequest }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        requests.append(request)
        await afterRequest?()
        return .init(statusCode: 200, body: Data(#"{"data":[{"id":"llama-3.3-70b-versatile","active":true},{"id":"whisper-large-v3","active":true}]}"#.utf8))
    }
}
