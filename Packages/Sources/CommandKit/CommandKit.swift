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
public struct CommandArgument: Sendable, Equatable, Hashable, Codable {
    public let name: String
    public let description: String
    public let isRequired: Bool
    /// Runtime value type accepted for this argument.
    public let valueType: CommandArgumentValueType
    /// Value used when a reference omits this argument.
    public let defaultValue: CommandArgumentValue?

    public init(
        name: String,
        description: String,
        isRequired: Bool,
        valueType: CommandArgumentValueType = .string,
        defaultValue: CommandArgumentValue? = nil
    ) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
        self.valueType = valueType
        self.defaultValue = defaultValue
    }
}

/// Descriptive metadata for a command. Does not execute anything.
public struct CommandDescriptor: Sendable, Equatable, Hashable, Identifiable {
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
public struct CommandManifest: Sendable, Equatable, Hashable, Identifiable {
    public let id: CommandID
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let category: CommandCategory
    public let mode: CommandMode
    public let keywords: [String]
    /// Serializable invocation argument schema shared by every presentation surface.
    public let arguments: [CommandArgument]
    /// Non-secret capabilities that must be available before the command can execute.
    public let availabilityRequirements: [CommandAvailabilityRequirement]
    public let badgeTitle: String
    /// Default footer actions when the command surface first appears.
    public let defaultActions: [CommandActionDescriptor]

    public var descriptor: CommandDescriptor {
        CommandDescriptor(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            keywords: keywords,
            arguments: arguments
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
        arguments: [CommandArgument] = [],
        availabilityRequirements: [CommandAvailabilityRequirement] = [],
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
        self.arguments = arguments
        self.availabilityRequirements = availabilityRequirements
        self.badgeTitle = badgeTitle
        self.defaultActions = defaultActions
    }
}

/// A declarative, non-secret requirement evaluated by the application availability service.
public enum CommandAvailabilityRequirement: Sendable, Equatable, Hashable {
    /// A permission identified by the owning platform permission service.
    case permission(identifier: String)
}

/// Errors specific to command registration.
public enum CommandRegistryError: Error, Sendable, Equatable {
    case duplicateCommand(CommandID)
    case commandNotFound(CommandID)
    case duplicateArgument(commandID: CommandID, name: String)
    case invalidDefaultValue(
        commandID: CommandID,
        name: String,
        expected: CommandArgumentValueType,
        actual: CommandArgumentValueType
    )
    /// A decimal argument cannot be persisted because it is NaN or infinite.
    case nonFiniteDecimal(commandID: CommandID, name: String)
    case missingRequiredArgument(commandID: CommandID, name: String)
    case unknownArgument(commandID: CommandID, name: String)
    case invalidArgumentType(
        commandID: CommandID,
        name: String,
        expected: CommandArgumentValueType,
        actual: CommandArgumentValueType
    )
}

/// In-memory registry of command manifests and legacy descriptors.
public actor CommandRegistry {
    private var manifests: [CommandID: CommandManifest] = [:]
    private var availabilitySnapshot: CommandAvailabilitySnapshot = .allAvailable

    public init() {}

    /// Registers a full command manifest.
    public func register(_ manifest: CommandManifest) throws {
        if manifests[manifest.id] != nil {
            throw CommandRegistryError.duplicateCommand(manifest.id)
        }
        try Self.validateSchema(of: manifest)
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
            arguments: descriptor.arguments,
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
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return $0.id.rawValue < $1.id.rawValue
        }
    }

    public func allDescriptors() -> [CommandDescriptor] {
        allManifests().map(\.descriptor)
    }

    public var count: Int {
        manifests.count
    }

    /// Atomically replaces the complete metadata catalog after validating every entry.
    ///
    /// If validation fails, the previous catalog remains unchanged.
    public func replaceCatalog(with newManifests: [CommandManifest]) throws {
        try replaceCatalog(with: newManifests, availability: .allAvailable)
    }

    /// Atomically replaces metadata and availability from the same evaluated generation.
    ///
    /// If validation fails, both parts of the previous catalog remain unchanged.
    public func replaceCatalog(
        with newManifests: [CommandManifest],
        availability: CommandAvailabilitySnapshot
    ) throws {
        var replacement: [CommandID: CommandManifest] = [:]
        for manifest in newManifests {
            guard replacement[manifest.id] == nil else {
                throw CommandRegistryError.duplicateCommand(manifest.id)
            }
            try Self.validateSchema(of: manifest)
            replacement[manifest.id] = manifest
        }
        manifests = replacement
        availabilitySnapshot = availability
    }

    /// Returns one immutable generation for presentation surfaces such as Settings.
    public func catalogSnapshot() -> CommandCatalogSnapshot {
        CommandCatalogSnapshot(
            manifests: allManifests(),
            availability: availabilitySnapshot
        )
    }

