import CommandKit
import Foundation
import Infrastructure
import Observation

enum FileBrowserActionID {
    static let open = CommandActionID(rawValue: "file-browser.open")
    static let up = CommandActionID(rawValue: "file-browser.up")
    static let refresh = CommandActionID(rawValue: "file-browser.refresh")
    static let permissions = CommandActionID(rawValue: "file-browser.permissions")
}

enum FileBrowserRow: Identifiable, Equatable {
    case root(FileBrowserRoot)
    case entry(FileBrowserEntry)
    var id: FileBrowserLocation {
        switch self { case .root(let root): FileBrowserLocation(rootID: root.id); case .entry(let entry): entry.location }
    }
    var title: String { switch self { case .root(let root): root.name; case .entry(let entry): entry.name } }
    var kindTitle: String {
        switch self {
        case .root: "Authorized folder"
        case .entry(let entry):
            switch entry.kind { case .folder: "Folder"; case .file: "File"; case .package: "Package";
            case .symbolicLink: "Symbolic link · unavailable"; case .alias: "Alias · unavailable" }
        }
    }
    var isActionable: Bool { switch self { case .root: true; case .entry(let entry): entry.isActionable } }
    var isFolder: Bool { switch self { case .root: true; case .entry(let entry): entry.kind == .folder } }
}

@MainActor
@Observable
final class FileBrowserViewModel: LauncherApplicationModel {
    enum Phase: Equatable { case loading, ready, needsAccess, failed }
    private(set) var phase: Phase = .loading
    private(set) var roots: [FileBrowserRoot] = []
    private(set) var snapshot: FileBrowserSnapshot?
    private(set) var location: FileBrowserLocation?
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var isOpening = false
    private(set) var searchFocusRequest = 0
    var query = "" { didSet { if oldValue != query { cancelOpen(); resolveSelection() } } }
    var selectedID: FileBrowserLocation?
    var showsActionsMenu = false
    @ObservationIgnored private let browser: any FileBrowsing
    @ObservationIgnored private let opener: any URLOpening
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onOpenPermissions: () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var openID: UUID?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isStopped = false

    init(browser: any FileBrowsing, opener: any URLOpening, onGoBack: @escaping () -> Void,
         onOpenPermissions: @escaping () -> Void) {
        self.browser = browser; self.opener = opener; self.onGoBack = onGoBack
        self.onOpenPermissions = onOpenPermissions
    }

    var rows: [FileBrowserRow] {
        guard phase == .ready else { return [] }
        let all = location == nil ? roots.map(FileBrowserRow.root) : (snapshot?.entries ?? []).map(FileBrowserRow.entry)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? all : all.filter { $0.title.localizedStandardContains(needle) }
    }
    var selectedRow: FileBrowserRow? { rows.first { $0.id == selectedID } }
    var locationTitle: String {
        guard let location else { return "Authorized Folders" }
        return location.components.last ?? roots.first(where: { $0.id == location.rootID })?.name ?? "Folder"
    }
    var relativeLocation: String {
        guard let location else { return "Choose a folder to browse" }
        let root = roots.first(where: { $0.id == location.rootID })?.name ?? "Authorized Folder"
        return ([root] + location.components).joined(separator: " › ")
    }
    var footerActions: [CommandActionDescriptor] {
        if phase == .needsAccess {
            return [CommandActionDescriptor(id: FileBrowserActionID.permissions, title: "Choose Authorized Folders", isPrimary: true, keyHint: .return)]
        }
        return [
            CommandActionDescriptor(id: FileBrowserActionID.open, title: selectedRow?.isFolder == true ? "Open Folder" : "Open File",
                                    isPrimary: true, keyHint: .return, isEnabled: selectedRow?.isActionable == true && isOpening == false),
            CommandActionDescriptor(id: FileBrowserActionID.up, title: "Parent Folder",
                                    keyHint: CommandKeyHint(symbols: ["⌘", "↑"]), isEnabled: location != nil),
            CommandActionDescriptor(id: FileBrowserActionID.refresh, title: "Refresh", keyHint: CommandKeyHint(symbols: ["⌘", "R"]))
        ]
    }
    var menuActions: [CommandActionDescriptor] { [] }

    func start() {
        guard hasStarted == false, isStopped == false else { return }
        hasStarted = true
        refresh()
    }

