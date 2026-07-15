import CommandKit
import Infrastructure
import SearchKit
import SwiftUI

@MainActor
struct FinderAIApplicationServices {
    let runtime: any AIProviderRuntimeServicing
    let workspace: any FinderAIWorkspaceQuerying
    let toolExecutor: any FinderAIToolExecuting

    init(
        runtime: any AIProviderRuntimeServicing,
        workspace: any FinderAIWorkspaceQuerying,
        toolExecutor: any FinderAIToolExecuting
    ) {
        self.runtime = runtime
        self.workspace = workspace
        self.toolExecutor = toolExecutor
    }

    static var inMemory: FinderAIApplicationServices {
        let workspace = FinderAIWorkspaceService(
            folderAccessStore: InMemoryFolderAccessStore(),
            searchService: InMemoryFileSearchService(),
            fileRevealer: InMemoryFileRevealer()
        )
        return FinderAIApplicationServices(
            runtime: InMemoryAIProviderRuntimeService(),
            workspace: workspace,
            toolExecutor: FinderAIToolExecutor(
                workspace: workspace,
                approvalCoordinator: workspace
            )
        )
    }
}

enum FinderAIApplicationID {
    static let command = CommandID(rawValue: "ai.finder")
}

@MainActor
struct FinderAIApplication: LauncherApplication {
    private static let manifest = CommandManifest(
        id: FinderAIApplicationID.command,
        title: "Finder AI",
        subtitle: "Ask questions and approve actions in authorized folders",
        systemImage: "folder.badge.gearshape",
        category: .productivity,
        mode: .view,
        keywords: [
            "AI", "Finder", "files", "folders", "search", "organize", "rename", "move",
            "copy", "trash"
        ],
        badgeTitle: "AI Extension",
        defaultActions: [
            CommandActionDescriptor(
                id: FinderAIActionID.send,
                title: "Send",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            ),
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.aiExtensionsID,
        kind: .aiExtension,
        order: 10,
        documentation: RegisteredApplicationDocumentation.finderAI
    )

    private let services: FinderAIApplicationServices

    init(services: FinderAIApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = FinderAIViewModel(
            runtime: services.runtime,
            workspace: services.workspace,
            toolExecutor: services.toolExecutor,
            onGoBack: context.navigation.goBack,
            onOpenSettings: context.navigation.openAISettings,
            onOpenPermissionsSettings: context.navigation.openPermissionsSettings
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                FinderAIView(viewModel: $0)
            }
        )
    }
}

extension FinderAIViewModel: LauncherApplicationModel {}
