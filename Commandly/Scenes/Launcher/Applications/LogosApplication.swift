import CommandKit
import Infrastructure
import SwiftUI

nonisolated struct LogosApplicationServices: Sendable {
    let service: any SVGLServicing
    let favoritesStore: any LogoFavoritesStoring
    let pasteboard: any PasteboardAccessing
    let exporter: any LogoFileExporting

    static func live(pasteboard: any PasteboardAccessing) -> LogosApplicationServices {
        LogosApplicationServices(
            service: LiveSVGLService(),
            favoritesStore: UserDefaultsLogoFavoritesStore(),
            pasteboard: pasteboard,
            exporter: NativeLogoFileExporter()
        )
    }
}

/// A searchable, native catalog of community-provided SVG brand assets.
@MainActor
struct LogosApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "logos.catalog")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Logos",
        subtitle: "Search, favorite, copy, and download SVG logos",
        systemImage: "square.grid.3x3.square",
        category: .productivity,
        mode: .view,
        keywords: [
            "logo", "logos", "svg", "brand", "assets", "icons", "svgl", "download"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: LogosActionID.copySVG,
                title: "Copy Selected SVG",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: LogosActionID.download,
                title: "Download Selected SVG"
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
        order: 37,
        documentation: RegisteredApplicationDocumentation.logos
    )

    private let services: LogosApplicationServices

    init(services: LogosApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = LogosViewModel(
            service: services.service,
            favoritesStore: services.favoritesStore,
            pasteboard: services.pasteboard,
            exporter: services.exporter,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                LogosView(viewModel: $0)
            }
        )
    }
}
