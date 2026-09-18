import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated enum EmojiSearchMode: String, CaseIterable, Identifiable { case local = "Catalog", ai = "AI Search"; var id: Self { self } }
enum EmojiSearchActionID {
    static let find = CommandActionID(rawValue: "emoji.find-with-ai")
    static let cancel = CommandActionID(rawValue: "emoji.cancel-ai")
    static let settings = CommandActionID(rawValue: "emoji.ai-settings")
    static let refresh = CommandActionID(rawValue: "emoji.refresh-providers")
}

@MainActor @Observable
final class EmojiSearchViewModel: LauncherApplicationModel {
    var query = "" { didSet { if query != oldValue { inputsChanged() } } }
    var mode: EmojiSearchMode { didSet { if mode != oldValue { inputsChanged() } } }
    var category: String? { didSet { if category != oldValue && mode == .local { inputsChanged() } } }
    var includesVariants = false { didSet { if includesVariants != oldValue && mode == .local { inputsChanged() } } }
    var providerID = "" { didSet { if providerID != oldValue && mode == .ai { inputsChanged() } } }
    var showsActionsMenu = false
    private(set) var entries: [UnicodeEmojiEntry] = []
    private(set) var selectedID: String?
    private(set) var categories: [String] = []
    private(set) var choices: [QuickAISelection] = []
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var isFindingWithAI = false
    private(set) var isLoadingChoices = false
    private(set) var isCopying = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var providerError: String?
    private(set) var hasAIResult = false
    private(set) var focusRequest = 0
    @ObservationIgnored private let services: EmojiSearchApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onOpenSettings: () -> Void
    @ObservationIgnored private var catalog: UnicodeEmojiCatalog?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var queryGeneration = UUID()
    @ObservationIgnored private var aiGeneration = UUID()
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private var pendingCopy: UUID?
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var choicesTask: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?

    init(services: EmojiSearchApplicationServices, initialMode: EmojiSearchMode = .local,
         onGoBack: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.services = services; mode = initialMode; self.onGoBack = onGoBack; self.onOpenSettings = onOpenSettings
    }
    deinit { loadingTask?.cancel(); searchTask?.cancel(); aiTask?.cancel(); choicesTask?.cancel(); copyTask?.cancel() }

