import CommandKit
import SwiftUI

@MainActor struct NotionWorkspaceApplication: LauncherApplication {
    static let id = CommandID(rawValue: "workspace.notion")
    static let searchID = CommandID(rawValue: "workspace.notion.search")
    static let manifest = CommandManifest(id: id, title: "Notion Workspace", subtitle: "Search shared pages and browse their contents",
        systemImage: "doc.text.magnifyingglass", category: .productivity, mode: .view,
        keywords: ["notion", "workspace", "pages", "databases", "knowledge"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 54, documentation: RegisteredApplicationDocumentation.notionWorkspace)
    let services: NotionWorkspaceApplicationServices
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.searchID, parentID: Self.id, title: "Search Notion Workspace", subtitle: "Find pages shared with your integration", systemImage: "doc.text.magnifyingglass", keywords: ["notion", "pages", "workspace"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message("Notion Workspace is disabled in Settings.") }
        let model = NotionWorkspaceViewModel(services: services, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { NotionWorkspaceView(model: $0) })
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.searchID, arguments.values.isEmpty else { return .message("This Notion tool is unavailable.") }
        return launch(in: context)
    }
}
