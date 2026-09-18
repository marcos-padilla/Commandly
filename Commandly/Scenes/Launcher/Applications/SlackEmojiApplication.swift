import CommandKit
import SwiftUI

@MainActor
struct SlackEmojiApplication: LauncherApplication {
    static let id = CommandID(rawValue: "media.slack-emoji")
    static let openToolID = CommandID(rawValue: "media.slack-emoji.tool.open")
    static let manifest = CommandManifest(id: id, title: "Slack Emoji", subtitle: "Search your workspace's custom emoji",
        systemImage: "face.smiling", category: .productivity, mode: .view,
        keywords: ["slack", "workspace", "custom emoji", "reaction", "emoticon"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 50, documentation: RegisteredApplicationDocumentation.slackEmoji)
    private let services: SlackEmojiApplicationServices
    init(services: SlackEmojiApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Search Slack Custom Emoji", subtitle: "Choose an explicitly connected workspace",
               systemImage: "face.smiling", keywords: ["slack", "workspace emoji", "custom reaction"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = SlackEmojiViewModel(services: services, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { SlackEmojiView(model: $0) })
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments; guard toolID == Self.openToolID else { return .message("This Slack emoji tool is unavailable.") }; return launch(in: context)
    }
}
