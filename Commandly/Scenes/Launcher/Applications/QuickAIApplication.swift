import CommandKit
import SwiftUI

@MainActor
struct QuickAIApplication: LauncherApplication {
    static let id = CommandID(rawValue: "ai.chat")
    static let openToolID = CommandID(rawValue: "ai.chat.tool.open")
    static let manifest = CommandManifest(id: id, title: "Quick AI",
        subtitle: "Ask, draft, and follow up with your configured AI model",
        systemImage: "bubble.left.and.text.bubble.right", category: .productivity, mode: .view,
        keywords: ["AI", "chat", "ask", "question", "quick AI", "assistant", "draft", "conversation"],
        badgeTitle: "AI Extension")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.aiExtensionsID, kind: .aiExtension, order: 5,
        documentation: RegisteredApplicationDocumentation.quickAI)
    private let services: QuickAIApplicationServices
    init(services: QuickAIApplicationServices) { self.services = services }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Open AI Chat",
            subtitle: "Start a text conversation with your configured provider", systemImage: "bubble.left.and.text.bubble.right",
            keywords: ["chat", "AI", "quick AI", "question", "ask"]) ]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = QuickAIViewModel(service: services.chat, onGoBack: context.navigation.goBack,
                                    onOpenSettings: context.navigation.openAISettings)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { QuickAIView(viewModel: $0) })
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.openToolID else { return .message("This AI chat tool is unavailable.") }
        return launch(in: context)
    }
}
