import CommandKit
import Foundation
import Infrastructure
import Observation

enum SlackEmojiActionID {
    static let refresh = CommandActionID(rawValue: "slack-emoji.refresh")
    static let copyImage = CommandActionID(rawValue: "slack-emoji.copy-image")
    static let save = CommandActionID(rawValue: "slack-emoji.save")
    static let connections = CommandActionID(rawValue: "slack-emoji.connections")
    static let playback = CommandActionID(rawValue: "slack-emoji.playback")
}
@MainActor @Observable
final class SlackEmojiViewModel: LauncherApplicationModel {
    var query = "" { didSet { if query != oldValue { filter() } } }
    var workspaceID: String? { didSet { if workspaceID != oldValue { clearInventory() } } }
    var selectedName: String? { didSet { if selectedName != oldValue { loadPreview() } } }
    var tokenInput = ""
    var showsConnections = false
    var showsActionsMenu = false
    private(set) var workspaces: [SlackEmojiWorkspace] = []
    private(set) var catalog: SlackEmojiCatalog?
    private(set) var items: [SlackCustomEmoji] = []
    private(set) var totalMatches = 0
    private(set) var preview: SlackEmojiPreview?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isFiltering = false
    private(set) var isLoadingPreview = false
    private(set) var isExporting = false
    private(set) var isChangingConnection = false
    private(set) var isCancellingConnection = false
    private(set) var isPlaying = true
    private(set) var reducesMotion = false
    private(set) var errorMessage: String?
    private(set) var previewError: String?
    private(set) var statusMessage: String?
    private(set) var focusRequest = 0
    let fixtureLabel: String?
    @ObservationIgnored private let services: SlackEmojiApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var filterGeneration = UUID()
    @ObservationIgnored private var selectionGeneration = UUID()
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored private var loadWork: Task<Void, Never>?
    @ObservationIgnored private var refreshWork: Task<Void, Never>?
    @ObservationIgnored private var filterWork: Task<Void, Never>?
    @ObservationIgnored private var previewWork: Task<Void, Never>?
    @ObservationIgnored private var exportWork: Task<Void, Never>?
    @ObservationIgnored private var connectionWork: Task<Void, Never>?
    @ObservationIgnored private var cancellationWork: Task<Void, Never>?
    @ObservationIgnored private var releaseWork: Task<Void, Never>?
    init(services: SlackEmojiApplicationServices, onGoBack: @escaping () -> Void) { self.services = services; self.onGoBack = onGoBack; fixtureLabel = services.fixtureLabel }
    deinit { loadWork?.cancel(); refreshWork?.cancel(); filterWork?.cancel(); previewWork?.cancel(); exportWork?.cancel(); connectionWork?.cancel(); cancellationWork?.cancel() }
    var workspace: SlackEmojiWorkspace? { workspaces.first { $0.id == workspaceID } }
    var selected: SlackCustomEmoji? { items.first { $0.name == selectedName } }
    var canRefresh: Bool { active && workspace != nil && !isLoading && !isChangingConnection && !isRefreshing && !showsConnections }
    var canCopyName: Bool { active && selected != nil && !isExporting && !showsConnections && !isChangingConnection }
    var canExportImage: Bool { canCopyName && selected?.resolution.imageURL != nil }
    var canTogglePlayback: Bool { preview?.animation != nil && !reducesMotion }
    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if selected != nil { primary = .init(id: BuiltInCommandActionID.copy, title: "Copy Slack Name", isPrimary: true, keyHint: .return, isEnabled: canCopyName) }
        else if catalog == nil { primary = .init(id: SlackEmojiActionID.refresh, title: isRefreshing ? "Refreshing…" : "Refresh Emoji", isPrimary: true, keyHint: .return, isEnabled: canRefresh) }
        else { primary = .init(id: BuiltInCommandActionID.copy, title: isFiltering ? "Searching Names…" : "No Matching Emoji", isPrimary: true, keyHint: .return, isEnabled: false) }
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: SlackEmojiActionID.refresh, title: "Refresh Workspace Emoji", isEnabled: canRefresh),
         .init(id: BuiltInCommandActionID.copy, title: "Copy Slack Name", isEnabled: canCopyName),
         .init(id: SlackEmojiActionID.copyImage, title: "Copy Original Image", isEnabled: canExportImage),
         .init(id: SlackEmojiActionID.save, title: "Save Original Image…", isEnabled: canExportImage),
         .init(id: SlackEmojiActionID.playback, title: reducesMotion ? "Still Preview" : isPlaying ? "Pause Preview" : "Play Preview", isEnabled: canTogglePlayback),
         .init(id: SlackEmojiActionID.connections, title: "Workspaces…")]
    }
    func load() { guard !active else { return }; active = true; loadConnections() }
    func loadConnections() {
        guard active, !isChangingConnection else { return }
        loadWork?.cancel(); connectionGeneration = UUID(); let id = connectionGeneration; let retiring = connectionWork
        isLoading = true; errorMessage = nil
        loadWork = Task { [weak self, service = services.service] in
            do {
                await retiring?.value; try Task.checkCancellation()
                let values = try await service.connections(); try Task.checkCancellation()
                guard let self, self.active, self.connectionGeneration == id else { return }
                let previous = self.workspace; self.workspaces = values
                if !values.contains(where: { $0.id == self.workspaceID }) { self.workspaceID = values.first?.id }
                if previous != self.workspace { self.clearInventory() }
                self.isLoading = false; self.focusRequest += 1
            } catch { guard let self, self.active, self.connectionGeneration == id, !Task.isCancelled else { return }; self.isLoading = false; self.errorMessage = Self.message(error) }
        }
    }
    func refresh() {
        guard canRefresh, let workspace else { return }; clearInventory(); isRefreshing = true; let id = generation
        refreshWork = Task { [weak self, service = services.service] in
            do {
                let value = try await service.refresh(workspace)
                guard let self, self.active, self.generation == id, self.workspace == workspace, !Task.isCancelled else { await service.release(value); return }
                self.catalog = value; self.isRefreshing = false; self.filter()
            } catch { guard let self, self.active, self.generation == id, !Task.isCancelled else { return }; self.isRefreshing = false; self.errorMessage = Self.message(error) }
        }
    }
    private func filter() {
        filterGeneration = UUID(); filterWork?.cancel(); clearMedia(); items = []; selectedName = nil; totalMatches = 0
        isFiltering = false; statusMessage = nil
        guard active, let catalog else { return }; isFiltering = true; let id = filterGeneration; let query = query
        filterWork = Task { [weak self, service = services.service] in
            do {
                let matches = try await service.search(query, catalog: catalog); try Task.checkCancellation()
                guard let self, self.active, self.catalog == catalog, self.filterGeneration == id else { return }
                self.items = matches.items; self.totalMatches = matches.total; self.isFiltering = false; self.selectedName = matches.items.first?.name
            } catch { guard let self, self.active, self.filterGeneration == id, !Task.isCancelled else { return }; self.isFiltering = false; self.errorMessage = Self.message(error) }
        }
    }
    func loadPreview() {
        clearMedia()
        guard active, let selected, selected.resolution.imageURL != nil, let catalog else { return }
        isLoadingPreview = true; let id = selectionGeneration
        previewWork = Task { [weak self, services] in
            do {
                let bytes = try await services.service.media(selected, catalog: catalog); try Task.checkCancellation()
                let value = try await services.decoder.preview(bytes); try Task.checkCancellation()
                guard let self, self.active, self.selectionGeneration == id, self.catalog == catalog else { return }
                self.preview = value; self.isLoadingPreview = false; self.isPlaying = !self.reducesMotion
            } catch { guard let self, self.active, self.selectionGeneration == id, !Task.isCancelled else { return }; self.isLoadingPreview = false; self.previewError = Self.message(error) }
        }
    }
    func submit() { if selected != nil { copyName() } else if catalog == nil, !isFiltering { refresh() } }
    func copyName() {
        guard canCopyName, let selected else { return }; isExporting = true; errorMessage = nil; statusMessage = nil; let id = selectionGeneration
        exportWork = Task { [weak self, exporter = services.exporter] in
            do {
                guard self?.active == true, self?.selectionGeneration == id else { return }
                try await exporter.copyName(selected.name); try Task.checkCancellation()
                guard let self, self.active, self.selectionGeneration == id else { return }
                self.isExporting = false; self.statusMessage = "Slack name copied. Paste it in the connected workspace."
            } catch { guard let self, self.active, self.selectionGeneration == id, !Task.isCancelled else { return }; self.isExporting = false; self.errorMessage = Self.message(error) }
        }
    }
    func exportImage(save: Bool) {
        guard canExportImage, let selected, let catalog else { return }; isExporting = true; errorMessage = nil; statusMessage = nil; let id = selectionGeneration
        exportWork = Task { [weak self, services] in
            do {
                let data = try await services.service.media(selected, catalog: catalog); try Task.checkCancellation()
                guard self?.active == true, self?.selectionGeneration == id, self?.catalog == catalog else { return }
                let completed: Bool
                if save { completed = try await services.exporter.saveImage(data, name: selected.name) }
                else { try await services.exporter.copyImage(data); completed = true }
                guard let self, self.active, self.selectionGeneration == id, !Task.isCancelled else { return }
                self.isExporting = false; self.statusMessage = completed ? (save ? "Original emoji image saved." : "Original emoji image copied. Animation support depends on the receiving app.") : "Save cancelled."
            } catch { guard let self, self.active, self.selectionGeneration == id, !Task.isCancelled else { return }; self.isExporting = false; self.errorMessage = Self.message(error) }
        }
    }
    func connect(replacing: Bool) {
        guard active, !isLoading, !isChangingConnection, !tokenInput.isEmpty, !replacing || workspace != nil else { return }
        let token = tokenInput; let target = replacing ? workspace : nil; tokenInput = ""
        changeConnection { service in _ = try await service.connect(token: token, replacing: target) }
    }
    func disconnect() { guard active, !isLoading, !isChangingConnection, let workspace else { return }; changeConnection { try await $0.disconnect(workspace) } }
    private func changeConnection(_ operation: @escaping @Sendable (any SlackEmojiServing) async throws -> Void) {
        clearInventory(); loadWork?.cancel(); isLoading = false; isChangingConnection = true; connectionGeneration = UUID(); let id = connectionGeneration
        connectionWork = Task { [weak self, service = services.service] in
            do {
                try await operation(service)
                let values = try await service.connections(); try Task.checkCancellation()
                guard let self, self.active, self.connectionGeneration == id else { return }
                self.workspaces = values; if !values.contains(where: { $0.id == self.workspaceID }) { self.workspaceID = values.first?.id }
                self.isChangingConnection = false
                self.statusMessage = self.fixtureLabel == nil ? "Workspace connections updated in Keychain. Choose a workspace and Refresh Emoji." : "Generated workspace connections updated. No token was stored."
            } catch { guard let self, self.active, self.connectionGeneration == id, !Task.isCancelled else { return }; self.isChangingConnection = false; self.errorMessage = Self.message(error) }
        }
    }
    private func clearMedia() {
        selectionGeneration = UUID(); previewWork?.cancel(); exportWork?.cancel(); preview = nil; previewError = nil; isLoadingPreview = false; isExporting = false
    }
    private func clearInventory() {
        generation = UUID(); refreshWork?.cancel(); filterGeneration = UUID(); filterWork?.cancel(); clearMedia()
        if let catalog {
            let previous = releaseWork
            // Retained, ordered cleanup only releases the exact retired catalog, never its replacement.
            releaseWork = Task { [service = services.service] in await previous?.value; await service.release(catalog) }
        }
        catalog = nil; items = []; selectedName = nil; totalMatches = 0; isRefreshing = false; isFiltering = false; errorMessage = nil; statusMessage = nil
    }
    func moveSelection(offset: Int) { guard !items.isEmpty else { return }; let index = items.firstIndex { $0.name == selectedName } ?? 0; selectedName = items[min(max(index + offset, 0), items.count - 1)].name }
    func setReduceMotion(_ value: Bool) { reducesMotion = value; if value { isPlaying = false } }
    func togglePlayback() { guard canTogglePlayback else { return }; isPlaying.toggle() }
    func openConnections() { statusMessage = nil; errorMessage = nil; tokenInput = ""; isPlaying = false; showsConnections = true }
    func closeConnections() {
        if isChangingConnection { cancelConnectionChange(); return }
        tokenInput = ""; showsConnections = false; focusRequest += 1
    }
    private func cancelConnectionChange() {
        guard isChangingConnection, !isCancellingConnection else { return }
        isCancellingConnection = true; tokenInput = ""; connectionGeneration = UUID(); let id = connectionGeneration
        let before = workspaces; let retiring = connectionWork; retiring?.cancel()
        cancellationWork = Task { [weak self] in
            await retiring?.value
            guard let self, self.active, self.connectionGeneration == id, !Task.isCancelled else { return }
            self.isChangingConnection = false; self.isCancellingConnection = false; self.showsConnections = false
            self.loadConnections(); let reloadID = self.connectionGeneration
            await self.loadWork?.value
            guard self.active, self.connectionGeneration == reloadID, !self.isLoading, !Task.isCancelled, self.errorMessage == nil else { return }
            self.statusMessage = self.workspaces == before ? "Connection check cancelled." : "The connection finished before cancellation. Your saved workspace connections are up to date."
        }
    }
    func openSetup() { if let url = URL(string: "https://api.slack.com/apps") { services.openURL(url) } }
    func openTerms() { if let url = URL(string: "https://slack.com/terms-of-service/api") { services.openURL(url) } }
    func perform(_ id: CommandActionID) {
        switch id {
        case SlackEmojiActionID.refresh: refresh()
        case BuiltInCommandActionID.copy: copyName()
        case SlackEmojiActionID.copyImage: exportImage(save: false)
        case SlackEmojiActionID.save: exportImage(save: true)
        case SlackEmojiActionID.connections: openConnections()
        case SlackEmojiActionID.playback: togglePlayback()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if showsConnections { closeConnections(); return true }
        if isRefreshing { clearInventory(); return true }
        if isExporting || isLoadingPreview { clearMedia(); return true }
        return false
    }
    func goBack() { if handleEscape() { return }; stop(); onGoBack() }
    func stop() {
        active = false; clearInventory(); loadWork?.cancel(); connectionWork?.cancel(); cancellationWork?.cancel(); connectionGeneration = UUID()
        tokenInput = ""; workspaces = []; workspaceID = nil; isLoading = false; isChangingConnection = false; isCancellingConnection = false; showsConnections = false; showsActionsMenu = false
    }
    static func message(_ error: any Error) -> String { (error as? SlackEmojiError)?.errorDescription ?? SlackEmojiError.unavailable.errorDescription ?? "Slack emoji is unavailable." }
    static func resolutionDescription(_ item: SlackCustomEmoji) -> String {
        switch item.resolution {
        case .image(_, let canonical, let chain): chain.isEmpty ? "Custom workspace emoji" : "Alias of :" + canonical + ":"
        case .missingAlias: "Alias target was not returned by this workspace. Copy its name to use it in Slack."
        case .aliasCycle: "This alias forms a cycle and cannot be previewed."
        case .aliasTooDeep: "This alias exceeds the safe resolution limit."
        case .unsupportedURL: "The workspace returned an unsupported image address."
        }
    }
    func waitForLoadForTesting() async { await loadWork?.value }
    func waitForRefreshForTesting() async { await refreshWork?.value; await filterWork?.value; await previewWork?.value }
    func waitForFilterForTesting() async { await filterWork?.value; await previewWork?.value }
    func waitForExportForTesting() async { await exportWork?.value }
    func waitForConnectionForTesting() async { await connectionWork?.value }
    func waitForCancellationForTesting() async { await cancellationWork?.value }
    func waitForCleanupForTesting() async { await releaseWork?.value }
    var pendingRefreshForTesting: Task<Void, Never>? { refreshWork }
    var pendingExportForTesting: Task<Void, Never>? { exportWork }
}