    var selected: UnicodeEmojiEntry? { selectedID.flatMap { catalog?.entry(for: $0) } }
    var gridSelectionID: String? { entries.first { $0.id == selectedID }?.id ?? entries.first { $0.family == selected?.family }?.id }
    var variants: [UnicodeEmojiEntry] { selected.flatMap { catalog?.variants(of: $0) } ?? [] }
    var provider: QuickAISelection? { choices.first { $0.id == providerID } }
    var canFindWithAI: Bool {
        isActive && catalog != nil && provider?.supportsStreaming == true && !isFindingWithAI && !isLoadingChoices
            && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && query.utf8.count <= 1_024
    }
    var canCopy: Bool { isActive && selected != nil && !isSearching && !isFindingWithAI && !isCopying }
    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if isFindingWithAI { primary = .init(id: EmojiSearchActionID.find, title: "Finding Emoji…", isPrimary: true, isEnabled: false) }
        else if mode == .ai && !hasAIResult { primary = .init(id: EmojiSearchActionID.find, title: "Find with AI", isPrimary: true, keyHint: .return, isEnabled: canFindWithAI) }
        else { primary = .init(id: BuiltInCommandActionID.copy, title: "Copy Emoji", isPrimary: true, keyHint: .return, isEnabled: canCopy || isSearching) }
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: BuiltInCommandActionID.copy, title: "Copy Emoji", isEnabled: canCopy),
         .init(id: EmojiSearchActionID.find, title: "Find with AI", isEnabled: mode == .ai && canFindWithAI),
         .init(id: EmojiSearchActionID.cancel, title: "Cancel AI Search", isEnabled: isFindingWithAI),
         .init(id: EmojiSearchActionID.refresh, title: "Refresh Saved AI Connections", isEnabled: !isLoadingChoices),
         .init(id: EmojiSearchActionID.settings, title: "AI Settings…")]
    }

    func start() {
        guard !isActive else { return }
        isActive = true; isLoading = true; errorMessage = nil
        let id = UUID(); loadGeneration = id
        loadingTask = Task { [weak self, catalog = services.catalog] in
            do {
                let value = try await catalog.load()
                try Task.checkCancellation()
                guard let self, self.isActive, self.loadGeneration == id else { return }
                self.catalog = value; self.categories = value.categories; self.isLoading = false
                self.inputsChanged()
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.loadGeneration == id else { return }
                self.isLoading = false; self.errorMessage = (error as? UnicodeEmojiError)?.errorDescription ?? UnicodeEmojiError.unavailable.errorDescription
            }
        }
        refreshChoices()
    }

    func refreshChoices() {
        guard isActive, !isLoadingChoices else { return }
        isLoadingChoices = true; providerError = nil; cancelAI()
        if mode == .ai { clearResults() }
        choicesTask = Task { [weak self, semantic = services.semantic] in
            do {
                let result = try await semantic.selections()
                try Task.checkCancellation()
                guard let self, self.isActive else { return }
                self.choices = result.selections
                if !result.selections.contains(where: { $0.id == self.providerID }) {
                    self.providerID = result.preferredID.flatMap { preferred in result.selections.first { $0.id == preferred }?.id }
                        ?? result.selections.first?.id ?? ""
                }
                self.isLoadingChoices = false
            } catch {
                guard let self, !Task.isCancelled, self.isActive else { return }
                self.choices = []; self.providerID = ""; self.isLoadingChoices = false
                self.providerError = "Saved AI connections could not be loaded. Open AI Settings, then refresh."
            }
        }
    }

    private func inputsChanged() {
        queryGeneration = UUID(); pendingCopy = nil; searchTask?.cancel(); copyTask?.cancel(); isCopying = false
        cancelAI(); clearResults(); errorMessage = nil; statusMessage = nil
        guard isActive, catalog != nil, mode == .local else { isSearching = false; return }
        let id = queryGeneration
        let request = UnicodeEmojiSearchRequest(query: query, category: category, includesVariants: includesVariants)
        isSearching = true
        searchTask = Task { [weak self, catalog = services.catalog] in
            do {
                let results = try await catalog.search(request)
                try Task.checkCancellation()
                guard let self, self.isActive, self.queryGeneration == id, self.mode == .local else { return }
                self.entries = results; self.selectedID = results.first?.id; self.isSearching = false
                self.statusMessage = "\(results.count) \(results.count == 1 ? "result" : "results") · Unicode 17.0 · English names and keywords"
                if self.pendingCopy == id { self.pendingCopy = nil; self.copy() }
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.queryGeneration == id else { return }
                self.isSearching = false; self.pendingCopy = nil
                self.errorMessage = (error as? UnicodeEmojiError)?.errorDescription ?? UnicodeEmojiError.unavailable.errorDescription
            }
        }
    }

    func findWithAI() {
        guard mode == .ai, canFindWithAI, let provider, let catalog else { return }
        cancelAI(); clearResults(); errorMessage = nil; statusMessage = nil
        let id = aiGeneration; let description = query
        isFindingWithAI = true
        aiTask = Task { [weak self, semantic = services.semantic] in
            do {
                let results = try await semantic.search(description: description, selection: provider, catalog: catalog)
                try Task.checkCancellation()
                guard let self, self.isActive, self.aiGeneration == id, self.mode == .ai else { return }
                self.entries = results; self.selectedID = results.first?.id; self.isFindingWithAI = false; self.hasAIResult = true
                self.statusMessage = results.isEmpty ? "AI found no matching emoji. Edit the description and retry." : "\(results.count) AI suggestions · \(provider.title) · choose before copying"
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.aiGeneration == id else { return }
                self.isFindingWithAI = false
                self.errorMessage = (error as? UnicodeEmojiError)?.errorDescription ?? "AI search is unavailable. Check your connection in AI Settings or try another model."
            }
        }
    }

    func cancelAI() { aiGeneration = UUID(); aiTask?.cancel(); aiTask = nil; isFindingWithAI = false }
    private func clearResults() { entries = []; selectedID = nil; hasAIResult = false }
    func select(_ entry: UnicodeEmojiEntry) {
        guard entries.contains(where: { $0.id == entry.id || $0.family == entry.family }) else { return }
        selectedID = entry.id; pendingCopy = nil
    }
    func selectVariant(_ symbol: String) { guard let value = variants.first(where: { $0.id == symbol }) else { return }; select(value) }
    /// Shell Up/Down moves between rows in this six-column grid; Left/Right is handled only by the grid.
    func moveSelection(offset: Int) { moveCell(offset: offset * 6) }
    func moveCell(offset: Int) {
        guard !entries.isEmpty, !isSearching, !isFindingWithAI else { return }
        let current = entries.firstIndex { $0.id == selectedID } ?? entries.firstIndex { $0.family == selected?.family } ?? 0
        let index = min(max(current + offset, 0), entries.count - 1)
        selectedID = entries[index].id; pendingCopy = nil
    }
    func submit() {
        guard !isFindingWithAI else { return } // Rapid Return never cancels an active provider request.
        if mode == .ai && !hasAIResult { findWithAI() } else { copy() }
    }
    func copy() {
        if mode == .local && isSearching { pendingCopy = queryGeneration; return }
        guard canCopy, let symbol = selected?.symbol else { return }
        let id = queryGeneration
        isCopying = true
        copyTask = Task { [weak self, pasteboard = services.pasteboard] in
            guard !Task.isCancelled else { return }
            await pasteboard.writeString(symbol)
            guard let self, !Task.isCancelled, self.isActive, self.queryGeneration == id else { return }
            self.isCopying = false; self.statusMessage = "Emoji copied."; self.focusRequest += 1
        }
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case BuiltInCommandActionID.copy: copy()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        case EmojiSearchActionID.find: findWithAI()
        case EmojiSearchActionID.cancel: cancelAI(); statusMessage = "AI search cancelled."
        case EmojiSearchActionID.refresh: refreshChoices()
        case EmojiSearchActionID.settings: onOpenSettings()
        default: break
        }
    }
    func handleEscape() -> Bool {
        pendingCopy = nil
        if isFindingWithAI { cancelAI(); statusMessage = "AI search cancelled."; return true }
        if !query.isEmpty { query = ""; focusRequest += 1; return true }
        return false
    }
    func goBack() { stop(); onGoBack() }
    func stop() {
        isActive = false; loadGeneration = UUID(); queryGeneration = UUID(); pendingCopy = nil
        loadingTask?.cancel(); searchTask?.cancel(); choicesTask?.cancel(); copyTask?.cancel(); cancelAI()
        isLoading = false; isSearching = false; isLoadingChoices = false; isCopying = false
        query = ""; clearResults(); statusMessage = nil; errorMessage = nil
    }
    var pendingSearchForTesting: Task<Void, Never>? { searchTask }
    var pendingAIForTesting: Task<Void, Never>? { aiTask }
    func waitForLoadingForTesting() async { await loadingTask?.value; await choicesTask?.value; await searchTask?.value }
    func waitForSearchForTesting() async { await searchTask?.value; await copyTask?.value }
    func waitForAIForTesting() async { await aiTask?.value }
    func waitForCopyForTesting() async { await copyTask?.value }
}
