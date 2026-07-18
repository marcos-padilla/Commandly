import CommandKit
import Foundation

nonisolated enum LauncherCommandWheelActionID {
    static let add = CommandActionID(rawValue: "command-wheel.add")
}

nonisolated struct LauncherCommandWheelActionTarget: Identifiable, Equatable, Sendable {
    let reference: CommandReference
    let title: String
    let systemImage: String

    var id: String {
        "\(reference.commandID.rawValue):\(title)"
    }
}

extension LauncherViewModel {
    var showsRegisteredCommandActionsPanel: Bool {
        registeredCommandActionsTarget != nil
    }

    var registeredCommandActionsPanelTitle: String {
        registeredCommandActionsTarget?.title ?? "Command"
    }

    var filteredRegisteredCommandActions: [LauncherActionPanelItem] {
        let actions = [Self.addToCommandWheelPanelItem]
        let query = registeredCommandActionsQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Returns the exact persistable reference represented by a launcher search row.
    ///
    /// Installed applications retain their typed bundle-identifier argument; registered
    /// application rows use the same argument-free reference sent to shared execution.
    func commandWheelReference(for item: LauncherItem) -> CommandReference? {
        switch item.action {
        case .launchApplication(let commandID):
            return CommandReference(commandID: commandID)
        case .openInstalledApplication(let bundleIdentifier):
            return BuiltInCommandReference.openInstalledApplication(
                bundleIdentifier: bundleIdentifier
            )
        default:
            return nil
        }
    }

    func presentContextActions(for item: LauncherItem) {
        select(item.id)
        switch item.action {
        case .openInstalledApplication(let bundleIdentifier):
            dismissRegisteredCommandActionsPanel()
            presentApplicationActions(forBundleID: bundleIdentifier)
        case .launchApplication:
            presentRegisteredCommandActions(for: item)
        default:
            break
        }
    }

    func presentRegisteredCommandActions(for item: LauncherItem) {
        guard commandWheelAssignmentStore != nil,
              let reference = commandWheelReference(for: item) else {
            statusMessage = "Command Wheel settings are unavailable."
            return
        }
        dismissApplicationActionsPanel()
        registeredCommandActionsTarget = LauncherCommandWheelActionTarget(
            reference: reference,
            title: item.title,
            systemImage: item.systemImage
        )
        registeredCommandActionsQuery = ""
        statusMessage = nil
    }

    func dismissRegisteredCommandActionsPanel() {
        registeredCommandActionsTarget = nil
        registeredCommandActionsQuery = ""
    }

    func performRegisteredCommandAction(_ id: CommandActionID) {
        guard id == LauncherCommandWheelActionID.add,
              let target = registeredCommandActionsTarget else {
            return
        }
        dismissRegisteredCommandActionsPanel()
        presentCommandWheelAssignment(for: target)
    }

    func presentCommandWheelAssignmentForInstalledApplication(
        bundleIdentifier: String
    ) {
        let app = cachedApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        })
        let title: String
        let systemImage: String
        if let app {
            title = app.name
            systemImage = "app.fill"
        } else if case .openInstalledApplication(let selectedBundleID) = selectedItem?.action,
                  selectedBundleID == bundleIdentifier {
            title = selectedItem?.title ?? bundleIdentifier
            systemImage = selectedItem?.systemImage ?? "app.fill"
        } else {
            title = bundleIdentifier
            systemImage = "app.fill"
        }
        presentCommandWheelAssignment(
            for: LauncherCommandWheelActionTarget(
                reference: BuiltInCommandReference.openInstalledApplication(
                    bundleIdentifier: bundleIdentifier
                ),
                title: title,
                systemImage: systemImage
            )
        )
    }

    private func presentCommandWheelAssignment(
        for target: LauncherCommandWheelActionTarget
    ) {
        commandWheelAssignmentPreparationTask?.cancel()
        let preparationID = UUID()
        commandWheelAssignmentPreparationID = preparationID
        statusMessage = "Loading Command Wheel settings…"
        commandWheelAssignmentPreparationTask = Task { @MainActor [weak self] in
            guard let self, let store = commandWheelAssignmentStore else { return }
            let isReady = await store.prepareForAssignment()
            guard Task.isCancelled == false,
                  commandWheelAssignmentPreparationID == preparationID else {
                return
            }
            commandWheelAssignmentPreparationTask = nil
            commandWheelAssignmentPreparationID = nil
            guard isReady else {
                statusMessage = "Command Wheel settings could not be loaded. Open Settings to recover them."
                return
            }
            presentPreparedCommandWheelAssignment(for: target, store: store)
        }
    }

    private func presentPreparedCommandWheelAssignment(
        for target: LauncherCommandWheelActionTarget,
        store: any CommandWheelAssignmentStoring
    ) {
        let model = CommandWheelAssignmentModel(
            reference: target.reference,
            commandTitle: target.title,
            commandSystemImage: target.systemImage,
            store: store,
            reportStatus: { [weak self] message in
                self?.statusMessage = message
            },
            revealAssignment: { [weak self] location in
                guard let self else { return }
                self.onDismiss()
                self.onOpenCommandWheelSettings(location)
            }
        )
        guard let model else {
            statusMessage = "Command Wheel settings are unavailable."
            return
        }
        dismissApplicationActionsPanel()
        dismissRegisteredCommandActionsPanel()
        commandWheelAssignmentModel = model
    }

    static var addToCommandWheelPanelItem: LauncherActionPanelItem {
        LauncherActionPanelItem(
            id: LauncherCommandWheelActionID.add,
            title: "Add to Command Wheel…",
            systemImage: "circle.grid.cross",
            section: "command-wheel"
        )
    }
}
