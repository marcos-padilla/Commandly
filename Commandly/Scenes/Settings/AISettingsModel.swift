import Foundation
import Observation
import SecurityKit

nonisolated enum AISettingsPhase: Equatable, Sendable {
    case idle
    case loading
    case validating
    case selectingModel
    case saving
    case disconnecting(String)
}

/// Main-actor state machine for provider selection, credential validation, and model choice.
@Observable
@MainActor
final class AISettingsModel {
    private let connectionStore: any AIConnectionStoring
    private let credentialStore: any AIProviderCredentialStoring
    private let connectionService: any AIConnectionServicing
    private let excludeCredentialFromClipboardHistory: @MainActor (String) -> Void
    private var validatedCredential: String?
    private var validatedProviderID: String?
    private var validatedEndpoint: String?
    private var hasLoaded = false

    let providers: [AIProviderOption]
    private(set) var preferences: AIConnectionPreferences = .empty
    private(set) var phase: AISettingsPhase = .idle
    private(set) var discoveredModels: [AIModelOption] = []
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?

    var selectedProviderID: String?
    var credentialInput = ""
    var endpointInput = ""
    var selectedModelID: String?

    init(
        connectionStore: any AIConnectionStoring,
        credentialStore: any AIProviderCredentialStoring,
        connectionService: any AIConnectionServicing,
        excludeCredentialFromClipboardHistory: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.connectionStore = connectionStore
        self.credentialStore = credentialStore
        self.connectionService = connectionService
        self.excludeCredentialFromClipboardHistory = excludeCredentialFromClipboardHistory
        self.providers = connectionService.providers
    }

    convenience init() {
        self.init(
            connectionStore: InMemoryAIConnectionStore(),
            credentialStore: SecureAIProviderCredentialStore(
                secureStore: InMemorySecureStore()
            ),
            connectionService: InMemoryAIConnectionService()
        )
    }

    var selectedProvider: AIProviderOption? {
        guard let selectedProviderID else { return nil }
        return providers.first { $0.id == selectedProviderID }
    }

    var selectedModel: AIModelOption? {
        guard let selectedModelID else { return nil }
        return discoveredModels.first { $0.id == selectedModelID }
    }

    var configuredConnections: [StoredAIConnection] {
        preferences.connections.compactMap { connection in
            providers.contains(where: { $0.id == connection.providerID }) ? connection : nil
        }
    }

    var isBusy: Bool {
        switch phase {
        case .loading, .validating, .saving, .disconnecting:
            return true
        case .idle, .selectingModel:
            return false
        }
    }

    var canValidate: Bool {
        guard let provider = selectedProvider, isBusy == false else { return false }
        if provider.requiresCredential == false { return true }
        if credentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        return preferences.connection(for: provider.id) != nil
    }

    var canSave: Bool {
        guard phase == .selectingModel,
              selectedModel != nil,
              let provider = selectedProvider,
              validatedProviderID == provider.id else {
            return false
        }
        if provider.requiresCredential {
            if let validatedCredential {
                guard credentialInput == validatedCredential else { return false }
            } else {
                guard credentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
            }
        }
        if provider.allowsEndpointEditing, endpointInput != validatedEndpoint {
            return false
        }
        return true
    }

