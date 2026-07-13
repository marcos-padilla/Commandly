import Foundation

/// Unique identifier for a command.
public struct CommandID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a command identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Unique identifier for a command action (footer / ⌘K menu).
public struct CommandActionID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// High-level grouping for commands.
public enum CommandCategory: String, Sendable, Codable, CaseIterable, Equatable {
    case application
    case navigation
    case system
    case productivity
    case experimental
}

/// How a command is presented when selected from the launcher.
public enum CommandMode: String, Sendable, Codable, Equatable {
    /// Runs immediately without pushing a nested surface.
    case action
    /// Pushes a command-owned surface (search, list, preview, actions).
    case view
}

/// Display-only keyboard hint for footer chrome.
public struct CommandKeyHint: Sendable, Equatable, Hashable {
    public let symbols: [String]

    public init(symbols: [String]) {
        self.symbols = symbols
    }

    public static let `return` = CommandKeyHint(symbols: ["↩"])
    public static let escape = CommandKeyHint(symbols: ["Esc"])
    public static let commandK = CommandKeyHint(symbols: ["⌘", "K"])
}

/// An action exposed by a command surface (primary footer button or Actions menu).
public struct CommandActionDescriptor: Sendable, Equatable, Identifiable, Hashable {
    public let id: CommandActionID
    public let title: String
    public let isPrimary: Bool
    public let keyHint: CommandKeyHint?
    public let isEnabled: Bool

    public init(
        id: CommandActionID,
        title: String,
        isPrimary: Bool = false,
        keyHint: CommandKeyHint? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
        self.keyHint = keyHint
        self.isEnabled = isEnabled
    }
}

/// Describes an argument a command may accept.
public struct CommandArgument: Sendable, Equatable, Codable {
    public let name: String
    public let description: String
    public let isRequired: Bool

    public init(name: String, description: String, isRequired: Bool) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
    }
}

/// Descriptive metadata for a command. Does not execute anything.
public struct CommandDescriptor: Sendable, Equatable, Identifiable {
    public let id: CommandID
    public let title: String
    public let subtitle: String?
    public let category: CommandCategory
    public let keywords: [String]
    public let arguments: [CommandArgument]

    public init(
        id: CommandID,
        title: String,
        subtitle: String? = nil,
        category: CommandCategory,
        keywords: [String] = [],
        arguments: [CommandArgument] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.keywords = keywords
        self.arguments = arguments
    }
}

/// Full registration payload for a launcher command (metadata + presentation mode).
public struct CommandManifest: Sendable, Equatable, Identifiable {
    public let id: CommandID
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let category: CommandCategory
    public let mode: CommandMode
    public let keywords: [String]
    public let badgeTitle: String
    /// Default footer actions when the command surface first appears.
    public let defaultActions: [CommandActionDescriptor]

    public var descriptor: CommandDescriptor {
        CommandDescriptor(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            keywords: keywords
        )
    }

    public init(
        id: CommandID,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        category: CommandCategory,
        mode: CommandMode,
        keywords: [String] = [],
        badgeTitle: String = "Command",
        defaultActions: [CommandActionDescriptor] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.mode = mode
        self.keywords = keywords
        self.badgeTitle = badgeTitle
        self.defaultActions = defaultActions
    }
}

/// Outcome of a command execution attempt.
public enum CommandResult: Sendable, Equatable {
    case success(message: String?)
    case failure(message: String)
    case cancelled
}

/// Contract for executing a command. No concrete executors are provided yet.
public protocol CommandExecuting: Sendable {
    func execute(id: CommandID, arguments: [String: String]) async throws -> CommandResult
}

/// Errors specific to command registration.
public enum CommandRegistryError: Error, Sendable, Equatable {
    case duplicateCommand(CommandID)
    case commandNotFound(CommandID)
}