    /// Resolves and validates a persisted command reference against the current catalog.
    public func resolve(reference: CommandReference) async throws -> ResolvedCommand {
        guard let manifest = manifests[reference.commandID] else {
            throw CommandRegistryError.commandNotFound(reference.commandID)
        }

        let schemaByName = Dictionary(uniqueKeysWithValues: manifest.arguments.map { ($0.name, $0) })
        for name in reference.arguments.values.keys.sorted() where schemaByName[name] == nil {
            throw CommandRegistryError.unknownArgument(commandID: manifest.id, name: name)
        }

        var normalizedValues = reference.arguments.values
        for argument in manifest.arguments {
            if let value = normalizedValues[argument.name] {
                guard value.valueType == argument.valueType else {
                    throw CommandRegistryError.invalidArgumentType(
                        commandID: manifest.id,
                        name: argument.name,
                        expected: argument.valueType,
                        actual: value.valueType
                    )
                }
                try Self.validatePersistable(
                    value,
                    commandID: manifest.id,
                    argumentName: argument.name
                )
            } else if let defaultValue = argument.defaultValue {
                normalizedValues[argument.name] = defaultValue
            } else if argument.isRequired {
                throw CommandRegistryError.missingRequiredArgument(
                    commandID: manifest.id,
                    name: argument.name
                )
            }
        }

        let normalizedReference = CommandReference(
            commandID: reference.commandID,
            arguments: CommandArguments(normalizedValues)
        )
        return ResolvedCommand(
            reference: normalizedReference,
            manifest: manifest,
            availability: availabilitySnapshot.availability(for: normalizedReference)
        )
    }

    private static func validateSchema(of manifest: CommandManifest) throws {
        var names: Set<String> = []
        for argument in manifest.arguments {
            guard names.insert(argument.name).inserted else {
                throw CommandRegistryError.duplicateArgument(
                    commandID: manifest.id,
                    name: argument.name
                )
            }
            if let defaultValue = argument.defaultValue,
               defaultValue.valueType != argument.valueType {
                throw CommandRegistryError.invalidDefaultValue(
                    commandID: manifest.id,
                    name: argument.name,
                    expected: argument.valueType,
                    actual: defaultValue.valueType
                )
            }
            if let defaultValue = argument.defaultValue {
                try validatePersistable(
                    defaultValue,
                    commandID: manifest.id,
                    argumentName: argument.name
                )
            }
        }
    }

    private static func validatePersistable(
        _ value: CommandArgumentValue,
        commandID: CommandID,
        argumentName: String
    ) throws {
        guard case .decimal(let decimal) = value, decimal.isFinite == false else { return }
        throw CommandRegistryError.nonFiniteDecimal(
            commandID: commandID,
            name: argumentName
        )
    }
}

extension CommandRegistry: CommandResolving {}

/// Well-known built-in command identifiers.
public enum BuiltInCommandID {
    public static let clipboardHistory = CommandID(rawValue: "clipboard.history")
    public static let searchFiles = CommandID(rawValue: "files.search")
    public static let openSettings = CommandID(rawValue: "settings.open")
    /// Opens an installed macOS application supplied by bundle identifier.
    public static let openInstalledApplication = CommandID(rawValue: "applications.open-installed")
}

/// Well-known argument names used by shared built-in commands.
public enum BuiltInCommandArgumentName {
    /// Bundle identifier accepted by ``BuiltInCommandID/openInstalledApplication``.
    public static let bundleIdentifier = "bundleIdentifier"
}

/// Reusable built-in command manifests that are not launcher application surfaces.
public enum BuiltInCommandManifest {
    /// Parameterized installed-application command shared by search, shortcuts, and Command Wheel.
    public static let openInstalledApplication = CommandManifest(
        id: BuiltInCommandID.openInstalledApplication,
        title: "Open Installed Application",
        subtitle: "Open a macOS application by bundle identifier",
        systemImage: "app.fill",
        category: .application,
        mode: .action,
        keywords: ["application", "launch", "open"],
        arguments: [
            CommandArgument(
                name: BuiltInCommandArgumentName.bundleIdentifier,
                description: "The installed application's bundle identifier.",
                isRequired: true,
                valueType: .string
            )
        ],
        badgeTitle: "Application"
    )
}

/// Factories for references to shared built-in commands.
public enum BuiltInCommandReference {
    /// Creates a reference that opens the installed application with `bundleIdentifier`.
    public static func openInstalledApplication(bundleIdentifier: String) -> CommandReference {
        CommandReference(
            commandID: BuiltInCommandID.openInstalledApplication,
            arguments: CommandArguments([
                BuiltInCommandArgumentName.bundleIdentifier: .string(bundleIdentifier)
            ])
        )
    }
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
