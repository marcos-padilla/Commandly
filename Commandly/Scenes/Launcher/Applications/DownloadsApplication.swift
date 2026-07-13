import CommandKit
import Infrastructure
import SwiftUI

nonisolated struct DownloadsApplicationServices: Sendable {
    let provider: any RecentDownloadsProviding
    let urlOpener: any URLOpening
    let fileRevealer: any FileRevealing
    let pasteboard: any PasteboardAccessing

    init(
        provider: any RecentDownloadsProviding,
        urlOpener: any URLOpening,
        fileRevealer: any FileRevealing,
        pasteboard: any PasteboardAccessing
    ) {
        self.provider = provider
        self.urlOpener = urlOpener
        self.fileRevealer = fileRevealer
        self.pasteboard = pasteboard
    }
}

@MainActor
struct DownloadsApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "downloads.recent")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Recent Downloads",
        subtitle: "Open, reveal, and copy your latest files",
        systemImage: "arrow.down.circle",
        category: .productivity,
        mode: .view,
        keywords: ["downloads", "latest", "recent", "files", "finder", "open", "copy"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: "Open Newest Download",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copyFile,
                title: "Copy Newest Download"
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 35
    )

    private let services: DownloadsApplicationServices

    init(services: DownloadsApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = DownloadsViewModel(
            provider: services.provider,
            urlOpener: services.urlOpener,
            fileRevealer: services.fileRevealer,
            pasteboard: services.pasteboard,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                DownloadsView(viewModel: $0)
            }
        )
    }
}

extension DownloadsViewModel: LauncherApplicationModel {}
