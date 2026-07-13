import CommandKit
import SwiftUI

@MainActor
struct WindowLayoutsApplicationServices {
    let layoutService: any WindowLayoutApplying
    let customStore: any CustomWindowLayoutStoring
}

@MainActor
struct WindowLayoutsApplication: LauncherApplication {
    static let id = CommandID(rawValue: "windows.layouts")

    private static let manifest = CommandManifest(
        id: id,
        title: "Window Layouts",
        subtitle: "Arrange the active window with 58 native presets",
        systemImage: "rectangle.3.group",
        category: .system,
        mode: .view,
        keywords: ["window", "tile", "resize", "position", "custom", "grid"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: WindowLayoutsActionID.apply,
                title: "Apply to Active Window",
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
        order: 80,
        documentation: RegisteredApplicationDocumentation.windowLayouts
    )

    private let services: WindowLayoutsApplicationServices

    init(services: WindowLayoutsApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = WindowLayoutsViewModel(
            service: services.layoutService,
            customStore: services.customStore,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                WindowLayoutsView(viewModel: $0)
            }
        )
    }
}

extension WindowLayoutsViewModel: LauncherApplicationModel {}
