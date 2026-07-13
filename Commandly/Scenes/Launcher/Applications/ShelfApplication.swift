import CommandKit

@MainActor
struct ShelfApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "shelf.board")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Shelf",
        subtitle: "Stage files and snippets on a temporary local board",
        systemImage: "square.stack.3d.up",
        category: .productivity,
        mode: .action,
        keywords: [
            "shelf",
            "staging",
            "drop",
            "clipboard",
            "board",
            "temporary",
            "files"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: "shelf.open"),
                title: "Open Shelf",
                isPrimary: true,
                keyHint: .return
            )
        ]
    )

    static let configurationFields: [LauncherConfigurationField] = [
        LauncherConfigurationField(
            id: "keep-visible",
            variable: "keepVisibleWhenInactive",
            title: "Keep shelf visible when inactive",
            description: "Leave the shelf on screen after Commandly loses focus.",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "clear-when-empty",
            variable: "clearWhenEmpty",
            title: "Close when empty",
            description: "Dismiss the shelf automatically after the last staged item leaves. Applies when staging ships.",
            kind: .toggle,
            defaultValue: .boolean(false)
        ),
        LauncherConfigurationField(
            id: "preferred-corner",
            variable: "preferredCorner",
            title: "Preferred corner",
            description: "Default placement when opening a new Shelf board.",
            kind: .selection,
            defaultValue: .text(ShelfPreferredCorner.bottomRight.rawValue),
            options: ShelfPreferredCorner.allCases.map { corner in
                LauncherConfigurationOption(
                    id: corner.rawValue,
                    title: corner.title,
                    description: "Anchor near the \(corner.title.lowercased()) of the screen."
                )
            }
        ),
        LauncherConfigurationField(
            id: "drop-sound",
            variable: "playDropSound",
            title: "Play drop sound",
            description: "Play a local macOS sound when an item is staged. Sound playback lands with staging.",
            kind: .toggle,
            defaultValue: .boolean(false)
        )
    ]

    let definition: LauncherApplicationDefinition
    private let launchController: ShelfLaunchController

    init(launchController: ShelfLaunchController = ShelfLaunchController()) {
        self.launchController = launchController
        self.definition = LauncherApplicationDefinition(
            manifest: Self.manifest,
            parentID: BuiltInLauncherApplicationGroup.catalogID,
            kind: .application,
            order: 32,
            configurationFields: Self.configurationFields,
            documentation: RegisteredApplicationDocumentation.shelf
        )
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = context
        launchController.present(.empty)
        return .dismiss
    }
}