    func refresh() { load(location) }
    func showRoots() { load(nil) }
    func select(_ id: FileBrowserLocation) { cancelOpen(); selectedID = id; statusMessage = nil }
    func moveSelection(offset: Int) {
        cancelOpen()
        selectedID = LauncherListSelection.nextID(in: rows, selectedID: selectedID, offset: offset, id: \.id)
    }

    func performPrimary() {
        guard isStopped == false else { return }
        if phase == .needsAccess { openPermissions(); return }
        guard isOpening == false, let row = selectedRow else { return }
        switch row {
        case .root(let root): load(FileBrowserLocation(rootID: root.id))
        case .entry(let entry):
            if entry.kind == .folder { load(entry.location) }
            else if entry.isActionable { open(entry) }
            else { statusMessage = "Links and aliases stay closed to keep browsing inside your authorized folders." }
        }
    }

    func goUp() {
        guard let location else { return }
        let previous = location
        load(location.parent, selectionAfterLoading: previous)
    }

    func handleEscape() -> Bool {
        cancelOpen()
        if query.isEmpty == false { query = ""; return true }
        if location != nil { goUp(); return true }
        return false
    }
    func goBack() { stop(); onGoBack() }
    func openPermissions() { cancelOpen(); onOpenPermissions() }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case FileBrowserActionID.open: performPrimary()
        case FileBrowserActionID.up: goUp()
        case FileBrowserActionID.refresh: refresh()
        case FileBrowserActionID.permissions: openPermissions()
        default: break
        }
    }

    func stop() {
        isStopped = true
        loadID = UUID()
        loadTask?.cancel()
        cancelOpen()
        roots = []; snapshot = nil; selectedID = nil; location = nil; query = ""
        statusMessage = nil; errorMessage = nil; showsActionsMenu = false
    }

    func waitForLoadingForTesting() async { await loadTask?.value }
    func waitForOpeningForTesting() async { await openTask?.value }

    private func load(_ target: FileBrowserLocation?, selectionAfterLoading: FileBrowserLocation? = nil) {
        guard isStopped == false else { return }
        loadTask?.cancel()
        cancelOpen()
        loadID = UUID()
        let requestID = loadID
        location = target
        snapshot = nil; selectedID = nil; query = ""; errorMessage = nil; statusMessage = nil
        phase = .loading
        searchFocusRequest += 1
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let currentRoots = try await browser.roots()
                let result: FileBrowserSnapshot?
                if let target { result = try await browser.list(target) } else { result = nil }
                guard Task.isCancelled == false, loadID == requestID, isStopped == false else { return }
                roots = currentRoots; snapshot = result; phase = .ready
                selectedID = selectionAfterLoading
                resolveSelection()
            } catch is CancellationError { return }
            catch {
                guard Task.isCancelled == false, loadID == requestID, isStopped == false else { return }
                phase = (error as? FileBrowserError) == .noAuthorizedFolders ? .needsAccess : .failed
                errorMessage = message(for: error)
            }
        }
    }

    private func open(_ entry: FileBrowserEntry) {
        let requestID = UUID()
        openID = requestID
        isOpening = true
        statusMessage = nil
        openTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if openID == requestID { isOpening = false; openID = nil } }
            do {
                try await browser.open(entry, using: opener)
                guard Task.isCancelled == false, openID == requestID, isStopped == false else { return }
                statusMessage = "Opened."
            } catch is CancellationError { return }
            catch {
                guard Task.isCancelled == false, openID == requestID, isStopped == false else { return }
                statusMessage = message(for: error)
            }
        }
    }
    private func cancelOpen() { openTask?.cancel(); openID = nil; isOpening = false }
    private func resolveSelection() {
        selectedID = LauncherListSelection.resolvedID(in: rows, selectedID: selectedID, id: \.id)
    }
    private func message(for error: any Error) -> String {
        switch error as? FileBrowserError {
        case .noAuthorizedFolders: "Choose the folders Commandly may browse in Settings → Permissions."
        case .authorizationUnavailable: "These folder grants are unavailable or expired. Reconnect the volume or choose folders again in Permissions."
        case .accessDenied: "Access to this folder has changed. Choose authorized folders in Permissions."
        case .folderUnavailable: "This folder is missing or unavailable. Go up a level or refresh."
        case .unsafeLocation: "This location cannot be browsed. Links and paths outside an authorized folder stay closed."
        case .itemChanged: "This item changed or moved. Refresh the folder and select it again."
        case .unsupportedItem: "This item cannot be opened safely from File Browser."
        case .openFailed: "macOS couldn’t open this file."
        case nil: "This folder couldn’t be loaded. Try refreshing."
        }
    }
}
