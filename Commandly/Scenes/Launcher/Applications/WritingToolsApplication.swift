import CommandKit
import SwiftUI

@MainActor
struct WritingToolsApplication: LauncherApplication {
    static let id = CommandID(rawValue: "text.writing-tools")
    static let reviewToolID = CommandID(rawValue: "text.writing-tools.tool.review")
    static let inlineHelpToolID = CommandID(rawValue: "text.writing-tools.tool.inline-help")
    static let manifest = CommandManifest(id: id, title: "Spelling & Grammar",
        subtitle: "Check and review text with native writing services", systemImage: "text.badge.checkmark",
        category: .productivity, mode: .view, keywords: ["grammar", "spelling", "spelling grammar", "proofread", "correct", "quick fix", "writing"])
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, kind: .application,
        documentation: RegisteredApplicationDocumentation.writingTools)
    private let services: WritingToolsApplicationServices
    init(services: WritingToolsApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.reviewToolID, parentID: Self.id, title: "Check Spelling & Grammar",
            subtitle: "Review native suggestions for entered text", systemImage: "text.badge.checkmark", keywords: ["proofread", "correct"]),
         .tool(id: Self.inlineHelpToolID, parentID: Self.id, title: "Quick Fix in Other Apps",
            subtitle: "Set up the native selected-text Service and its shortcut", systemImage: "cursorarrow.and.square.on.square.dashed",
            keywords: ["inline", "quick fix", "selection", "services"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { present(in: context, instructions: false) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard [Self.reviewToolID, Self.inlineHelpToolID].contains(toolID) else { return .message("This writing tool is unavailable.") }
        return present(in: context, instructions: toolID == Self.inlineHelpToolID)
    }
    private func present(in context: LauncherApplicationContext, instructions: Bool) -> LauncherApplicationLaunch {
        let model = WritingToolsViewModel(services: services, showsInlineInstructions: instructions, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { WritingToolsView(viewModel: $0) })
    }
}
