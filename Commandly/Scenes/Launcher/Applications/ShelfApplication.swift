import CommandKit

@MainActor
struct ShelfApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "shelf.board")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Shelf",
        subtitle: "Stage files, folders, text, and images on a temporary local board",
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
            "files",
            "folders",
            "text",
            "images"
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
            id: "clear-when-empty",
            variable: "clearWhenEmpty",
            title: "Close when empty",
            description: "Dismiss the shelf automatically after its final staged item is removed.",
            kind: .toggle,
            defaultValue: .boolean(false)
        ),
        LauncherConfigurationField(
            id: "preferred-corner",
            variable: "preferredCorner",
            title: "Preferred corner",
            description: "Default placement on the display active when a new Shelf opens.",
            kind: .selection,
            defaultValue: .text(ShelfPreferredCorner.defaultValue.rawValue),
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
            description: "Play a local macOS sound after new content is staged.",
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
