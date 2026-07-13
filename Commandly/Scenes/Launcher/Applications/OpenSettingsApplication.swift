import CommandKit

@MainActor
struct OpenSettingsApplication: LauncherApplication {
    let manifest = CommandManifest(
        id: BuiltInCommandID.openSettings,
        title: "Open Settings",
        subtitle: "Preferences, permissions, and about",
        systemImage: "gearshape",
        category: .navigation,
        mode: .action,
        keywords: ["preferences", "general"],
        badgeTitle: "Settings",
        defaultActions: [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: "open"),
                title: "Open Settings",
                isPrimary: true,
                keyHint: .return
            )
        ]
    )

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        .openSettings
    }
}
