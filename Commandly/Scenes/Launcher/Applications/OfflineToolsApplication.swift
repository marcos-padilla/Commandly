import CommandKit
import SwiftUI

@MainActor
struct OfflineToolsApplication: LauncherApplication {
    let definition: LauncherApplicationDefinition
    private let manifest: CommandManifest
    private let tool: OfflineToolKind
    private let services: OfflineToolsServices

    init(tool: OfflineToolKind, services: OfflineToolsServices) {
        self.tool = tool
        self.services = services
        let manifest = CommandManifest(
            id: CommandID(rawValue: tool.commandID),
            title: tool.title,
            subtitle: tool.subtitle,
            systemImage: tool.systemImage,
            category: .productivity,
            mode: .view,
            keywords: tool.keywords,
            badgeTitle: "Application",
            defaultActions: tool.manifestActions
        )
        self.manifest = manifest
        self.definition = LauncherApplicationDefinition(
            manifest: manifest,
            parentID: BuiltInLauncherApplicationGroup.catalogID,
            kind: .application,
            order: 100 + (OfflineToolKind.allCases.firstIndex(of: tool) ?? 0),
            documentation: tool.documentation
        )
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = OfflineToolsViewModel(
            tool: tool,
            services: services,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: manifest, model: model) {
                OfflineToolsView(viewModel: $0)
            }
        )
    }
}

extension OfflineToolsViewModel: LauncherApplicationModel {}

private extension OfflineToolKind {
    var manifestActions: [CommandActionDescriptor] {
        switch self {
        case .emoji:
            return [
                primaryAction(id: BuiltInCommandActionID.copy, title: "Copy Emoji", keyHint: .return),
                actionsMenu,
            ]
        case .textCase:
            return [
                primaryAction(id: BuiltInCommandActionID.copy, title: "Copy Converted Text"),
                actionsMenu,
            ]
        case .color:
            return [
                primaryAction(id: BuiltInCommandActionID.copy, title: "Copy Hex"),
                actionsMenu,
            ]
        case .dictionary:
            return [
                primaryAction(id: OfflineToolsActionID.lookup, title: "Look Up", keyHint: .return),
                actionsMenu,
            ]
        case .fonts:
            return [
                primaryAction(id: BuiltInCommandActionID.copy, title: "Copy Font Name", keyHint: .return),
                actionsMenu,
            ]
        case .typing:
            return [
                primaryAction(id: OfflineToolsActionID.resetTyping, title: "New Attempt"),
            ]
        }
    }

    func primaryAction(
        id: CommandActionID,
        title: String,
        keyHint: CommandKeyHint? = nil
    ) -> CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            isPrimary: true,
            keyHint: keyHint
        )
    }

    var actionsMenu: CommandActionDescriptor {
        CommandActionDescriptor(
            id: BuiltInCommandActionID.openActions,
            title: "Actions",
            keyHint: .commandK
        )
    }
}