/// In-memory registry of command manifests and legacy descriptors.
public actor CommandRegistry {
    private var manifests: [CommandID: CommandManifest] = [:]

    public init() {}

    /// Registers a full command manifest.
    public func register(_ manifest: CommandManifest) throws {
        if manifests[manifest.id] != nil {
            throw CommandRegistryError.duplicateCommand(manifest.id)
        }
        manifests[manifest.id] = manifest
    }

    /// Registers a legacy descriptor as an action-mode manifest without chrome defaults.
    public func register(_ descriptor: CommandDescriptor) throws {
        let manifest = CommandManifest(
            id: descriptor.id,
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            systemImage: "command",
            category: descriptor.category,
            mode: .action,
            keywords: descriptor.keywords,
            badgeTitle: "Command",
            defaultActions: []
        )
        try register(manifest)
    }

    public func manifest(for id: CommandID) -> CommandManifest? {
        manifests[id]
    }

    public func descriptor(for id: CommandID) -> CommandDescriptor? {
        manifests[id]?.descriptor
    }

    public func allManifests() -> [CommandManifest] {
        manifests.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    public func allDescriptors() -> [CommandDescriptor] {
        allManifests().map(\.descriptor)
    }

    public var count: Int {
        manifests.count
    }
}

/// Well-known built-in command identifiers.
public enum BuiltInCommandID {
    public static let clipboardHistory = CommandID(rawValue: "clipboard.history")
    public static let searchFiles = CommandID(rawValue: "files.search")
    public static let openSettings = CommandID(rawValue: "settings.open")
}

/// Well-known action identifiers shared across surfaces.
public enum BuiltInCommandActionID {
    public static let copy = CommandActionID(rawValue: "copy")
    public static let delete = CommandActionID(rawValue: "delete")
    public static let clearHistory = CommandActionID(rawValue: "clear-history")
    public static let openActions = CommandActionID(rawValue: "open-actions")
    public static let goBack = CommandActionID(rawValue: "go-back")
    public static let documentation = CommandActionID(rawValue: "documentation")
    public static let settings = CommandActionID(rawValue: "settings")
    public static let quit = CommandActionID(rawValue: "quit")
    public static let openApplication = CommandActionID(rawValue: "app.open")
    public static let showInFinder = CommandActionID(rawValue: "app.show-in-finder")
    public static let showInfoInFinder = CommandActionID(rawValue: "app.show-info")
    public static let showPackageContents = CommandActionID(rawValue: "app.package-contents")
    public static let toggleFavorite = CommandActionID(rawValue: "app.toggle-favorite")
    public static let copyAppName = CommandActionID(rawValue: "app.copy-name")
    public static let copyAppPath = CommandActionID(rawValue: "app.copy-path")
    public static let copyBundleIdentifier = CommandActionID(rawValue: "app.copy-bundle-id")
    public static let toggleAutoQuit = CommandActionID(rawValue: "app.toggle-auto-quit")
    public static let toggleDisableApplication = CommandActionID(rawValue: "app.toggle-disable")
    public static let uninstallApplication = CommandActionID(rawValue: "app.uninstall")
    public static let resetAppRanking = CommandActionID(rawValue: "app.reset-ranking")
    public static let openFile = CommandActionID(rawValue: "file.open")
    public static let revealFile = CommandActionID(rawValue: "file.reveal")
    public static let copyFilePath = CommandActionID(rawValue: "file.copy-path")
    public static let openFileWith = CommandActionID(rawValue: "file.open-with")
    public static let showFileInfo = CommandActionID(rawValue: "file.show-info")
    public static let openEnclosingFolder = CommandActionID(rawValue: "file.enclosing-folder")
    public static let toggleFileDetails = CommandActionID(rawValue: "file.toggle-details")
    public static let shareFile = CommandActionID(rawValue: "file.share")
    public static let moveFile = CommandActionID(rawValue: "file.move")
    public static let copyFileTo = CommandActionID(rawValue: "file.copy-to")
    public static let duplicateFile = CommandActionID(rawValue: "file.duplicate")
    public static let createFileShortcut = CommandActionID(rawValue: "file.create-shortcut")
    public static let copyFile = CommandActionID(rawValue: "file.copy")
    public static let copyFileName = CommandActionID(rawValue: "file.copy-name")
    public static let trashFile = CommandActionID(rawValue: "file.trash")
}
