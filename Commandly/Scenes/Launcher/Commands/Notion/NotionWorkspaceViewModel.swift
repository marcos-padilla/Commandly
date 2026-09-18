import CommandKit
import Foundation
import Infrastructure
import Observation

@MainActor @Observable final class NotionWorkspaceViewModel: LauncherApplicationModel {
    @ObservationIgnored private let services: NotionWorkspaceApplicationServices
    @ObservationIgnored let onGoBack: () -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private var active = false
    private(set) var connection: NotionWorkspaceConnection?
    private(set) var items: [NotionWorkspaceItem] = []
    private(set) var route: [NotionWorkspaceItem] = []
    private(set) var cursor: String?
    private(set) var busy = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private var submittedQuery = ""
    var query = ""
    var selectedID: UUID?
    var token = ""
    var showsConnection = false
    var showsActionsMenu = false
    var selected: NotionWorkspaceItem? { items.first { $0.id == selectedID } }
    var title: String { route.last?.title ?? connection?.name ?? "Notion Workspace" }
    var footerActions: [CommandActionDescriptor] {
        [.init(id: .init(rawValue: "notion.open"), title: selected?.hasChildren == true ? "Browse Selection" : "Copy Text", isPrimary: true, keyHint: .return, isEnabled: selected != nil && !busy),
         .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: .init(rawValue: "notion.search"), title: "Search Workspace", isEnabled: connection != nil && !busy),
         .init(id: .init(rawValue: "notion.open"), title: "Browse Selection", isEnabled: selected?.hasChildren == true && !busy),
         .init(id: .init(rawValue: "notion.web"), title: "Open in Notion", isEnabled: selected != nil && !busy),
         .init(id: .init(rawValue: "notion.copy"), title: "Copy Text", isEnabled: selected != nil && !busy),
         .init(id: .init(rawValue: "notion.connection"), title: "Workspace Connection…")]
    }
    init(services: NotionWorkspaceApplicationServices, onGoBack: @escaping () -> Void) { self.services = services; self.onGoBack = onGoBack }
    deinit { task?.cancel() }
    func start() { guard !active else { return }; active = true; reloadConnection() }
    func reloadConnection() {
        run { model in
            let value = try await model.services.service.connection()
            try Task.checkCancellation()
            if model.connection != value { model.clearContent() }
            model.connection = value
        }
    }
    func connect() {
        guard !token.isEmpty else { return }
        let input = token; token = ""
        run { model in
            _ = try await model.services.service.connect(token: input)
            let value = try await model.services.service.connection()
            try Task.checkCancellation()
            model.clearContent(); model.connection = value; model.showsConnection = false
            model.statusMessage = "Workspace connected. Search to load pages shared with this integration."
        }
    }
    func disconnect() {
        run { model in
            try await model.services.service.disconnect(); try Task.checkCancellation()
            model.clearContent(); model.connection = nil; model.statusMessage = "Local connection removed."
        }
    }
    func search() {
        guard !busy else { return }
        guard connection != nil else { showsConnection = true; return }
        route = []; submittedQuery = query; items = []; selectedID = nil; cursor = nil
        loadPage(append: false)
    }
    func loadMore() { guard cursor != nil, items.count < 1000 else { return }; loadPage(append: true) }
    private func loadPage(append: Bool) {
        guard !busy, let connection else { return }
        let target = route.last; let next = append ? cursor : nil; let search = submittedQuery
        run { model in
            let result: NotionWorkspacePage
            if let target { result = try await model.services.service.children(of: target, cursor: next, connection: connection) }
            else { result = try await model.services.service.search(search, cursor: next, connection: connection) }
            try Task.checkCancellation()
            var seen = Set(append ? model.items.map(\.id) : [])
            let additions = result.items.filter { seen.insert($0.id).inserted }
            model.items = append ? model.items + additions : additions
            model.cursor = result.nextCursor
            model.selectedID = model.items.contains(where: { $0.id == model.selectedID }) ? model.selectedID : model.items.first?.id
            if model.items.count >= 1000 && model.cursor != nil { model.statusMessage = "Showing 1,000 items. Narrow your search or open the database in Notion." }
        }
    }
    func browseSelection() {
        guard !busy, let selected else { return }
        guard selected.hasChildren else { copySelection(); return }
        guard route.count < 32 else { errorMessage = "Open this deeply nested page in Notion to continue."; return }
        route.append(selected); items = []; selectedID = nil; cursor = nil; loadPage(append: false)
    }
    func back() {
        if busy { cancel(); return }
        if !route.isEmpty { route.removeLast(); items = []; selectedID = nil; cursor = nil; loadPage(append: false) }
        else { onGoBack() }
    }
    func openSelection() { if let url = selected?.webURL { services.open(url) } }
    func copySelection() {
        guard !busy, let selected else { return }
        statusMessage = services.copy(selected.text.isEmpty ? selected.title : selected.text) ? "Text copied." : "Could not copy text."
    }
    func showConnection() { token = ""; showsConnection = true }
    func closeConnection() {
        token = ""; showsConnection = false
        if busy { cancel(); reloadConnection() }
    }
    func openSetup() { if let url = URL(string: "https://www.notion.so/profile/integrations") { services.open(url) } }
    func moveSelection(offset: Int) { selectedID = LauncherListSelection.nextID(in: items, selectedID: selectedID, offset: offset, id: \.id) }
    func perform(_ actionID: CommandActionID) {
        switch actionID.rawValue {
        case "notion.open": browseSelection()
        case "notion.web": openSelection()
        case "notion.copy": copySelection()
        case "notion.search": search()
        case "notion.connection": showConnection()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if showsConnection { closeConnection(); return true }
        if busy { cancel(); return true }
        if !route.isEmpty { back(); return true }
        return false
    }
    func stop() { active = false; cancel(); token = ""; clearContent(); connection = nil }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    private func clearContent() { items = []; route = []; selectedID = nil; cursor = nil; query = ""; submittedQuery = "" }
    private func run(_ operation: @escaping @MainActor (NotionWorkspaceViewModel) async throws -> Void) {
        guard active, !busy else { return }
        let id = UUID(); generation = id; busy = true; errorMessage = nil; statusMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do { try await operation(self) }
            catch { if self.active, self.generation == id, !Task.isCancelled { self.errorMessage = (error as? NotionWorkspaceError ?? .unavailable).localizedDescription } }
            if self.generation == id { self.busy = false }
        }
    }
    func waitForWorkForTesting() async { await task?.value }
}
