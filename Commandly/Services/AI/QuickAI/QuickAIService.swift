import AIKit
import Foundation
import SecurityKit

/// A non-secret provider/model choice. Discovered models carry a session-only connection pin.
nonisolated struct QuickAISelection: Equatable, Identifiable, Sendable {
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let connectionRevision: String
    let supportsStreaming: Bool
    // A caller cannot mint a discovered choice with the ordinary saved-pair initializer.
    // This contains only metadata, never a credential or provider response body.
    fileprivate let discoveredFrom: StoredAIConnection?
    fileprivate let discoveredModel: AIModelOption?

    init(providerID: String, providerName: String, modelID: String, modelName: String,
         connectionRevision: String, supportsStreaming: Bool) {
        self.providerID = providerID; self.providerName = providerName
        self.modelID = modelID; self.modelName = modelName
        self.connectionRevision = connectionRevision; self.supportsStreaming = supportsStreaming
        discoveredFrom = nil; discoveredModel = nil
    }

    fileprivate init(connection: StoredAIConnection, model: AIModelOption, provider: AIProviderDescriptor) {
        providerID = connection.providerID; providerName = provider.displayName
        modelID = model.id; modelName = model.displayName
        connectionRevision = connection.connectionRevision
        supportsStreaming = AITextStreamingTransport.supports(provider.id)
        discoveredFrom = connection; discoveredModel = model
    }

    var id: String { providerID + ":" + connectionRevision + ":" + modelID }
    var title: String { providerName + " · " + modelName }
}

nonisolated struct QuickAICatalog: Equatable, Sendable {
    let selections: [QuickAISelection]
    let preferredID: String?
    static let empty = QuickAICatalog(selections: [], preferredID: nil)
}

/// The chat has no credential, filesystem, clipboard, browser, or tool capability.
nonisolated protocol QuickAIServicing: Sendable {
    func catalog() async throws -> QuickAICatalog
    /// Explicitly requests text-model metadata using the selected saved connection.
    /// Returned choices live only in the caller's session; no preference is saved.
    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection]
    func respond(
        messages: [AIMessage], selection: QuickAISelection,
        onTextDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws -> AICompletionResponse
}

extension QuickAIServicing {
    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection] {
        throw AIConnectionServiceError.unsupportedRuntime
    }
}

/// Reuses the reviewed provider runtime and adapters with a text-streaming HTTP bridge.
nonisolated struct NativeQuickAIService: QuickAIServicing {
    private let connections: any AIConnectionStoring
    private let credentials: any AIProviderCredentialStoring
    private let registry: AIProviderRegistry
    private let streamTransport: any AIHTTPStreamingTransport
    private let discovery: (any AIConnectionServicing)?

    init(connectionStore: any AIConnectionStoring, credentialStore: any AIProviderCredentialStoring,
         registry: AIProviderRegistry, streamTransport: any AIHTTPStreamingTransport,
         modelDiscovery: (any AIConnectionServicing)? = nil) {
        connections = connectionStore
        credentials = credentialStore
        self.registry = registry
        self.streamTransport = streamTransport
        discovery = modelDiscovery
    }

    func catalog() async throws -> QuickAICatalog {
        let preferences = try await connections.load()
        try Task.checkCancellation()
        let selections = preferences.connections.prefix(32).compactMap { connection -> QuickAISelection? in
            guard let descriptor = registry.providers.first(where: { $0.id.rawValue == connection.providerID }),
                  descriptor.capabilities.contains(.textGeneration) else { return nil }
            return QuickAISelection(providerID: connection.providerID, providerName: descriptor.displayName,
                modelID: connection.modelID, modelName: connection.modelDisplayName,
                connectionRevision: connection.connectionRevision,
                supportsStreaming: AITextStreamingTransport.supports(descriptor.id))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return QuickAICatalog(selections: selections,
            preferredID: selections.first { $0.providerID == preferences.activeProviderID }?.id)
    }

    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection] {
        try Task.checkCancellation()
        guard let discovery else { throw AIConnectionServiceError.unsupportedRuntime }
        let connection = try await matchingConnection(selection)
        let descriptor = try registry.adapter(for: .init(rawValue: connection.providerID)).descriptor
        guard descriptor.capabilities.contains(.textGeneration), AITextStreamingTransport.supports(descriptor.id) else {
            throw AIConnectionServiceError.unsupportedRuntime
        }
        let record = descriptor.authentication == .none ? nil : try await credentials.credentialRecord(for: connection.providerID)
        if descriptor.authentication == .apiKey && record == nil { throw AIProviderRuntimeError.credentialUnavailable }
        if let record, record.connectionRevision != connection.connectionRevision { throw AIProviderRuntimeError.connectionMismatch }
        // Recheck after the credential lookup before transmitting even a metadata request.
        guard try await connections.load().connection(for: connection.providerID) == connection else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        try Task.checkCancellation()
        let result = try await discovery.validate(providerID: connection.providerID,
            credential: record.map { SensitiveValue($0.reveal()) }, endpoint: connection.endpoint)
        try Task.checkCancellation()
        let pin = QuickAIConnectionPin(source: connections, credentials: credentials, expected: connection,
            projected: connection, authentication: descriptor.authentication)
        try await pin.validate()
        var seen: Set<String> = []
        let models = result.models.filter { model in
            model.capabilities.isSuperset(of: ["text-input", "text-output"])
                && Self.isValidModelText(model.id) && Self.isValidModelText(model.displayName)
                && seen.insert(model.id).inserted
        }.prefix(256).map { QuickAISelection(connection: connection, model: $0, provider: descriptor) }
        guard models.isEmpty == false else { throw AIConnectionServiceError.noCompatibleModels }
        return models.sorted { $0.modelName.localizedStandardCompare($1.modelName) == .orderedAscending }
    }

    private static func isValidModelText(_ text: String) -> Bool {
        text.isEmpty == false && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && text.utf8.count <= 1_024 && text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) == false
    }

    private func matchingConnection(_ selection: QuickAISelection) async throws -> StoredAIConnection {
        let preferences = try await connections.load()
        guard let connection = preferences.connection(for: selection.providerID),
              connection.connectionRevision == selection.connectionRevision else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        if let original = selection.discoveredFrom {
            guard original == connection, selection.discoveredModel?.id == selection.modelID else {
                throw AIProviderRuntimeError.connectionMismatch
            }
        } else if connection.modelID != selection.modelID { throw AIProviderRuntimeError.modelMismatch }
        return connection
    }

    func respond(messages: [AIMessage], selection: QuickAISelection,
                 onTextDelta: @escaping @Sendable (String) async throws -> Void) async throws -> AICompletionResponse {
        try Task.checkCancellation()
        guard selection.supportsStreaming, AITextStreamingTransport.supports(.init(rawValue: selection.providerID)),
              messages.count <= 64,
              messages.allSatisfy({ $0.toolCalls.isEmpty && $0.toolResults.isEmpty && $0.role != .tool
                  && $0.content.allSatisfy { if case .text = $0 { return true }; return false } }),
              messages.reduce(0, { $0 + $1.content.reduce(0, { sum, content in
                  if case .text(let value) = content { return sum + value.utf8.count }; return sum
              }) }) <= 1_024 * 1_024 else { throw AIProviderError.invalidRequest }
        let connection = try await matchingConnection(selection)
        let descriptor = try registry.adapter(for: .init(rawValue: selection.providerID)).descriptor
        let projected = selection.discoveredModel.map { model in
            StoredAIConnection(providerID: connection.providerID, modelID: model.id,
                modelDisplayName: model.displayName, endpoint: connection.endpoint,
                capabilities: model.capabilities, connectionRevision: connection.connectionRevision)
        } ?? connection
        let pin = QuickAIConnectionPin(source: connections, credentials: credentials,
            expected: connection, projected: projected, authentication: descriptor.authentication)
        let bridge = AITextStreamingTransport(providerID: .init(rawValue: selection.providerID), transport: streamTransport) { delta in
            // Validate before making provisional text visible as well as in the final runtime check.
            try await pin.validate()
            try Task.checkCancellation()
            try await onTextDelta(delta)
        }
        let runtime = AIProviderRuntimeService(connectionStore: pin, credentialStore: credentials,
            registry: try AIProviderRegistry.standard(transport: bridge), transport: bridge)
        let response = try await runtime.complete(AICompletionRequest(modelID: selection.modelID,
            messages: messages, tools: [], toolChoice: .none, maximumOutputTokens: 2_048),
            providerID: selection.providerID, connectionRevision: selection.connectionRevision)
        try Task.checkCancellation()
        guard response.message.role == .assistant, response.message.toolCalls.isEmpty,
              response.message.toolResults.isEmpty,
              [.completed, .length, .contentFiltered, .refused].contains(response.finishReason),
              response.message.content.allSatisfy({ if case .text = $0 { return true }; return false }) else {
            throw AIProviderError.invalidProviderResponse
        }
        return response
    }
}

