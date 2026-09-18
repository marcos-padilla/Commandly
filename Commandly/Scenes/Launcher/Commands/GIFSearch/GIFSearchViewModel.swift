import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated enum GIFExportAction { case copy, save }
enum GIFSearchActionID {
    static let search = CommandActionID(rawValue: "gif-search.search")
    static let trending = CommandActionID(rawValue: "gif-search.trending")
    static let save = CommandActionID(rawValue: "gif-search.save")
    static let source = CommandActionID(rawValue: "gif-search.source")
    static let connection = CommandActionID(rawValue: "gif-search.connection")
    static let pause = CommandActionID(rawValue: "gif-search.pause")
}

@MainActor @Observable
final class GIFSearchViewModel: LauncherApplicationModel {
    var query = "" { didSet { if oldValue != query { invalidateResults() } } }
    var rating: GIFContentRating = .pg { didSet { if oldValue != rating { invalidateResults() } } }
    var selectedID: String? { didSet { if oldValue != selectedID { loadPreview() } } }
    var apiKeyInput = ""
    var showsConnection = false
    var showsActionsMenu = false
    var isPlaying = true
    private(set) var reducesMotion = false
    private(set) var connection: GIFConnectionState?
    private(set) var items: [GIFCatalogItem] = []
    private(set) var animation: GIFDecodedAnimation?
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var isLoadingPreview = false
    private(set) var isExporting = false
    private(set) var isChangingConnection = false
    private(set) var errorMessage: String?
    private(set) var previewError: String?
    private(set) var statusMessage: String?
    private(set) var nextOffset: Int?
    private(set) var currentOffset = 0
    private(set) var focusRequest = 0
    let fixtureLabel: String?
    @ObservationIgnored private let services: GIFSearchApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var selectionGeneration = UUID()
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored private var submittedQuery: GIFCatalogQuery?
    @ObservationIgnored private var priorOffsets: [Int] = []
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var searchWork: Task<Void, Never>?
    @ObservationIgnored private var previewWork: Task<Void, Never>?
    @ObservationIgnored private var exportWork: Task<Void, Never>?
    @ObservationIgnored private var connectionWork: Task<Void, Never>?
    init(services: GIFSearchApplicationServices, onGoBack: @escaping () -> Void) {
        self.services = services; self.onGoBack = onGoBack; fixtureLabel = services.fixtureLabel
    }
    deinit { loading?.cancel(); searchWork?.cancel(); previewWork?.cancel(); exportWork?.cancel(); connectionWork?.cancel() }
    var selected: GIFCatalogItem? { items.first { $0.id == selectedID } }
    var canSearch: Bool { active && connection?.isConfigured == true && !isLoading && !isChangingConnection && !isSearching && !showsConnection }
    var canExport: Bool { selected?.originalURL != nil && !isSearching && !isExporting && !isChangingConnection && !showsConnection }
    var canGoPrevious: Bool { !priorOffsets.isEmpty && !isSearching }
    var canGoNext: Bool { nextOffset != nil && !isSearching }
    var canTogglePreviewPlayback: Bool { animation != nil && !reducesMotion }
    static func resultAccessibilityLabel(for item: GIFCatalogItem) -> String {
        var components = [item.title]
        if let creator = item.creator { components.append("By " + creator) }
        else if let source = item.sourceName { components.append("Source: " + source) }
        if item.accessibilityText.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(item.title.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
            components.append(item.accessibilityText)
        }
        return components.joined(separator: ". ")
    }
    var footerActions: [CommandActionDescriptor] {
        let primary = selected == nil
            ? CommandActionDescriptor(id: GIFSearchActionID.search, title: isSearching ? "Searching…" : "Search GIPHY", isPrimary: true, keyHint: .return, isEnabled: canSearch && !query.isEmpty)
            : CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: isExporting ? "Preparing GIF…" : "Copy Animated GIF", isPrimary: true, keyHint: .return, isEnabled: canExport)
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: GIFSearchActionID.search, title: "Search GIPHY", isEnabled: canSearch && !query.isEmpty),
         .init(id: GIFSearchActionID.trending, title: "Load Trending GIFs", isEnabled: canSearch),
         .init(id: BuiltInCommandActionID.copy, title: "Copy Animated GIF", isEnabled: canExport),
         .init(id: GIFSearchActionID.save, title: "Save Animated GIF…", isEnabled: canExport),
         .init(id: GIFSearchActionID.pause, title: reducesMotion ? "Still Preview" : isPlaying ? "Pause Preview" : "Play Preview", isEnabled: canTogglePreviewPlayback),
         .init(id: GIFSearchActionID.source, title: "Open on GIPHY", isEnabled: selected?.pageURL != nil),
         .init(id: GIFSearchActionID.connection, title: "GIPHY Connection…")]
    }
    func load() {
        guard !active else { return }; active = true; refreshConnection()
    }
    func refreshConnection() {
        guard active, !isChangingConnection else { return }
        loading?.cancel(); isLoading = true; connectionGeneration = UUID()
        let id = connectionGeneration; let retiringChange = connectionWork
        loading = Task { [weak self, catalog = services.catalog] in
            do {
                // A stopped session may still have an authorized Keychain mutation finishing.
                // Reload only after that operation settles; its old UI completion is invalidated.
                await retiringChange?.value
                try Task.checkCancellation()
                let value = try await catalog.connection(); try Task.checkCancellation()
                guard let self, self.active, self.connectionGeneration == id else { return }
                if self.connection?.revision != value.revision { self.invalidateResults() }
                self.connection = value; self.isLoading = false; self.focusRequest += 1
            } catch {
                guard let self, self.active, !Task.isCancelled, self.connectionGeneration == id else { return }
                self.isLoading = false; self.errorMessage = Self.message(error)
            }
        }
    }
    func submitFromKeyboard() {
        // Query and rating edits synchronously discard selection, including Trending results.
        if selected != nil { export(.copy) }
        else { submitSearch() }
    }
    func setReduceMotion(_ value: Bool) {
        reducesMotion = value
        if value { isPlaying = false }
    }
    func togglePreviewPlayback() { guard canTogglePreviewPlayback else { return }; isPlaying.toggle() }
    func submitSearch() {
        guard canSearch else { return }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = GIFSearchError.invalidRequest.errorDescription; return }
        guard query.count <= 50, query.utf8.count <= 400 else { errorMessage = GIFSearchError.queryTooLong.errorDescription; return }
        priorOffsets = []; search(.search(query), offset: 0)
    }
    func loadTrending() { guard canSearch else { return }; priorOffsets = []; search(.trending, offset: 0) }
    func nextPage() {
        guard canGoNext, let offset = nextOffset, let submittedQuery else { return }
        priorOffsets.append(currentOffset); search(submittedQuery, offset: offset)
    }
    func previousPage() {
        guard canGoPrevious, let submittedQuery, let offset = priorOffsets.popLast() else { return }
        search(submittedQuery, offset: offset)
    }
    private func search(_ query: GIFCatalogQuery, offset: Int) {
        guard let revision = connection?.revision, connection?.isConfigured == true else { return }
        invalidateResults(resetPagination: false); submittedQuery = query; isSearching = true
        let id = generation; let rating = rating
        searchWork = Task { [weak self, catalog = services.catalog] in
            do {
                let page = try await catalog.search(query, rating: rating, offset: offset, connection: revision); try Task.checkCancellation()
                guard let self, self.active, self.generation == id, self.connection?.revision == revision else { return }
                self.items = page.items; self.currentOffset = offset; self.nextOffset = page.nextOffset; self.isSearching = false
                self.selectedID = page.items.first?.id
                if page.items.isEmpty { self.statusMessage = "No GIFs found. Try another phrase." }
            } catch {
                guard let self, self.active, !Task.isCancelled, self.generation == id else { return }
                self.isSearching = false; self.errorMessage = Self.message(error)
            }
        }
    }
    private func invalidateResults(resetPagination: Bool = true) {
        generation = UUID(); searchWork?.cancel(); searchWork = nil; isSearching = false
        invalidateMedia(); items = []; selectedID = nil; nextOffset = nil; errorMessage = nil; statusMessage = nil
        if resetPagination { currentOffset = 0; priorOffsets = []; submittedQuery = nil }
    }
    private func invalidateMedia() {
        selectionGeneration = UUID(); previewWork?.cancel(); previewWork = nil; exportWork?.cancel(); exportWork = nil
        animation = nil; isLoadingPreview = false; isExporting = false; previewError = nil
    }
    func loadPreview() {
        invalidateMedia()
        guard active, let item = selected, let revision = connection?.revision else { return }
        guard item.previewURL != nil else { previewError = GIFSearchError.unsafeURL.errorDescription; return }
        isLoadingPreview = true; let token = selectionGeneration
        previewWork = Task { [weak self, services] in
            do {
                let bytes = try await services.catalog.media(item, original: false, connection: revision)
                try Task.checkCancellation()
                let result = try await services.decoder.preview(bytes); try Task.checkCancellation()
                guard let self, self.active, self.selectionGeneration == token, self.connection?.revision == revision else { return }
                self.animation = result; self.isLoadingPreview = false; self.isPlaying = !self.reducesMotion
            } catch {
                guard let self, self.active, !Task.isCancelled, self.selectionGeneration == token else { return }
                self.isLoadingPreview = false; self.previewError = Self.message(error)
            }
        }
    }
    func export(_ action: GIFExportAction) {
        guard canExport, let item = selected, let revision = connection?.revision else { return }
        isExporting = true; errorMessage = nil; statusMessage = nil; let token = selectionGeneration
        exportWork = Task { [weak self, services] in
            do {
                // Original animation is downloaded only for this explicit copy/save, not retained as a cache.
                let bytes = try await services.catalog.media(item, original: true, connection: revision); try Task.checkCancellation()
                guard self?.active == true, self?.selectionGeneration == token, self?.connection?.revision == revision else { return }
                let saved: Bool
                switch action {
                case .copy: try await services.exporter.copy(bytes); saved = true
                case .save: saved = try await services.exporter.save(bytes, suggestedName: "Commandly GIF.gif")
                }
                guard let self, self.active, self.selectionGeneration == token, !Task.isCancelled else { return }
                self.isExporting = false
                self.statusMessage = !saved ? "Save cancelled." : action == .copy ? "Animated GIF copied. Paste into an app that supports GIFs." : "Animated GIF saved."
            } catch {
                guard let self, self.active, !Task.isCancelled, self.selectionGeneration == token else { return }
                self.isExporting = false; self.errorMessage = Self.message(error)
            }
        }
    }
    func openConnection() {
        showsConnection = true; apiKeyInput = ""; isPlaying = false
        statusMessage = nil; errorMessage = nil
    }
    func closeConnection() { guard !isChangingConnection else { return }; apiKeyInput = ""; showsConnection = false; focusRequest += 1 }
    func saveKey() {
        guard active, !isLoading, !isChangingConnection else { return }
        let key = apiKeyInput; apiKeyInput = ""; changeConnection { try await $0.configure(key: key) }
    }
    func disconnect() { guard active, !isLoading, !isChangingConnection else { return }; apiKeyInput = ""; changeConnection { try await $0.disconnect() } }
    private func changeConnection(_ operation: @escaping @Sendable (any GIFCatalogServing) async throws -> GIFConnectionState) {
        invalidateResults(); loading?.cancel(); connectionGeneration = UUID(); isChangingConnection = true
        connection = nil; let id = connectionGeneration
        connectionWork = Task { [weak self, catalog = services.catalog] in
            do {
                let state = try await operation(catalog)
                guard let self, self.active, self.connectionGeneration == id, !Task.isCancelled else { return }
                self.connection = state; self.isChangingConnection = false; self.isLoading = false
                if self.fixtureLabel != nil {
                    self.statusMessage = state.isConfigured
                        ? "Generated connection enabled. No key was saved or sent."
                        : "Generated connection disabled. No saved key was changed."
                } else {
                    self.statusMessage = state.isConfigured ? "API key saved to Keychain. Submit a search to use GIPHY." : "GIPHY disconnected. API key removed."
                }
            } catch {
                guard let self, self.active, self.connectionGeneration == id, !Task.isCancelled else { return }
                self.isChangingConnection = false; self.isLoading = false; self.errorMessage = Self.message(error)
            }
        }
    }
    func openGIPHYPage() { if let url = selected?.pageURL, GIPHYURLPolicy.page(url) { services.openURL(url) } }
    func openCreatorSource() { if let url = selected?.sourceURL, GIPHYURLPolicy.externalSource(url) { services.openURL(url) } }
    func openProviderSetup() { openFixed("https://developers.giphy.com/dashboard/") }
    func openProviderTerms() { openFixed("https://support.giphy.com/hc/en-us/articles/360028134111-GIPHY-API-Terms-of-Service") }
    private func openFixed(_ text: String) { if let url = URL(string: text) { services.openURL(url) } }
    func moveSelection(offset: Int) {
        guard !items.isEmpty else { return }; let index = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case GIFSearchActionID.search: submitSearch()
        case GIFSearchActionID.trending: loadTrending()
        case BuiltInCommandActionID.copy: export(.copy)
        case GIFSearchActionID.save: export(.save)
        case GIFSearchActionID.source: openGIPHYPage()
        case GIFSearchActionID.connection: openConnection()
        case GIFSearchActionID.pause: togglePreviewPlayback()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if showsConnection { closeConnection(); return true }
        if isSearching { invalidateResults(); return true }
        if isExporting || isLoadingPreview { invalidateMedia(); return true }
        return false
    }
    func goBack() { if handleEscape() { return }; stop(); onGoBack() }
    func stop() {
        active = false; invalidateResults(); loading?.cancel(); connectionWork?.cancel(); connectionGeneration = UUID()
        apiKeyInput = ""; connection = nil; isLoading = false; isChangingConnection = false
        showsConnection = false; showsActionsMenu = false
    }
    private static func message(_ error: any Error) -> String { (error as? GIFSearchError)?.errorDescription ?? GIFSearchError.unavailable.errorDescription ?? "GIF search is unavailable." }
    func waitForLoadForTesting() async { await loading?.value }
    func waitForSearchForTesting() async { await searchWork?.value; await previewWork?.value }
    func waitForPreviewForTesting() async { await previewWork?.value }
    func waitForExportForTesting() async { await exportWork?.value }
    func waitForConnectionForTesting() async { await connectionWork?.value }
    var pendingSearchForTesting: Task<Void, Never>? { searchWork }
    var pendingPreviewForTesting: Task<Void, Never>? { previewWork }
    var pendingExportForTesting: Task<Void, Never>? { exportWork }
}
