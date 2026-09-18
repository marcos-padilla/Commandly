import AIKit
import CommandKit
import SwiftUI

@MainActor struct ExternalAgentApplication: LauncherApplication {
    let kind: ExternalAgentKind
    private let services: ExternalAgentApplicationServices
    init(kind: ExternalAgentKind, services: ExternalAgentApplicationServices) { self.kind = kind; self.services = services }
    static func id(_ kind: ExternalAgentKind) -> CommandID { .init(rawValue: "ai.external." + kind.rawValue.lowercased()) }
    private var manifest: CommandManifest {
        .init(id: Self.id(kind), title: kind.title + " Agent", subtitle: "Chat with your own \(kind.title) agent server",
              systemImage: "point.3.connected.trianglepath.dotted", category: .productivity, mode: .view,
              keywords: [kind.title, "agent", "chat", "gateway", "server"], badgeTitle: "AI Extension")
    }
    var definition: LauncherApplicationDefinition {
        .init(manifest: manifest, parentID: BuiltInLauncherApplicationGroup.aiExtensionsID, kind: .aiExtension,
              order: kind == .hermes ? 12 : 13, documentation: RegisteredApplicationDocumentation.externalAgents)
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message("Enable this agent in Applications settings first.") }
        let model = ExternalAgentViewModel(kind: kind, service: services.service, goBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: manifest, model: model) { ExternalAgentView(model: $0) })
    }
}
