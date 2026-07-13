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
            defaultActions: [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.copy,
                    title: "Primary Action",
                    isPrimary: true,
                    keyHint: .return
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK
                )
            ]
        )
        self.manifest = manifest
        self.definition = LauncherApplicationDefinition(
            manifest: manifest,
            parentID: BuiltInLauncherApplicationGroup.catalogID,
            kind: .application,
            order: 100 + (OfflineToolKind.allCases.firstIndex(of: tool) ?? 0)
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
