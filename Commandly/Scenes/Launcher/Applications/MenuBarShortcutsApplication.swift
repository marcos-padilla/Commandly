import CommandKit
import SwiftUI

@MainActor
struct MenuBarShortcutsApplication: LauncherApplication {
    static let id = CommandID(rawValue: "menu-bar.shortcuts")
    static let manifest = CommandManifest(id: id, title: "Menu Bar Shortcuts",
        subtitle: "Keep chosen Commandly tools beside the clock", systemImage: "menubar.rectangle",
        category: .productivity, mode: .view, keywords: ["pin", "menu bar", "status", "quick access", "shortcuts"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID, kind: .application, order: 81,
        documentation: RegisteredApplicationDocumentation.menuBarShortcuts)
    let controller: MenuBarShortcutController?
    init(controller: MenuBarShortcutController? = nil) { self.controller = controller }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard let controller else { return .message("Menu-bar shortcuts are unavailable in this session.") }
        let model = MenuBarShortcutsModel(controller: controller, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { MenuBarShortcutsView(model: $0) })
    }
}