/// Read-only projection selects one saved connection without changing global AI Settings.
private nonisolated struct QuickAIConnectionPin: AIConnectionStoring {
    let source: any AIConnectionStoring
    let credentials: any AIProviderCredentialStoring
    let expected: StoredAIConnection
    let projected: StoredAIConnection
    let authentication: AIAuthenticationRequirement

    func load() async throws -> AIConnectionPreferences {
        var preferences = try await source.load()
        guard preferences.connection(for: expected.providerID) == expected else { throw AIProviderRuntimeError.connectionMismatch }
        preferences.upsert(projected, makeActive: true)
        return preferences
    }

    func save(_ preferences: AIConnectionPreferences) async throws { throw AIProviderRuntimeError.connectionMismatch }

    func validate() async throws {
        _ = try await load()
        if authentication != .none {
            let record = try await credentials.credentialRecord(for: expected.providerID)
            if authentication == .apiKey && record == nil { throw AIProviderRuntimeError.credentialUnavailable }
            if let record, record.connectionRevision != expected.connectionRevision { throw AIProviderRuntimeError.connectionMismatch }
        }
    }
}

/// Deterministic inert service for previews and composition defaults; never opens Keychain or network.
nonisolated struct InMemoryQuickAIService: QuickAIServicing {
    let choices: QuickAICatalog
    let reply: String
    let discoveredChoices: [QuickAISelection]
    init(choices: QuickAICatalog = .empty, reply: String = "This is a local preview response.",
         discoveredChoices: [QuickAISelection] = []) {
        self.choices = choices
        self.reply = reply
        self.discoveredChoices = discoveredChoices
    }
    func catalog() async throws -> QuickAICatalog { choices }
    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection] {
        try Task.checkCancellation()
        return (choices.selections + discoveredChoices).filter {
            $0.providerID == selection.providerID && $0.connectionRevision == selection.connectionRevision
        }
    }
    func respond(messages: [AIMessage], selection: QuickAISelection,
                 onTextDelta: @escaping @Sendable (String) async throws -> Void) async throws -> AICompletionResponse {
        guard (choices.selections + discoveredChoices).contains(selection) else { throw AIProviderRuntimeError.connectionMismatch }
        try Task.checkCancellation()
        try await onTextDelta(reply)
        return .init(id: nil, message: .assistant(reply), finishReason: .completed)
    }
}
