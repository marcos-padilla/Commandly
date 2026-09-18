import CommandKit
import Infrastructure
import Observation

nonisolated enum FinderPathActionID {
    static let copy = CommandActionID(rawValue: "finder-path.copy")
    static let allow = CommandActionID(rawValue: "finder-path.allow-copy")
    static let settings = CommandActionID(rawValue: "finder-path.settings")
    static let cancel = CommandActionID(rawValue: "finder-path.cancel")
}

@MainActor @Observable final class FinderPathViewModel: LauncherApplicationModel {
    @ObservationIgnored private let services: FinderPathApplicationServices
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private var active = false
    private(set) var isWorking = false
    private(set) var needsConsent = false
    private(set) var permissionDenied = false
    private(set) var statusMessage: String?
    var showsActionsMenu = false
    var fixtureLabel: String? { services.fixtureLabel }
    init(services: FinderPathApplicationServices, isEnabled: Bool = true, onGoBack: @escaping () -> Void) {
        self.services = services; self.isEnabled = isEnabled; self.onGoBack = onGoBack
    }
    deinit { task?.cancel() }
    var canCopy: Bool { active && isEnabled && !isWorking }
    var primaryTitle: String { needsConsent ? "Allow Finder Access and Copy" : "Copy Current Finder Path" }
    var footerActions: [CommandActionDescriptor] {
        [.init(id: needsConsent ? FinderPathActionID.allow : FinderPathActionID.copy, title: isWorking ? "Reading Finder…" : primaryTitle,
               isPrimary: true, keyHint: .return, isEnabled: canCopy),
         .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: FinderPathActionID.copy, title: "Copy Current Finder Path", isEnabled: canCopy),
         .init(id: FinderPathActionID.allow, title: "Allow Finder Access and Copy", isEnabled: canCopy && needsConsent),
         .init(id: FinderPathActionID.settings, title: "Open System Settings", isEnabled: active && isEnabled && !isWorking),
         .init(id: FinderPathActionID.cancel, title: "Cancel", isEnabled: isWorking)]
    }
    func activate(copyImmediately: Bool = false) {
        guard !active else { return }; active = true
        if copyImmediately { copy(allowPrompt: false) }
    }
    func performPrimary() { copy(allowPrompt: needsConsent) }
    func copy(allowPrompt: Bool = false) {
        guard canCopy, !allowPrompt || needsConsent else { return }
        generation &+= 1; let id = generation
        isWorking = true; statusMessage = nil; showsActionsMenu = false
        task = Task { [weak self, services] in
            do {
                try Task.checkCancellation()
                switch try await services.reader.authorization(allowPrompt: allowPrompt) {
                case .authorized: break
                case .requiresConsent: throw FinderPathError.permissionRequired
                case .denied: throw FinderPathError.permissionDenied
                case .finderUnavailable: throw FinderPathError.finderUnavailable
                }
                try Task.checkCancellation()
                guard let self, self.active, self.generation == id else { return }
                self.needsConsent = false; self.permissionDenied = false
                let snapshot = try await services.reader.capture()
                // Validate always consumes a returned token, including when this task was cancelled.
                try await services.reader.validate(snapshot)
                try Task.checkCancellation()
                guard self.active, self.generation == id else { return }
                // No suspension between the final cancellation/generation check and clipboard commit.
                try services.copier.copy(snapshot.path)
                self.isWorking = false
                self.statusMessage = snapshot.origin == .selectedItem ? "Selected Finder item path copied." : "Current Finder folder path copied."
            } catch {
                guard let self, self.active, self.generation == id, !Task.isCancelled else { return }
                self.isWorking = false
                if error is CancellationError { return }
                let failure = error as? FinderPathError ?? .unavailable
                self.needsConsent = failure == .permissionRequired
                self.permissionDenied = failure == .permissionDenied
                self.statusMessage = failure.message
            }
        }
    }
    func openSettings() {
        guard active, isEnabled, !isWorking else { return }
        generation &+= 1; let id = generation; isWorking = true; showsActionsMenu = false
        task = Task { [weak self, services] in
            do {
                try Task.checkCancellation(); try await services.openSettings(); try Task.checkCancellation()
                guard let self, self.active, self.generation == id else { return }
                self.isWorking = false; self.statusMessage = "In Privacy & Security → Automation, enable Finder for Commandly, then retry."
            } catch {
                guard let self, self.active, self.generation == id, !Task.isCancelled else { return }
                self.isWorking = false; self.statusMessage = "Open System Settings → Privacy & Security → Automation to check Finder access."
            }
        }
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case FinderPathActionID.copy: copy()
        case FinderPathActionID.allow: copy(allowPrompt: true)
        case FinderPathActionID.settings: openSettings()
        case FinderPathActionID.cancel: cancel()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func moveSelection(offset: Int) {}
    func handleEscape() -> Bool { if isWorking { cancel(); return true }; return false }
    func goBack() { stop(); onGoBack() }
    private func cancel() {
        generation &+= 1; task?.cancel(); task = nil; isWorking = false
        statusMessage = "Copy cancelled. Any macOS consent dialog remains managed by macOS."
    }
    func stop() {
        generation &+= 1; task?.cancel(); task = nil; isWorking = false; active = false
        needsConsent = false; permissionDenied = false; statusMessage = nil; showsActionsMenu = false
    }
    func flushForTesting() async { await task?.value }
    var pendingTaskForTesting: Task<Void, Never>? { task }
}
