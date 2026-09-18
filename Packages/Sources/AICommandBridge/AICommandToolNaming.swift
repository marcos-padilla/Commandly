import CommandKit
import Foundation

/// Failures raised while mapping command identifiers to provider-compatible tool names.
public enum AICommandToolNameError: Error, Equatable, Sendable {
    /// Two commands mapped to the same provider tool name.
    case collision(first: CommandID, second: CommandID)
    /// The identifier produced no usable provider name.
    case unmappable(CommandID)
}

/// Deterministic, collision-checked mapping between internal command IDs and provider tool names.
///
/// Providers accept a restricted name alphabet, so `timers.start` cannot be sent verbatim. The
/// mapping is deterministic — the same catalog always produces the same names — and keeps a reverse
/// index so an incoming tool call resolves back to exactly one internal command.
public struct AICommandToolNameMap: Sendable, Equatable {
    private let nameByCommand: [CommandID: String]
    private let commandByName: [String: CommandID]

    /// Builds a mapping for a set of commands.
    ///
    /// - Throws: ``AICommandToolNameError/collision(first:second:)`` when two commands would share
    ///   a provider name. The map is never built with an ambiguous entry.
    public init(commandIDs: [CommandID]) throws {
        var nameByCommand: [CommandID: String] = [:]
        var commandByName: [String: CommandID] = [:]
        for commandID in commandIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard nameByCommand[commandID] == nil else { continue }
            let name = Self.providerName(for: commandID)
            guard name.isEmpty == false else {
                throw AICommandToolNameError.unmappable(commandID)
            }
            if let existing = commandByName[name] {
                throw AICommandToolNameError.collision(first: existing, second: commandID)
            }
            nameByCommand[commandID] = name
            commandByName[name] = commandID
        }
        self.nameByCommand = nameByCommand
        self.commandByName = commandByName
    }

    /// Provider tool name for a command, when the command is in this map.
    public func name(for commandID: CommandID) -> String? {
        nameByCommand[commandID]
    }

    /// Internal command for a provider tool name, when the name is in this map.
    public func commandID(forToolName name: String) -> CommandID? {
        commandByName[name]
    }

    /// Number of mapped commands.
    public var count: Int { nameByCommand.count }

    /// Converts an internal identifier into the portable ASCII subset providers accept.
    ///
    /// Only `A–Z`, `a–z`, `0–9`, `_` and `-` survive; everything else becomes `_`. Length is capped
    /// at the 64 characters ``AIToolDefinition`` validates.
    static func providerName(for commandID: CommandID) -> String {
        var scalars: [Character] = []
        for character in commandID.rawValue {
            let isPortable = character.isASCII
                && (character.isLetter || character.isNumber || character == "_" || character == "-")
            scalars.append(isPortable ? character : "_")
        }
        let trimmed = String(scalars.prefix(64))
        return trimmed
    }
}
