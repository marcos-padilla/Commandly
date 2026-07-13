import CommandKit
import Foundation
import Observation

nonisolated enum SystemActivityMode: String, CaseIterable, Identifiable, Sendable {
    case resources
    case applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resources: return "Resources"
        case .applications: return "Applications"
        }
    }
}

nonisolated enum SystemActivityActionID {
    static let refresh = CommandActionID(rawValue: "system-activity.refresh")
    static let activate = CommandActionID(rawValue: "system-activity.activate")
    static let quit = CommandActionID(rawValue: "system-activity.quit")
    static let forceQuit = CommandActionID(rawValue: "system-activity.force-quit")
    static let quitAll = CommandActionID(rawValue: "system-activity.quit-all")
    static let confirm = CommandActionID(rawValue: "system-activity.confirm")
    static let cancel = CommandActionID(rawValue: "system-activity.cancel")
}

nonisolated enum SystemActivityConfirmation: Sendable, Equatable {
    case forceQuit(SystemApplicationSnapshot)
    case quitAll([SystemApplicationSnapshot])

    var title: String {
        switch self {
        case .forceQuit(let application):
            return "Force Quit \(application.localizedName)?"
        case .quitAll(let applications):
            return applications.count == 1
                ? "Quit 1 Application?"
                : "Quit \(applications.count) Applications?"
        }
    }

    var message: String {
        switch self {
        case .forceQuit:
            return "Unsaved changes may be lost. This action cannot be undone."
        case .quitAll:
            return """
            Commandly, Finder, and the frontmost application are protected. \
            Unsaved changes in the other applications may be lost.
            """
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .forceQuit: return "Force Quit"
        case .quitAll: return "Quit Applications"
        }
    }
}

@Observable
@MainActor
final class SystemActivityViewModel {
    static let automaticRefreshInterval: Duration = .seconds(3)

    var mode: SystemActivityMode = .resources {
        didSet {
            showsActionsMenu = false
            refreshSelection()
        }
    }

    var query = "" {
        didSet { refreshSelection() }
    }

    var selectedProcessIdentifier: Int32?
    var showsActionsMenu = false

    private(set) var snapshot: SystemActivitySnapshot?
    private(set) var isRefreshing = false
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var pendingConfirmation: SystemActivityConfirmation?

    @ObservationIgnored
    private let service: any SystemActivityServicing
    @ObservationIgnored
    private let commandlyProcessIdentifier: Int32
    @ObservationIgnored
    private let commandlyBundleIdentifier: String?
    @ObservationIgnored
    private let onGoBack: () -> Void
    @ObservationIgnored
    private let onDismiss: () -> Void
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var operationTask: Task<Void, Never>?
    @ObservationIgnored
    private var refreshGeneration = 0

    init(
        service: any SystemActivityServicing,
        commandlyProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        commandlyBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        onGoBack: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.service = service
        self.commandlyProcessIdentifier = commandlyProcessIdentifier
        self.commandlyBundleIdentifier = commandlyBundleIdentifier
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
    }

    var resources: SystemResourceSnapshot? {
        snapshot?.resources
    }

    var applications: [SystemApplicationSnapshot] {
        snapshot?.applications ?? []
    }

    var filteredApplications: [SystemApplicationSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return applications }
        return applications.filter { application in
            application.localizedName.localizedCaseInsensitiveContains(trimmed)
                || (application.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || String(application.processIdentifier).contains(trimmed)
        }
    }

    var selectedApplication: SystemApplicationSnapshot? {
        filteredApplications.first { $0.processIdentifier == selectedProcessIdentifier }
            ?? filteredApplications.first
    }

    var quitAllCandidates: [SystemApplicationSnapshot] {
        applications.filter { terminationProtectionReason(for: $0) == nil }
    }

    var canTerminateSelectedApplication: Bool {
        guard let selectedApplication else { return false }
        return terminationProtectionReason(for: selectedApplication) == nil
            && isPerformingAction == false
    }

    var footerActions: [CommandActionDescriptor] {
        if let pendingConfirmation {
            return [
                CommandActionDescriptor(
                    id: SystemActivityActionID.confirm,
                    title: pendingConfirmation.confirmButtonTitle,
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: isPerformingAction == false
                ),
                CommandActionDescriptor(
                    id: SystemActivityActionID.cancel,
                    title: "Cancel",
                    keyHint: .escape,
                    isEnabled: isPerformingAction == false
                )
            ]
        }

        switch mode {
        case .resources:
            return [
                CommandActionDescriptor(
                    id: SystemActivityActionID.refresh,
                    title: isRefreshing ? "Refreshing…" : "Refresh",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: isRefreshing == false
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK
                )
            ]
        case .applications:
            return [
                CommandActionDescriptor(
                    id: SystemActivityActionID.activate,
                    title: "Switch to Application",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: selectedApplication != nil && isPerformingAction == false
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK,
                    isEnabled: isPerformingAction == false
                )
            ]
        }
    }

