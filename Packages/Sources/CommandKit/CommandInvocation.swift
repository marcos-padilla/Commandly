import Foundation

/// Supported serialized value types for command invocation arguments.
public enum CommandArgumentValueType: String, Codable, CaseIterable, Hashable, Sendable {
    /// Unicode text.
    case string
    /// A true/false value.
    case boolean
    /// A signed whole number.
    case integer
    /// A finite floating-point number.
    case decimal
    /// A URL encoded by Foundation.
    case url
    /// An ordered collection of text values.
    case stringList
}

/// A typed, persistable command argument value.
///
/// Values deliberately exclude opaque executable closures and secrets. Commands remain responsible
/// for applying domain-specific validation after the registry verifies their declared value types.
public enum CommandArgumentValue: Hashable, Sendable {
    case string(String)
    case boolean(Bool)
    case integer(Int)
    case decimal(Double)
    case url(URL)
    case stringList([String])

    /// Schema type represented by this value.
    public var valueType: CommandArgumentValueType {
        switch self {
        case .string: return .string
        case .boolean: return .boolean
        case .integer: return .integer
        case .decimal: return .decimal
        case .url: return .url
        case .stringList: return .stringList
        }
    }
}

extension CommandArgumentValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandArgumentValueType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .value))
        case .decimal:
            self = .decimal(try container.decode(Double.self, forKey: .value))
        case .url:
            self = .url(try container.decode(URL.self, forKey: .value))
        case .stringList:
            self = .stringList(try container.decode([String].self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(valueType, forKey: .type)
        switch self {
        case .string(let value): try container.encode(value, forKey: .value)
        case .boolean(let value): try container.encode(value, forKey: .value)
        case .integer(let value): try container.encode(value, forKey: .value)
        case .decimal(let value): try container.encode(value, forKey: .value)
        case .url(let value): try container.encode(value, forKey: .value)
        case .stringList(let value): try container.encode(value, forKey: .value)
        }
    }
}

/// Named typed values supplied to a command invocation.
public struct CommandArguments: Codable, Hashable, Sendable {
    /// Raw named values. Callers must not log this dictionary because arguments may be private.
    public let values: [String: CommandArgumentValue]

    /// An invocation with no arguments.
    public static let empty = CommandArguments()

    /// Creates arguments from named values.
    public init(_ values: [String: CommandArgumentValue] = [:]) {
        self.values = values
    }

    /// Returns a named value, if supplied.
    public subscript(name: String) -> CommandArgumentValue? {
        values[name]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: CommandArgumentValue].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// A persistable reference to an existing shared command and its arguments.
public struct CommandReference: Codable, Hashable, Sendable {
    /// Stable identifier resolved through the shared command catalog.
    public let commandID: CommandID
    /// Persisted invocation values validated against the command schema.
    public let arguments: CommandArguments

    /// Creates a reference to a shared command.
    public init(commandID: CommandID, arguments: CommandArguments = .empty) {
        self.commandID = commandID
        self.arguments = arguments
    }
}

/// UI or system surface that requested command execution.
public enum CommandInvocationSource: Codable, Hashable, Sendable {
    /// Commandly's search surface.
    case search
    /// A registered system-wide shortcut assigned to an application command.
    case applicationHotKey
    /// A segment in a persisted Command Wheel profile and page.
    case commandWheel(profileID: UUID, pageID: UUID, segmentID: UUID)
}

/// Non-sensitive metadata captured for one command invocation.
///
/// Command arguments, queries, paths, clipboard contents, and credentials must not be added here.
public struct CommandInvocationContext: Codable, Hashable, Sendable {
    /// Surface that initiated execution.
    public let source: CommandInvocationSource
    /// Bundle identifier active before Commandly presented its UI, when available.
    public let frontmostApplicationBundleIdentifier: String?
    /// Stable display identifier captured for the invocation, when available.
    public let screenIdentifier: String?
    /// Wall-clock time at which invocation began.
    public let timestamp: Date

    /// Creates privacy-safe metadata for an invocation.
    public init(
        source: CommandInvocationSource,
        frontmostApplicationBundleIdentifier: String? = nil,
        screenIdentifier: String? = nil,
        timestamp: Date = Date()
    ) {
        self.source = source
        self.frontmostApplicationBundleIdentifier = frontmostApplicationBundleIdentifier
        self.screenIdentifier = screenIdentifier
        self.timestamp = timestamp
    }
}
