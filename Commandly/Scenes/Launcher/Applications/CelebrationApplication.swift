import CommandKit
import SwiftUI

@MainActor
struct CelebrationApplication: LauncherApplication {
    static let id = CommandID(rawValue: "celebration.confetti")
    static let celebrateToolID = CommandID(rawValue: "celebration.confetti.play")
    static let manifest = CommandManifest(
        id: id, title: "Confetti", subtitle: "Celebrate a finished task with a little color",
        systemImage: "party.popper", category: .productivity, mode: .view,
        keywords: ["celebrate", "celebration", "confetti", "party", "well done", "success"],
        badgeTitle: "Application"
    )
    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 80, documentation: RegisteredApplicationDocumentation.celebration
    )

    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.celebrateToolID, parentID: Self.id, title: "Celebrate with Confetti",
               subtitle: "Play one brief celebration inside Commandly", systemImage: "party.popper",
               keywords: ["confetti", "celebrate", "party", "celebration"])]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = CelebrationViewModel(onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            CelebrationView(model: $0)
        })
    }

    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.celebrateToolID else { return .message("That celebration is unavailable.") }
        return launch(in: context)
    }
}
