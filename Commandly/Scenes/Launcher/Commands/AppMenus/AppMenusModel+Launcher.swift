import CommandKit
import Infrastructure

private enum AppMenusAction {
    static let invoke = CommandActionID(rawValue: "app-menus.invoke")
    static let read = CommandActionID(rawValue: "app-menus.read")
    static let favorite = CommandActionID(rawValue: "app-menus.favorite")
}
extension AppMenusModel: LauncherApplicationModel {
    var statusMessage: String? { recoveryMessage }
    var footerActions: [CommandActionDescriptor] {
        [.init(id: AppMenusAction.invoke, title: "Invoke Command", isPrimary: true, keyHint: .return,
               isEnabled: state == .ready && filteredItems.contains { $0.handle == selection && $0.enabled }),
         .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: AppMenusAction.read, title: "Read Current App Menus", isEnabled: !isWorking),
         .init(id: AppMenusAction.favorite, title: "Toggle Favorite", isEnabled: favoritesLoaded && !isWorking && selection != nil)]
    }
    func moveSelection(offset: Int) {
        selection = LauncherListSelection.nextID(in: filteredItems, selectedID: selection, offset: offset, id: \.handle)
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case AppMenusAction.invoke: invokeSelection()
        case AppMenusAction.read: readMenus()
        case AppMenusAction.favorite:
            if let item = filteredItems.first(where: { $0.handle == selection }) { toggleFavorite(item) }
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if showsActionsMenu { showsActionsMenu = false; return true }
        if !query.isEmpty { query = ""; return true }
        return false
    }
}
