import CommandKit
import SwiftUI

enum SystemActivityApplicationID {
    static let command = CommandID(rawValue: "system.activity")
}

@MainActor
struct SystemActivityApplication: LauncherApplication {
    private static let manifest = CommandManifest(
        id: SystemActivityApplicationID.command,
        title: "System Activity",
        subtitle: "Monitor this Mac and manage running applications",
        systemImage: "gauge.with.dots.needle.67percent",
        category: .system,
        mode: .view,
        keywords: [
            "activity", "cpu", "memory", "storage", "thermal", "process",
            "applications", "switch", "quit", "force quit", "uptime"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: SystemActivityActionID.refresh,
                title: "Refresh",
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
        order: 45
    )

    private let service: any SystemActivityServicing

    init(service: any SystemActivityServicing = NativeSystemActivityService()) {
        self.service = service
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = SystemActivityViewModel(
            service: service,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                SystemActivityView(viewModel: $0)
            }
        )
    }
}

extension SystemActivityViewModel: LauncherApplicationModel {}
