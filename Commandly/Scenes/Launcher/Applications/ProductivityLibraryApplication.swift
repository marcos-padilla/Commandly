import CommandKit
import SwiftUI

/// Registered local-first library for snippets, notes, Quicklinks, and emoji keywords.
@MainActor
struct ProductivityLibraryApplication: LauncherApplication {
    static let id = CommandID(rawValue: "productivity.library")

    private static let manifest = CommandManifest(
        id: id,
        title: "Productivity Library",
        subtitle: "Snippets, quick notes, Quicklinks, and emoji keywords",
        systemImage: "books.vertical",
        category: .productivity,
        mode: .view,
        keywords: [
            "snippet", "note", "quicklink", "bookmark", "emoji", "text", "clipboard"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.useSelected,
                title: "Use Item",
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

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 40,
        documentation: RegisteredApplicationDocumentation.productivityLibrary
    )

    private let services: ProductivityLibraryApplicationServices

    init(services: ProductivityLibraryApplicationServices = .live) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = ProductivityLibraryViewModel(
            services: services,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                ProductivityLibraryView(viewModel: $0)
            }
        )
    }
}
