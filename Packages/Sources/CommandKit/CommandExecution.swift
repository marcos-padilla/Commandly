import Foundation

/// Why a known command cannot run in the current invocation context.
public enum CommandUnavailableReason: Codable, Hashable, Sendable {
    /// The user or an inherited setting disabled the command.
    case disabled
    /// A named, non-secret permission is missing.
    case missingPermission(identifier: String)
    /// A named runtime service or extension is not present.
    case missingDependency(identifier: String)
    /// The invocation does not provide the context required by the command.
    case invalidContext
    /// A transient condition currently prevents execution.
    case temporarilyUnavailable
    /// The current platform or command implementation cannot perform the action.
    case unsupported
}

/// Availability determined while resolving a command for an invocation surface.
public enum CommandAvailability: Codable, Hashable, Sendable {
    /// The command may be submitted to the executor.
    case available
    /// The command is known but cannot currently execute.
    case unavailable(CommandUnavailableReason)

    /// Whether execution may proceed.
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// Immutable availability facts captured for one command-catalog generation.
///
/// Command-level failures cover settings and permission state. Installed-application
/// availability is reference-aware because one parameterized manifest can point at many bundle
/// identifiers. A `nil` installed-application set preserves the all-available behavior used by
/// registries that have not installed a production snapshot.
public struct CommandAvailabilitySnapshot: Equatable, Sendable {
    /// Availability overrides for known command identifiers.
    public let commandAvailability: [CommandID: CommandAvailability]
    /// Normalized bundle identifiers currently available through the installed-app command.
    public let installedApplicationBundleIdentifiers: Set<String>?

    /// Creates a catalog availability snapshot.
    public init(
        commandAvailability: [CommandID: CommandAvailability] = [:],
        installedApplicationBundleIdentifiers: Set<String>? = nil
    ) {
        self.commandAvailability = commandAvailability
        self.installedApplicationBundleIdentifiers = installedApplicationBundleIdentifiers.map {
            Set($0.map(Self.normalizedBundleIdentifier))
        }
    }

    /// Default snapshot for standalone registries and tests without a production evaluator.
    public static let allAvailable = CommandAvailabilitySnapshot()

    /// Returns current availability for a validated, normalized reference.
    public func availability(for reference: CommandReference) -> CommandAvailability {
        if let availability = commandAvailability[reference.commandID],
           availability.isAvailable == false {
            return availability
        }

        guard reference.commandID == BuiltInCommandID.openInstalledApplication,
              let installedApplicationBundleIdentifiers else {
            return commandAvailability[reference.commandID] ?? .available
        }
        guard case .string(let bundleIdentifier)? = reference.arguments[
            BuiltInCommandArgumentName.bundleIdentifier
        ] else {
            return .unavailable(.invalidContext)
        }
        let normalized = Self.normalizedBundleIdentifier(bundleIdentifier)
        guard normalized.isEmpty == false,
              bundleIdentifier
                == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .unavailable(.invalidContext)
        }
        return installedApplicationBundleIdentifiers.contains(normalized)
            ? .available
            : .unavailable(.missingDependency(identifier: "installed-application"))
    }

    private static func normalizedBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// One atomic generation of known command metadata and its availability facts.
public struct CommandCatalogSnapshot: Equatable, Sendable {
    /// Known manifests, including commands that are currently unavailable.
    public let manifests: [CommandManifest]
    /// Availability facts evaluated for the same catalog generation.
    public let availability: CommandAvailabilitySnapshot

    /// Creates an immutable catalog snapshot.
    public init(
        manifests: [CommandManifest],
        availability: CommandAvailabilitySnapshot = .allAvailable
    ) {
        self.manifests = manifests
        self.availability = availability
    }
}

/// A validated command reference paired with its current manifest and availability.
public struct ResolvedCommand: Hashable, Sendable {
    /// Normalized reference, including any schema defaults.
    public let reference: CommandReference
    /// Current catalog metadata.
    public let manifest: CommandManifest
    /// Availability evaluated by the resolver.
    public let availability: CommandAvailability

    /// Creates a resolved command from validated metadata.
    public init(
        reference: CommandReference,
        manifest: CommandManifest,
        availability: CommandAvailability = .available
    ) {
        self.reference = reference
        self.manifest = manifest
        self.availability = availability
    }
}

/// Resolves persisted references into validated commands without executing them.
public protocol CommandResolving: Sendable {
    /// Resolves and validates a reference without executing it.
    func resolve(reference: CommandReference) async throws -> ResolvedCommand
}

/// User-facing outcome of a command execution attempt.
public enum CommandResult: Codable, Hashable, Sendable {
    /// Execution completed successfully, optionally with a user-facing message.
    case success(message: String?)
    /// Execution completed with a sanitized user-facing failure message.
    case failure(message: String)
    /// Execution was intentionally cancelled before success.
    case cancelled

    /// Privacy-safe outcome category suitable for usage history and logging.
    public var executionOutcome: CommandExecutionOutcome {
        switch self {
        case .success: return .succeeded
        case .failure: return .failed
        case .cancelled: return .cancelled
        }
    }
}

/// Executes a previously resolved command through the shared engine.
public protocol CommandExecuting: Sendable {
    /// Executes a validated command with privacy-safe invocation metadata.
    func execute(
        _ command: ResolvedCommand,
        context: CommandInvocationContext
    ) async throws -> CommandResult
}

/// Privacy-safe classification of an execution result.
public enum CommandExecutionOutcome: String, Codable, CaseIterable, Hashable, Sendable {
    /// Command completed successfully.
    case succeeded
    /// Command failed or was rejected.
    case failed
    /// Command was cancelled.
    case cancelled
}

/// Non-sensitive history record for one completed command execution.
public struct CommandExecutionRecord: Codable, Hashable, Identifiable, Sendable {
    /// Idempotency identifier for this completed execution.
    public let id: UUID
    /// Stable identifier of the executed command. Arguments are deliberately excluded.
    public let commandID: CommandID
    /// Surface that initiated the execution.
    public let source: CommandInvocationSource
    /// Privacy-safe completion category.
    public let outcome: CommandExecutionOutcome
    /// Wall-clock completion timestamp.
    public let timestamp: Date

    /// Creates a privacy-safe execution record.
    public init(
        id: UUID = UUID(),
        commandID: CommandID,
        source: CommandInvocationSource,
        outcome: CommandExecutionOutcome,
        timestamp: Date
    ) {
        self.id = id
        self.commandID = commandID
        self.source = source
        self.outcome = outcome
        self.timestamp = timestamp
    }
}
