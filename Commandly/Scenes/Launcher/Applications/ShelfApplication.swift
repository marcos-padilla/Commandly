import CommandKit

@MainActor
struct ShelfApplication: LauncherApplication, LauncherApplicationToolBackgroundInvoking {
    static let applicationID = CommandID(rawValue: "shelf.board")
    static let newShelfToolID = CommandID(rawValue: "shelf.new")
    static let newShelfFromClipboardToolID = CommandID(rawValue: "shelf.new-from-clipboard")

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

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.newShelfToolID,
                parentID: Self.applicationID,
                title: "New Shelf",
                subtitle: "Open an empty temporary staging board",
                systemImage: "square.stack.3d.up",
                order: 0,
                keywords: ["shelf", "new shelf", "empty", "staging", "board"],
                defaultHotKey: ShelfGlobalShortcut.newShelf.hotKey
            ),
            LauncherApplicationDefinition.tool(
                id: Self.newShelfFromClipboardToolID,
                parentID: Self.applicationID,
                title: "New Shelf from Clipboard",
                subtitle: "Stage the current clipboard on a new Shelf",
                systemImage: "clipboard",
                order: 1,
                keywords: ["shelf", "clipboard", "paste", "stage clipboard"],
                defaultHotKey: ShelfGlobalShortcut.newShelfFromClipboard.hotKey
            )
        ]
    }

    var backgroundToolIDs: Set<CommandID> {
        [Self.newShelfToolID, Self.newShelfFromClipboardToolID]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = context
        launchController.present(.empty)
        return .dismiss
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        _ = context
        guard let mode = entryMode(for: toolID) else {
            return .message("Shelf tool is unavailable.")
        }
        launchController.present(mode)
        return .dismiss
    }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        _ = arguments
        _ = settings
        guard let mode = entryMode(for: toolID) else {
            return .failure(message: "Shelf tool is unavailable.")
        }
        launchController.present(mode)
        return .success(message: nil)
    }

    private func entryMode(for toolID: CommandID) -> ShelfEntryMode? {
        switch toolID {
        case Self.newShelfToolID:
            return .empty
        case Self.newShelfFromClipboardToolID:
            return .fromClipboard
        default:
            return nil
        }
    }
}
