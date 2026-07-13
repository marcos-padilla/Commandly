import CommandKit
import SwiftUI

/// Behavior every active launcher application exposes to the shared launcher shell.
///
/// Feature data remains strongly typed inside the application. This deliberately small contract
/// only covers shell coordination such as footer actions and keyboard selection.
@MainActor
protocol LauncherApplicationModel: AnyObject {
    var statusMessage: String? { get }
    var footerActions: [CommandActionDescriptor] { get }
    var menuActions: [CommandActionDescriptor] { get }
    var showsActionsMenu: Bool { get set }

    func moveSelection(offset: Int)
    func perform(_ actionID: CommandActionID)
    func stop()
    /// Handles Escape inside the application (clear query, close panels, etc.).
    ///
    /// Return `true` when Escape was consumed without leaving the application.
    /// Return `false` to let the launcher shell return to home.
    func handleEscape() -> Bool
}

extension LauncherApplicationModel {
    func stop() {}

    func handleEscape() -> Bool { false }
}

/// Pure selection helpers shared by launcher lists with different item and identifier types.
enum LauncherListSelection {
    static func nextID<Item, ID: Equatable>(
        in items: [Item],
        selectedID: ID?,
        offset: Int,
        id: (Item) -> ID
    ) -> ID? {
        guard items.isEmpty == false else { return nil }
        let currentIndex = selectedID.flatMap { selectedID in
            items.firstIndex { id($0) == selectedID }
        } ?? 0
        return id(items[(currentIndex + offset + items.count) % items.count])
    }

    static func resolvedID<Item, ID: Equatable>(
        in items: [Item],
        selectedID: ID?,
        id: (Item) -> ID
    ) -> ID? {
        guard let selectedID, items.contains(where: { id($0) == selectedID }) else {
            return items.first.map(id)
        }
        return selectedID
    }
}

/// Type-erased boundary used only while the launcher dynamically hosts an application.
@MainActor
final class LauncherApplicationSession {
    let manifest: CommandManifest

    private let model: AnyObject
    private let surface: AnyView
    private let statusMessageProvider: () -> String?
    private let footerActionsProvider: () -> [CommandActionDescriptor]
    private let menuActionsProvider: () -> [CommandActionDescriptor]
    private let actionsMenuProvider: () -> Bool
    private let actionsMenuSetter: (Bool) -> Void
    private let moveSelectionHandler: (Int) -> Void
    private let actionHandler: (CommandActionID) -> Void
    private let stopHandler: () -> Void
    private let escapeHandler: () -> Bool

    init<Model: LauncherApplicationModel, Surface: View>(
        manifest: CommandManifest,
        model: Model,
        @ViewBuilder surface: (Model) -> Surface
    ) {
        self.manifest = manifest
        self.model = model
        self.surface = AnyView(surface(model))
        self.statusMessageProvider = { model.statusMessage }
        self.footerActionsProvider = { model.footerActions }
        self.menuActionsProvider = { model.menuActions }
        self.actionsMenuProvider = { model.showsActionsMenu }
        self.actionsMenuSetter = { model.showsActionsMenu = $0 }
        self.moveSelectionHandler = { model.moveSelection(offset: $0) }
        self.actionHandler = { model.perform($0) }
        self.stopHandler = { model.stop() }
        self.escapeHandler = { model.handleEscape() }
    }

    var statusMessage: String? { statusMessageProvider() }
    var footerActions: [CommandActionDescriptor] { footerActionsProvider() }
    var menuActions: [CommandActionDescriptor] { menuActionsProvider() }

    var showsActionsMenu: Bool {
        get { actionsMenuProvider() }
        set { actionsMenuSetter(newValue) }
    }

    var primaryActionID: CommandActionID? {
        footerActions.first(where: \.isPrimary)?.id ?? footerActions.first?.id
    }

    func makeSurface() -> AnyView {
        surface
    }

    func model<Model>(as type: Model.Type = Model.self) -> Model? {
        model as? Model
    }

    func moveSelection(offset: Int) {
        moveSelectionHandler(offset)
    }

    func perform(_ actionID: CommandActionID) {
        actionHandler(actionID)
    }

    func handleEscape() -> Bool {
        escapeHandler()
    }

    func stop() {
        stopHandler()
    }
}
