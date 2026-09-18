import CommandKit
import SwiftUI

@MainActor
struct ScheduleApplication: LauncherApplication {
    static let id = CommandID(rawValue: "schedule.open")
    static let openToolID = CommandID(rawValue: "schedule.tool.open")
    static let joinNextToolID = CommandID(rawValue: "schedule.tool.join-next")
    static let manifest = CommandManifest(
        id: id, title: "My Schedule", subtitle: "Review upcoming events and join meetings",
        systemImage: "calendar", category: .productivity, mode: .view,
        keywords: ["calendar", "agenda", "schedule", "meeting", "join", "autojoin"], badgeTitle: "Application"
    )
    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 32, documentation: RegisteredApplicationDocumentation.schedule
    )
    private let services: ScheduleApplicationServices

    init(services: ScheduleApplicationServices) { self.services = services }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            .tool(id: Self.openToolID, parentID: Self.id, title: "Open My Schedule",
                  subtitle: "Review your upcoming Calendar events", systemImage: "calendar",
                  keywords: ["agenda", "calendar", "schedule"]),
            .tool(id: Self.joinNextToolID, parentID: Self.id, title: "Join Next Meeting",
                  subtitle: "Review the next meeting link before joining", systemImage: "video",
                  order: 1, keywords: ["join", "meeting", "conference", "next"])
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(reviewNext: false, context: context)
    }

    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.openToolID || toolID == Self.joinNextToolID else {
            return .message("Schedule tool is unavailable.")
        }
        return makeLaunch(reviewNext: toolID == Self.joinNextToolID, context: context)
    }

    private func makeLaunch(reviewNext: Bool, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = ScheduleViewModel(services: services, reviewNextMeeting: reviewNext, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            ScheduleView(viewModel: $0)
        })
    }
}
