import CommandKit
import Infrastructure
import SwiftUI

@MainActor struct AppMenusApplication: LauncherApplication {
    static let id = CommandID(rawValue: "system.app-menus")
    static let searchID = CommandID(rawValue: "system.app-menus.search")
    static let favoritesID = CommandID(rawValue: "system.app-menus.favorites")
    static let manifest = CommandManifest(id: id, title: "App Menus", subtitle: "Search commands in the current app’s menu",
        systemImage: "menubar.rectangle", category: .productivity, mode: .view,
        keywords: ["menu", "current app", "commands", "favorites"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 53, documentation: RegisteredApplicationDocumentation.appMenus)
    private let services: AppMenusApplicationServices
    init(services: AppMenusApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.searchID, parentID: Self.id, title: "Search Current App Menus", subtitle: "Read the current app’s accessible menu commands",
            systemImage: "menubar.rectangle", category: .productivity, keywords: ["menu", "command", "current app"]),
         .tool(id: Self.favoritesID, parentID: Self.id, title: "Favorite App Menus", subtitle: "Match saved favorites against the current app’s menu",
            systemImage: "star", category: .productivity, keywords: ["menu", "favorite", "commands"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(context, favoritesOnly: false) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard [Self.searchID, Self.favoritesID].contains(toolID), arguments.values.isEmpty else { return .message("This menu tool accepts no arguments.") }
        return makeLaunch(context, favoritesOnly: toolID == Self.favoritesID)
    }
    private func makeLaunch(_ context: LauncherApplicationContext, favoritesOnly: Bool) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message("Enable App Menus in Applications settings first.") }
        let model = AppMenusModel(client: services.client, favorites: services.favorites)
        model.favoritesOnly = favoritesOnly
        // Explicit launcher activation requests one snapshot. Permission is checked without prompting.
        model.readMenus()
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            AppMenusView(model: $0, goBack: context.navigation.goBack)
        })
    }
}
