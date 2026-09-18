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
    static let openToolID = CommandID(rawValue: "downloads.recent.tool.open")
    static let openNewestToolID = CommandID(rawValue: "downloads.open-newest")
    static let copyNewestToolID = CommandID(rawValue: "downloads.copy-newest")

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
        order: 35,
        documentation: RegisteredApplicationDocumentation.downloads
    )

    private let services: DownloadsApplicationServices

    init(services: DownloadsApplicationServices) {
        self.services = services
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.openToolID,
                parentID: Self.applicationID,
                title: "Open Recent Downloads",
                subtitle: "Browse the newest top-level files in Downloads",
                systemImage: "arrow.down.circle",
                keywords: ["open", "downloads", "latest", "recent", "files"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.openNewestToolID,
                parentID: Self.applicationID,
                title: "Open Newest Download",
                subtitle: "Open the most recent available download",
                systemImage: "arrow.up.forward.app",
                order: 1,
                keywords: ["open newest", "latest download", "recent file"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.copyNewestToolID,
                parentID: Self.applicationID,
                title: "Copy Newest Download",
                subtitle: "Copy the most recent download as a file URL",
                systemImage: "doc.on.doc",
                order: 2,
                keywords: ["copy newest", "latest download", "clipboard", "recent file"]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(initialAction: nil, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID:
            return makeLaunch(initialAction: nil, context: context)
        case Self.openNewestToolID:
            return makeLaunch(initialAction: .openNewest, context: context)
        case Self.copyNewestToolID:
            return makeLaunch(initialAction: .copyNewest, context: context)
        default:
            return .message("Recent Downloads tool is unavailable.")
        }
    }

    private func makeLaunch(
        initialAction: DownloadsInitialAction?,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let model = DownloadsViewModel(
            provider: services.provider,
            urlOpener: services.urlOpener,
            fileRevealer: services.fileRevealer,
            pasteboard: services.pasteboard,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher,
            initialAction: initialAction
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                DownloadsView(viewModel: $0)
            }
        )
    }
}

extension DownloadsViewModel: LauncherApplicationModel {}
