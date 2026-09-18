import AIKit
import Foundation
import Observation

@Observable @MainActor final class AIAgentLibrary {
    private(set) var document = AIAgentLibraryDocument()
    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var status: String?
    @ObservationIgnored private let store: any AIAgentLibraryStoring
    @ObservationIgnored var onCatalogChange: (() throws -> Void)?
    init(store: any AIAgentLibraryStoring) { self.store = store }
    func load() async throws {
        guard isLoaded == false else { return }
        let loaded = try await store.load()
        guard isLoaded == false else { return }
        document = loaded; isLoaded = true
        do { try onCatalogChange?() } catch { status = "Agents loaded, but launcher entries could not be refreshed." }
    }
    func loadForLauncher() async {
        do { try await load() }
        catch { status = "Saved agents could not be loaded. Open AI Agents to retry." }
    }
    func update(_ edit: (inout AIAgentLibraryDocument) -> Void) async throws {
        guard isSaving == false else { throw AIAgentLibraryError.busy }
        try await load()
        guard isSaving == false else { throw AIAgentLibraryError.busy }
        isSaving = true; defer { isSaving = false }
        let previous = document
        var next = previous; edit(&next); next.revision = UUID()
        try next.validate()
        try await store.save(next, replacing: previous.revision)
        document = next; status = nil
        do { try onCatalogChange?() } catch { status = "Saved locally, but launcher entries could not be refreshed. Reopen Commandly to reload them." }
    }
    func importedSkill(from url: URL) async throws -> AIAgentSkill { try await store.importSkill(from: url) }
}

/// An agent adds only reviewed text context to the existing Quick AI runtime. It cannot acquire tools.
nonisolated struct AIAgentQuickAIService: QuickAIServicing {
    let base: any QuickAIServicing
    let selection: QuickAISelection
    let context: AIMessage
    let validateContext: @MainActor @Sendable () throws -> Void
    func catalog() async throws -> QuickAICatalog {
        try await validateContext()
        let saved = try await base.catalog()
        guard saved.selections.contains(where: { $0.providerID == selection.providerID && $0.connectionRevision == selection.connectionRevision }) else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        return .init(selections: [selection], preferredID: selection.id)
    }
    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection] {
        try await validateContext()
        let refreshed = try await base.refreshModels(for: selection)
        try await validateContext()
        return refreshed.filter { $0.providerID == self.selection.providerID && $0.modelID == self.selection.modelID }
    }
    func respond(messages: [AIMessage], selection: QuickAISelection,
                 onTextDelta: @escaping @Sendable (String) async throws -> Void) async throws -> AICompletionResponse {
        try await validateContext()
        guard selection.providerID == self.selection.providerID, selection.modelID == self.selection.modelID,
              selection.connectionRevision == self.selection.connectionRevision else { throw AIProviderRuntimeError.modelMismatch }
        let request = [context] + messages.filter { $0.role != .system }
        let validate = validateContext
        let reply = try await base.respond(messages: request, selection: selection) { delta in
            try await validate(); try Task.checkCancellation(); try await onTextDelta(delta)
        }
        try await validateContext(); return reply
    }
}

@MainActor struct AIAgentsApplicationServices {
    let library: AIAgentLibrary
    let chat: any QuickAIServicing
    static func live(chat: any QuickAIServicing) -> Self { .init(library: .init(store: LocalAIAgentLibraryStore.applicationStore()), chat: chat) }
    static var inMemory: Self { .init(library: .init(store: InMemoryAIAgentLibraryStore()), chat: InMemoryQuickAIService()) }
}
