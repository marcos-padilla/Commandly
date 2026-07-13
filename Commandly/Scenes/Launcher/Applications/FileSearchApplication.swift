import CommandKit
import SwiftUI

@MainActor
struct FileSearchApplication: LauncherApplication {
    private let services: FileSearchApplicationServices

    let manifest = CommandManifest(
        id: BuiltInCommandID.searchFiles,
        title: "Search Files",
        subtitle: "Find files, folders, and indexed contents",
        systemImage: "doc.text.magnifyingglass",
        category: .productivity,
        mode: .view,
        keywords: ["files", "finder", "documents", "folders", "images"],
        badgeTitle: "Command",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: "Open",
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

    init(services: FileSearchApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = FileSearchViewModel(
            searchService: services.searchService,
            urlOpener: services.urlOpener,
            fileRevealer: services.fileRevealer,
            fileActionService: services.fileActionService,
            finderInfoPresenter: services.finderInfoPresenter,
            pasteboard: services.pasteboard,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher,
            onOpenSettings: context.navigation.openSettings
        )
        return .present(
            LauncherApplicationSession(manifest: manifest, model: model) {
                FileSearchView(viewModel: $0)
            }
        )
    }
}

extension FileSearchViewModel: LauncherApplicationModel {}