    func load() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        phase = .loading
        defer {
            if phase == .loading { phase = .idle }
        }
        do {
            preferences = try await connectionStore.load()
        } catch is CancellationError {
            hasLoaded = false
        } catch {
            errorMessage = "Your saved AI connections couldn’t be loaded."
        }
    }

    func selectProvider(_ providerID: String) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        selectedProviderID = provider.id
        credentialInput = ""
        invalidateValidatedDraft()
        discoveredModels = []
        selectedModelID = preferences.connection(for: provider.id)?.modelID
        endpointInput = preferences.connection(for: provider.id)?.endpoint
            ?? provider.defaultEndpoint
            ?? ""
        phase = .idle
        statusMessage = nil
        errorMessage = nil
    }

    func resetDraft() {
        selectedProviderID = nil
        credentialInput = ""
        invalidateValidatedDraft()
        endpointInput = ""
        selectedModelID = nil
        discoveredModels = []
        phase = .idle
        statusMessage = nil
        errorMessage = nil
    }

    func validate() {
        Task { await validateNow() }
    }

    /// Called as the concealed field changes so a pasted credential is removed from Commandly's
    /// clipboard history immediately, even if the user closes Settings without validating it.
    func credentialDraftDidChange() {
        let candidate = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else { return }
        excludeCredentialFromClipboardHistory(candidate)
    }

    func validateNow() async {
        guard let provider = selectedProvider, canValidate else { return }
        phase = .validating
        statusMessage = nil
        errorMessage = nil
        discoveredModels = []
        selectedModelID = nil
        invalidateValidatedDraft()

        do {
            let credential = try await credentialForValidation(provider: provider)
            let validation = try await connectionService.validate(
                providerID: provider.id,
                credential: credential.map(SensitiveValue.init),
                endpoint: provider.allowsEndpointEditing ? endpointInput : nil
            )
            try Task.checkCancellation()
            discoveredModels = validation.models
            endpointInput = validation.normalizedEndpoint ?? endpointInput
            validatedProviderID = provider.id
            validatedEndpoint = provider.allowsEndpointEditing ? endpointInput : nil
            selectedModelID = preferredModelID(
                for: provider.id,
                in: validation.models
            )
            phase = .selectingModel
            statusMessage = validation.models.count == 1
                ? "Credential validated. Choose the available model to finish."
                : "Credential validated. Choose from \(validation.models.count) available models."
        } catch is CancellationError {
            invalidateValidatedDraft()
            phase = .idle
        } catch let error as AIConnectionServiceError {
            invalidateValidatedDraft()
            phase = .idle
            errorMessage = message(for: error)
        } catch {
            invalidateValidatedDraft()
            phase = .idle
            errorMessage = "That provider couldn’t be reached. Your credential was not saved."
        }
    }

    func saveSelection() {
        Task { await saveSelectionNow() }
    }

    func saveSelectionNow() async {
        guard let provider = selectedProvider,
              let model = selectedModel,
              canSave else { return }
        phase = .saving
        errorMessage = nil
        statusMessage = nil
        let connectionRevision = UUID().uuidString
        var previousCredential: StoredAIProviderCredential?
        var wroteCredential = false

        do {
            if provider.requiresCredential {
                previousCredential = try await credentialStore.credentialRecord(for: provider.id)
                guard let credential = validatedCredential ?? previousCredential?.reveal() else {
                    throw AIConnectionServiceError.invalidCredential
                }
                try await credentialStore.storeCredential(
                    credential,
                    for: provider.id,
                    connectionRevision: connectionRevision
                )
                wroteCredential = true
            }
            var updated = preferences
            updated.upsert(
                StoredAIConnection(
                    providerID: provider.id,
                    modelID: model.id,
                    modelDisplayName: model.displayName,
                    endpoint: provider.allowsEndpointEditing ? endpointInput : nil,
                    capabilities: model.capabilities,
                    connectionRevision: connectionRevision
                ),
                makeActive: true
            )
            try await connectionStore.save(updated)
            preferences = updated
            credentialInput = ""
            invalidateValidatedDraft()
            phase = .idle
            statusMessage = "\(provider.title) is connected and active."
        } catch is CancellationError {
            if wroteCredential {
                _ = await restoreCredential(previousCredential, for: provider.id)
            }
            phase = .selectingModel
        } catch {
            let rollbackSucceeded = wroteCredential
                ? await restoreCredential(previousCredential, for: provider.id)
                : true
            phase = .selectingModel
            errorMessage = rollbackSucceeded
                ? "The validated connection couldn’t be saved securely."
                : "The connection couldn’t be saved completely. Review its Keychain entry before trying again."
        }
    }

    func makeActive(_ providerID: String) {
        Task { await makeActiveNow(providerID) }
    }

    func makeActiveNow(_ providerID: String) async {
        guard preferences.connection(for: providerID) != nil,
              preferences.activeProviderID != providerID,
              isBusy == false else { return }
        phase = .saving
        var updated = preferences
        updated.activeProviderID = providerID
        do {
            try await connectionStore.save(updated)
            preferences = updated
            phase = .idle
            statusMessage = "Active AI provider changed."
            errorMessage = nil
        } catch {
            phase = .idle
            errorMessage = "The active provider couldn’t be changed."
        }
    }

    func disconnect(_ providerID: String) {
        Task { await disconnectNow(providerID) }
    }

    func disconnectNow(_ providerID: String) async {
        guard preferences.connection(for: providerID) != nil else { return }
        phase = .disconnecting(providerID)
        statusMessage = nil
        errorMessage = nil
        var removedCredential: StoredAIProviderCredential?
        var deletedCredential = false
        do {
            removedCredential = try await credentialStore.credentialRecord(for: providerID)
            try await credentialStore.deleteCredential(for: providerID)
            deletedCredential = true
            var updated = preferences
            updated.remove(providerID: providerID)
            try await connectionStore.save(updated)
            preferences = updated
            if selectedProviderID == providerID { resetDraft() }
            phase = .idle
            statusMessage = "Provider connection removed from this Mac."
        } catch {
            let rollbackSucceeded = deletedCredential
                ? await restoreCredential(removedCredential, for: providerID)
                : true
            phase = .idle
            errorMessage = rollbackSucceeded
                ? "That provider connection couldn’t be removed securely."
                : "The connection couldn’t be removed completely. Review its Keychain entry before trying again."
        }
    }

    private func credentialForValidation(
        provider: AIProviderOption
    ) async throws -> String? {
        guard provider.requiresCredential else {
            validatedCredential = nil
            return nil
        }
        let candidate = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty == false {
            guard candidate.utf8.count <= 8_192 else {
                throw AIConnectionServiceError.invalidCredential
            }
            credentialInput = candidate
            excludeCredentialFromClipboardHistory(candidate)
            validatedCredential = candidate
            return candidate
        }
        guard let existing = try await credentialStore.credential(for: provider.id) else {
            throw AIConnectionServiceError.invalidCredential
        }
        validatedCredential = nil
        return existing
    }

    private func invalidateValidatedDraft() {
        validatedCredential = nil
        validatedProviderID = nil
        validatedEndpoint = nil
    }

    private func restoreCredential(
        _ credential: StoredAIProviderCredential?,
        for providerID: String
    ) async -> Bool {
        let credentialStore = credentialStore
        // Compensation must still run when the user cancels the parent save task after a
        // Keychain write. A new, awaited task gives cleanup an uncancelled context without using a
        // detached task or allowing cleanup to outlive this state transition.
        return await Task {
            do {
                if let credential {
                    try await credentialStore.storeCredential(
                        credential.reveal(),
                        for: providerID,
                        connectionRevision: credential.connectionRevision
                    )
                } else {
                    try await credentialStore.deleteCredential(for: providerID)
                }
                return true
            } catch {
                return false
            }
        }.value
    }

    private func preferredModelID(
        for providerID: String,
        in models: [AIModelOption]
    ) -> String? {
        if let saved = preferences.connection(for: providerID)?.modelID,
           models.contains(where: { $0.id == saved }) {
            return saved
        }
        return models.first(where: \.supportsTools)?.id ?? models.first?.id
    }

    private func message(for error: AIConnectionServiceError) -> String {
        switch error {
        case .invalidCredential:
            return "The provider rejected that credential. Check it and try again."
        case .insufficientPermission:
            return "The credential is recognized but cannot list the required models."
        case .billingUnavailable:
            return "The provider reports that billing or quota is unavailable."
        case .rateLimited:
            return "The provider rate- or quota-limited validation. Try again later; if it persists, check account credits and spending limits."
        case .noCompatibleModels:
            return "The credential works, but no compatible text model is available."
        case .invalidEndpoint:
            return "Use a valid loopback URL for the local provider."
        case .unsupportedRuntime:
            return "Model discovery works, but this provider’s tool runtime is not ready yet."
        case .unavailable:
            return "That provider is temporarily unavailable. The credential was not saved."
        }
    }
}
