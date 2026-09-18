import AIKit
import CommandKit
import SwiftUI

/// Each saved agent owns a stable, searchable tool ID for launcher and shortcut preferences.
@MainActor struct AIAgentsApplication: LauncherApplication {
    static let id = CommandID(rawValue: "ai.agents")
    static let openToolID = CommandID(rawValue: "ai.agents.tool.open")
    static let manifest = CommandManifest(id: id, title: "AI Agents",
        subtitle: "Personal AI profiles, reviewed memory, and reusable instruction skills",
        systemImage: "person.crop.square", category: .productivity, mode: .view,
        keywords: ["AI", "agent", "assistant", "profile", "memory", "skills"], badgeTitle: "AI Extension")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.aiExtensionsID, kind: .aiExtension, order: 6,
        documentation: .init(category: .productivity,
            overview: "Create text assistants with their own instructions, selected model, and explicit saved context.",
            sections: [.init(id: "agents", title: "Create and use an agent", blocks: [
                .steps("setup", ["Configure a text provider in Settings → AI.", "Open AI Agents, choose New Agent, select its model, and save.", "Search the agent name or assign its individual tool a shortcut in Settings → Applications."]),
                .paragraph("memory", "Memory is saved only when you choose Save Memory. Review, disable, edit, or delete it in Memory. My Profile is sent only by agents with Use My Profile enabled. Chats remain in the current session."),
                .paragraph("skills", "Skills are reusable instruction text. Author a skill or import a Commandly skill JSON file, review it, save it, and enable it for an agent. Export shares only that skill's name and instructions."),
                .paragraph("limits", "Agents use Quick AI's text runtime. They do not execute tools, read files, browse, monitor activity, or run in the background. Model discovery and responses contact the selected provider only after an explicit action.")
            ])], keywords: ["AI agents", "memory", "skills", "personal profile"]))
    let services: AIAgentsApplicationServices
    static func toolID(for id: UUID) -> CommandID { .init(rawValue: "ai.agents.agent." + id.uuidString.lowercased()) }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Manage AI Agents",
            subtitle: "Create agents, review memory, and author instruction skills", systemImage: "person.crop.square",
            keywords: ["AI", "agent", "profile", "memory", "skills"])] + services.library.document.agents.enumerated().map { index, agent in
            .tool(id: Self.toolID(for: agent.id), parentID: Self.id, title: agent.name,
                subtitle: "Chat with your saved AI agent", systemImage: "person.crop.square", order: index + 1,
                keywords: ["AI", "agent", "chat", agent.name])
        }
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { launch(agentID: nil, in: context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        if toolID == Self.openToolID { return launch(in: context) }
        guard let agent = services.library.document.agents.first(where: { Self.toolID(for: $0.id) == toolID }) else {
            return .message("This AI agent is no longer available.")
        }
        return launch(agentID: agent.id, in: context)
    }
    private func launch(agentID: UUID?, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = AIAgentsViewModel(services: services, selectedAgentID: agentID,
            onGoBack: context.navigation.goBack, onOpenSettings: context.navigation.openAISettings,
            onOpenApplicationSettings: context.navigation.openSettings)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { AIAgentsView(model: $0) })
    }
}
