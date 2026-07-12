import Foundation

/// Unique identifier for a command.
public struct CommandID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a command identifier.
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

/// Describes an argument a command may accept.
public struct CommandArgument: Sendable, Equatable, Codable {
    /// Argument name.
    public let name: String
    /// Human-readable description.
    public let description: String
    /// Whether the argument is required.
    public let isRequired: Bool

    /// Creates a command argument descriptor.
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

    /// Creates a command descriptor.
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

/// Outcome of a command execution attempt.
public enum CommandResult: Sendable, Equatable {
    case success(message: String?)
    case failure(message: String)
    case cancelled
}

/// Contract for executing a command. No concrete executors are provided yet.
public protocol CommandExecuting: Sendable {
    /// Executes the command identified by `id` with the provided argument values.
    func execute(id: CommandID, arguments: [String: String]) async throws -> CommandResult
}

/// Errors specific to command registration.
public enum CommandRegistryError: Error, Sendable, Equatable {
    case duplicateCommand(CommandID)
    case commandNotFound(CommandID)
}

/// In-memory registry of command descriptors.
public actor CommandRegistry {
    private var descriptors: [CommandID: CommandDescriptor] = [:]

    /// Creates an empty registry.
    public init() {}

    /// Registers a command descriptor.
    /// - Throws: ``CommandRegistryError/duplicateCommand(_:)`` when the ID already exists.
    public func register(_ descriptor: CommandDescriptor) throws {
        if descriptors[descriptor.id] != nil {
            throw CommandRegistryError.duplicateCommand(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    /// Returns a registered descriptor, if present.
    public func descriptor(for id: CommandID) -> CommandDescriptor? {
        descriptors[id]
    }

    /// Returns all registered descriptors sorted by title.
    public func allDescriptors() -> [CommandDescriptor] {
        descriptors.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Number of registered commands.
    public var count: Int {
        descriptors.count
    }
}