    var menuActions: [CommandActionDescriptor] {
        if pendingConfirmation != nil { return [] }
        var actions = [
            CommandActionDescriptor(
                id: SystemActivityActionID.refresh,
                title: "Refresh System Activity",
                isEnabled: isRefreshing == false && isPerformingAction == false
            )
        ]
        guard mode == .applications else { return actions }
        actions.append(contentsOf: [
            CommandActionDescriptor(
                id: SystemActivityActionID.activate,
                title: "Switch to Application",
                isEnabled: selectedApplication != nil && isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: SystemActivityActionID.quit,
                title: "Quit Application",
                isEnabled: canTerminateSelectedApplication
            ),
            CommandActionDescriptor(
                id: SystemActivityActionID.forceQuit,
                title: "Force Quit…",
                isEnabled: canTerminateSelectedApplication
            ),
            CommandActionDescriptor(
                id: SystemActivityActionID.quitAll,
                title: "Quit All Other Applications…",
                isEnabled: quitAllCandidates.isEmpty == false && isPerformingAction == false
            )
        ])
        return actions
    }

    func start() {
        guard automaticRefreshTask == nil else { return }
        refresh(showSuccessMessage: false)
        automaticRefreshTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: Self.automaticRefreshInterval)
                } catch {
                    return
                }
                guard Task.isCancelled == false else { return }
                guard let self else { return }
                if self.isRefreshing == false && self.isPerformingAction == false {
                    self.refresh(showSuccessMessage: false)
                }
            }
        }
    }

    func stop() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        operationTask?.cancel()
        operationTask = nil
        isRefreshing = false
        isPerformingAction = false
    }

    func refresh(showSuccessMessage: Bool = true) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        isRefreshing = true
        if showSuccessMessage {
            statusMessage = nil
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updatedSnapshot = try await service.snapshot()
                guard Task.isCancelled == false, refreshGeneration == generation else { return }
                apply(updatedSnapshot)
                if showSuccessMessage {
                    statusMessage = "System activity updated."
                }
                isRefreshing = false
            } catch is CancellationError {
                if refreshGeneration == generation {
                    isRefreshing = false
                }
            } catch {
                guard refreshGeneration == generation else { return }
                isRefreshing = false
                statusMessage = error.localizedDescription
            }
        }
    }

    func setMode(_ mode: SystemActivityMode) {
        self.mode = mode
        statusMessage = nil
    }

    func select(processIdentifier: Int32) {
        selectedProcessIdentifier = processIdentifier
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        guard mode == .applications else { return }
        guard let nextID = LauncherListSelection.nextID(
            in: filteredApplications,
            selectedID: selectedProcessIdentifier,
            offset: offset,
            id: \.processIdentifier
        ) else { return }
        selectedProcessIdentifier = nextID
        statusMessage = nil
    }

    func perform(_ actionID: CommandActionID) {
        if pendingConfirmation != nil {
            switch actionID {
            case SystemActivityActionID.confirm:
                confirmPendingAction()
            case SystemActivityActionID.cancel:
                cancelConfirmation()
            case BuiltInCommandActionID.goBack:
                goBack()
            default:
                break
            }
            return
        }

        switch actionID {
        case SystemActivityActionID.refresh:
            refresh()
        case SystemActivityActionID.activate:
            activateSelectedApplication()
        case SystemActivityActionID.quit:
            quitSelectedApplication()
        case SystemActivityActionID.forceQuit:
            requestForceQuitSelectedApplication()
        case SystemActivityActionID.quitAll:
            requestQuitAllApplications()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            goBack()
        default:
            break
        }
    }

    func activateSelectedApplication() {
        guard let application = selectedApplication, isPerformingAction == false else { return }
        showsActionsMenu = false
        isPerformingAction = true
        statusMessage = "Switching to \(application.localizedName)…"
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await service.activate(processIdentifier: application.processIdentifier)
            guard Task.isCancelled == false else { return }
            isPerformingAction = false
            if succeeded {
                onDismiss()
            } else {
                statusMessage = """
                Couldn’t switch to \(application.localizedName). It may no longer be running.
                """
            }
        }
    }

    func quitSelectedApplication() {
        guard let application = selectedApplication, isPerformingAction == false else { return }
        if let reason = terminationProtectionReason(for: application) {
            statusMessage = reason
            showsActionsMenu = false
            return
        }
        runTermination(of: application, mode: .graceful)
    }

    func requestForceQuitSelectedApplication() {
        guard let application = selectedApplication, isPerformingAction == false else { return }
        if let reason = terminationProtectionReason(for: application) {
            statusMessage = reason
            showsActionsMenu = false
            return
        }
        pendingConfirmation = .forceQuit(application)
        showsActionsMenu = false
        statusMessage = nil
    }

    func requestQuitAllApplications() {
        guard isPerformingAction == false else { return }
        let candidates = quitAllCandidates
        guard candidates.isEmpty == false else {
            statusMessage = "There are no other applications to quit."
            showsActionsMenu = false
            return
        }
        pendingConfirmation = .quitAll(candidates)
        showsActionsMenu = false
        statusMessage = nil
    }

    func confirmPendingAction() {
        guard let confirmation = pendingConfirmation, isPerformingAction == false else { return }
        confirm(confirmation)
    }

    func confirm(_ confirmation: SystemActivityConfirmation) {
        guard isPerformingAction == false else { return }
        pendingConfirmation = nil
        switch confirmation {
        case .forceQuit(let application):
            runTermination(of: application, mode: .force)
        case .quitAll(let applications):
            runQuitAll(applications)
        }
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
        statusMessage = nil
    }

    func terminationProtectionReason(for application: SystemApplicationSnapshot) -> String? {
        if application.processIdentifier == commandlyProcessIdentifier
            || (commandlyBundleIdentifier != nil
                && application.bundleIdentifier == commandlyBundleIdentifier) {
            return "Commandly protects its own process from termination."
        }
        if application.bundleIdentifier == "com.apple.finder" {
            return "Finder is protected from termination."
        }
        if application.isFrontmost {
            return "The frontmost application is protected. Switch away before quitting it."
        }
        return nil
    }

    func handleEscape() -> Bool {
        if pendingConfirmation != nil {
            cancelConfirmation()
            return true
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func goBack() {
        stop()
        onGoBack()
    }

    func waitForRefreshForTesting() async {
        let task = refreshTask
        await task?.value
    }

    func waitForOperationForTesting() async {
        let task = operationTask
        await task?.value
    }

    private func refreshSelection() {
        selectedProcessIdentifier = LauncherListSelection.resolvedID(
            in: filteredApplications,
            selectedID: selectedProcessIdentifier,
            id: \.processIdentifier
        )
    }

    private func apply(_ updatedSnapshot: SystemActivitySnapshot) {
        snapshot = updatedSnapshot
        refreshSelection()
    }

    private func runTermination(
        of application: SystemApplicationSnapshot,
        mode: SystemApplicationTerminationMode
    ) {
        guard isPerformingAction == false else { return }
        showsActionsMenu = false
        isPerformingAction = true
        statusMessage = mode == .force
            ? "Force quitting \(application.localizedName)…"
            : "Quitting \(application.localizedName)…"

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await service.terminate(
                processIdentifier: application.processIdentifier,
                mode: mode
            )
            guard Task.isCancelled == false else { return }
            let refreshed = await refreshAfterMutation()
            guard Task.isCancelled == false else { return }
            isPerformingAction = false
            if succeeded {
                let verb = mode == .force ? "Force quit" : "Quit"
                statusMessage = "\(verb) \(application.localizedName)."
                    + (refreshed ? "" : " Refresh to update the list.")
            } else {
                statusMessage = """
                Couldn’t quit \(application.localizedName). It may no longer be running.
                """
            }
        }
    }

    private func runQuitAll(_ applications: [SystemApplicationSnapshot]) {
        guard isPerformingAction == false else { return }
        isPerformingAction = true
        statusMessage = "Quitting applications…"

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var succeededCount = 0
            var failedNames: [String] = []
            for application in applications {
                guard Task.isCancelled == false else { return }
                let succeeded = await service.terminate(
                    processIdentifier: application.processIdentifier,
                    mode: .graceful
                )
                if succeeded {
                    succeededCount += 1
                } else {
                    failedNames.append(application.localizedName)
                }
            }

            guard Task.isCancelled == false else { return }
            let refreshed = await refreshAfterMutation()
            guard Task.isCancelled == false else { return }
            isPerformingAction = false
            statusMessage = quitAllStatus(
                succeededCount: succeededCount,
                failedNames: failedNames,
                refreshed: refreshed
            )
        }
    }

    private func refreshAfterMutation() async -> Bool {
        do {
            let updatedSnapshot = try await service.snapshot()
            guard Task.isCancelled == false else { return false }
            apply(updatedSnapshot)
            return true
        } catch {
            return false
        }
    }

    private func quitAllStatus(
        succeededCount: Int,
        failedNames: [String],
        refreshed: Bool
    ) -> String {
        let successText: String
        if succeededCount == 0 {
            successText = ""
        } else if succeededCount == 1 {
            successText = "Quit 1 application."
        } else {
            successText = "Quit \(succeededCount) applications."
        }

        let failureText: String
        if failedNames.isEmpty {
            failureText = ""
        } else {
            let visibleNames = failedNames.prefix(3).joined(separator: ", ")
            let remainingCount = max(failedNames.count - 3, 0)
            let suffix = remainingCount > 0 ? " and \(remainingCount) more" : ""
            failureText = "Couldn’t quit \(visibleNames)\(suffix)."
        }

        let refreshText = refreshed ? "" : " Refresh to update the list."
        return [successText, failureText]
            .filter { $0.isEmpty == false }
            .joined(separator: " ") + refreshText
    }
}
