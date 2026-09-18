import CommandKit
import SwiftUI

@MainActor
struct EmojiSearchApplication: LauncherApplication {
    static let id = CommandID(rawValue: "tools.emoji-search")
    static let openToolID = CommandID(rawValue: "tools.emoji-search.tool.open")
    static let semanticToolID = CommandID(rawValue: "tools.emoji-search.ai")
    static let manifest = CommandManifest(id: id, title: "Emoji Search",
        subtitle: "Find Unicode emoji by name, keyword, or an optional AI description",
        systemImage: "face.smiling", category: .productivity, mode: .view,
        keywords: ["emoji", "unicode", "symbol", "reaction", "skin tone", "semantic", "AI emoji"], badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: "Copy Emoji", isPrimary: true, keyHint: .return),
            CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)
        ])
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID, kind: .application, order: 100,
        documentation: RegisteredApplicationDocumentation.emojiSearch)
    private let services: EmojiSearchApplicationServices
    init(services: EmojiSearchApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Open Emoji Search",
               subtitle: "Search the complete Unicode emoji catalog locally", systemImage: "face.smiling",
               keywords: ["emoji", "unicode", "copy", "symbol"]),
         .tool(id: Self.semanticToolID, parentID: Self.id, title: "Find Emoji with AI",
               subtitle: "Describe an idea, then explicitly search with your configured model", systemImage: "sparkles",
               keywords: ["emoji", "AI", "semantic", "feeling", "reaction"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(mode: .local, context: context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == Self.openToolID || toolID == Self.semanticToolID else { return .message("This emoji tool is unavailable.") }
        return makeLaunch(mode: toolID == Self.semanticToolID ? .ai : .local, context: context)
    }
    private func makeLaunch(mode: EmojiSearchMode, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = EmojiSearchViewModel(services: services, initialMode: mode,
            onGoBack: context.navigation.goBack, onOpenSettings: context.navigation.openAISettings)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { EmojiSearchView(viewModel: $0) })
    }
}
