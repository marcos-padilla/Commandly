import CommandKit
import Infrastructure
import Observation

nonisolated enum SystemSettingsActionID {
    static let openSelected = CommandActionID(rawValue: "system-settings.open-selected")
    static let openApplication = CommandActionID(rawValue: "system-settings.open-application")
    static let cancel = CommandActionID(rawValue: "system-settings.cancel")
}

@Observable @MainActor final class SystemSettingsViewModel: LauncherApplicationModel {
    private let opener: any SystemSettingsOpening
    private let isEnabled: Bool
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onOpened: () -> Void
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            cancelOperation()
            selectedID = LauncherListSelection.resolvedID(in: items, selectedID: selectedID, id: \.id)
            statusMessage = nil
        }
    }
    private(set) var selectedID: String?
    private(set) var isOpening = false
    private(set) var statusMessage: String?
    private(set) var searchFocusRequest = 0
    var showsActionsMenu = false

    init(opener: any SystemSettingsOpening, isEnabled: Bool = true, initialItemID: String? = nil,
         onGoBack: @escaping () -> Void, onOpened: @escaping () -> Void) {
        self.opener = opener; self.isEnabled = isEnabled; self.onGoBack = onGoBack; self.onOpened = onOpened
        selectedID = SystemSettingsCatalog.items.first { $0.id == initialItemID }?.id ?? SystemSettingsCatalog.items.first?.id
    }
    deinit { operation?.cancel() }
    var items: [SystemSettingsCatalogItem] { SystemSettingsCatalog.matching(query) }
    var selectedItem: SystemSettingsCatalogItem? { items.first { $0.id == selectedID } ?? items.first }
    var canOpen: Bool { isEnabled && !isOpening && selectedItem != nil }
    var footerActions: [CommandActionDescriptor] {
        [.init(id: SystemSettingsActionID.openSelected, title: "Open in System Settings", isPrimary: true, keyHint: .return, isEnabled: canOpen),
         .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: SystemSettingsActionID.openSelected, title: "Open Selected Settings", isEnabled: canOpen),
         .init(id: SystemSettingsActionID.openApplication, title: "Open System Settings", isEnabled: isEnabled && !isOpening),
         .init(id: SystemSettingsActionID.cancel, title: "Cancel Pending Navigation", isEnabled: isOpening)]
    }
    func requestSearchFocus() { searchFocusRequest += 1 }
    func select(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        cancelOperation(); selectedID = id; statusMessage = nil
    }
    func moveSelection(offset: Int) {
        if let id = LauncherListSelection.nextID(in: items, selectedID: selectedID, offset: offset, id: \.id) { select(id) }
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case SystemSettingsActionID.openSelected: openSelected()
        case SystemSettingsActionID.openApplication: open(nil)
        case SystemSettingsActionID.cancel: cancelOperation()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack: onGoBack()
        default: break
        }
    }
    func openSelected() {
        guard canOpen, let item = selectedItem else { return }
        open(item.pane)
    }
    private func open(_ pane: SystemSettingsPane?) {
        guard isEnabled, !isOpening else { return }
        generation &+= 1
        let id = generation
        isOpening = true; statusMessage = nil; showsActionsMenu = false
        operation = Task { [weak self, opener] in
            do {
                try Task.checkCancellation()
                let result = try await opener.open(pane)
                try Task.checkCancellation()
                guard let self, generation == id else { return }
                isOpening = false
                statusMessage = SystemSettingsNavigationFeedback.message(result)
                switch result {
                case .requestedPane, .openedApplication(fallbackFor: nil): onOpened()
                case .openedApplication: break // Keep visible guidance for the app-only fallback.
                }
            } catch {
                guard let self, generation == id else { return }
                isOpening = false
                if error is CancellationError { return }
                statusMessage = (error as? SystemSettingsNavigationError ?? .navigationFailed).message
            }
        }
    }
    func handleEscape() -> Bool {
        if isOpening { cancelOperation(); return true }
        if !query.isEmpty { query = ""; return true }
        return false
    }
    func goBack() { onGoBack() }
    func stop() { cancelOperation() }
    private func cancelOperation() {
        generation &+= 1
        operation?.cancel(); operation = nil; isOpening = false
    }
    func pendingOperationForTesting() -> Task<Void, Never>? { operation }
    func flushForTesting() async { await operation?.value }
}
