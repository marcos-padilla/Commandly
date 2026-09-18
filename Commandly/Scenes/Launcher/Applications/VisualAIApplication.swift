import CommandKit
import Infrastructure
import SwiftUI

@MainActor struct VisualAIApplication: LauncherApplication {
    static let id = CommandID(rawValue: "ai.visual")
    static let screenID = CommandID(rawValue: "ai.visual.screen")
    static let regionID = CommandID(rawValue: "ai.visual.region")
    static let manifest = CommandManifest(id: id, title: "Visual AI", subtitle: "Ask about a reviewed screenshot",
        systemImage: "viewfinder", category: .productivity, mode: .view,
        keywords: ["screenshot", "screen context", "vision", "AI", "region"], badgeTitle: "AI Extension")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .aiExtension, order: 54, documentation: RegisteredApplicationDocumentation.visualAI)
    let services: VisualAIApplicationServices
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.screenID, parentID: Self.id, title: "Ask AI About Full Screen", subtitle: "Capture one display, review it, then send",
            systemImage: "display", category: .productivity, keywords: ["full screen", "screenshot", "AI context"]),
         .tool(id: Self.regionID, parentID: Self.id, title: "Ask AI About a Region", subtitle: "Select a region, review it, then send",
            systemImage: "viewfinder", category: .productivity, keywords: ["region", "selection", "AI context"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { present(.display, context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard arguments.values.isEmpty, [Self.screenID, Self.regionID].contains(toolID) else { return .message("Visual AI accepts no command arguments.") }
        return present(toolID == Self.regionID ? .region : .display, context)
    }
    private func present(_ kind: ScreenshotKind, _ context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message("Enable Visual AI in Applications settings first.") }
        let model = VisualAIModel(services: services, openAISettings: context.navigation.openAISettings, goBack: context.navigation.goBack)
        model.kind = kind
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { VisualAIView(model: $0) })
    }
}
