import CommandKit
import Foundation

/// How a command reaches its effect.
public enum ModuleCommandExecutionMode: String, Sendable, Codable, CaseIterable, Equatable {
    /// Performs its work headlessly. It must not require a launcher session or window.
    case direct
    /// Presents native UI the caller must complete. It cannot finish on a caller's behalf.
    case requiresUserInterface
    /// Starts work that outlives the invocation and reports progress through an operation handle.
    case longRunning
}

/// What a command changes.
public enum ModuleCommandEffect: String, Sendable, Codable, CaseIterable, Equatable {
    /// Reads state without changing it.
    case readOnly
    /// Changes in-process or persisted application state.
    case localMutation
    /// Creates, moves, or removes files.
    case filesystemMutation
    /// Performs a network request or acts on an external account.
    case externalAction
}

/// Whether executing a command can reveal private content to a caller.
///
/// Local permission to access data, authority to mutate it, and consent to disclose it to a remote
/// provider are three separate decisions. This value covers only the third.
public enum ModuleCommandDisclosure: String, Sendable, Codable, CaseIterable, Equatable {
    /// Results contain no user content.
    case none
    /// Results contain user content that must stay on the device.
    case localPrivateContent
    /// Results may be disclosed to a remote provider only with an explicit caller grant.
    case remoteDisclosureAllowed
}

/// Whether a command may be projected as an AI tool.
///
/// The default is ``hidden``. A command becomes visible to AI only after an explicit review, which
/// is recorded by declaring ``reviewed`` in the module's own source.
public enum ModuleCommandAIExposure: String, Sendable, Codable, CaseIterable, Equatable {
    /// Never projected as an AI tool. This is the default for new and existing commands.
    case hidden
    /// Explicitly reviewed and eligible for AI projection, subject to runtime eligibility.
    case reviewed
}

/// Caller policy attached to a canonical command definition.
public struct ModuleCommandPolicy: Sendable, Hashable, Codable {
    /// How the command reaches its effect.
    public let executionMode: ModuleCommandExecutionMode
    /// What the command changes.
    public let effect: ModuleCommandEffect
    /// Whether results may be disclosed to a remote provider.
    public let disclosure: ModuleCommandDisclosure
    /// Whether the command may be projected as an AI tool.
    public let aiExposure: ModuleCommandAIExposure
    /// Whether repeating the command with identical input is safe.
    ///
    /// Non-idempotent commands must never be retried automatically.
    public let isIdempotent: Bool
    /// Whether the command requires an exact, argument-bound user approval before its effect.
    public let requiresExactApproval: Bool

    /// Creates a command policy.
    ///
    /// `aiExposure` defaults to ``ModuleCommandAIExposure/hidden`` so a command is never exposed to
    /// AI by omission.
    public init(
        executionMode: ModuleCommandExecutionMode,
        effect: ModuleCommandEffect,
        disclosure: ModuleCommandDisclosure = .none,
        aiExposure: ModuleCommandAIExposure = .hidden,
        isIdempotent: Bool = false,
        requiresExactApproval: Bool = false
    ) {
        self.executionMode = executionMode
        self.effect = effect
        self.disclosure = disclosure
        self.aiExposure = aiExposure
        self.isIdempotent = isIdempotent
        self.requiresExactApproval = requiresExactApproval
    }
}

/// The single authored definition of a module-owned command.
///
/// Launcher metadata, generated documentation, and AI tool schemas are all derived from this value.
/// Nothing may re-declare a command's description or validation rules elsewhere.
public struct ModuleCommandDefinition: Sendable, Identifiable, Equatable {
    /// Stable command identity, shared with ``CommandReference``.
    public var id: CommandID { manifest.id }
    /// Canonical launcher metadata and argument schema.
    public let manifest: CommandManifest
    /// One-sentence description of the operation, used by documentation and AI schemas.
    public let summary: String
    /// Caller policy for this command.
    public let policy: ModuleCommandPolicy

    /// Creates a canonical command definition.
    public init(manifest: CommandManifest, summary: String, policy: ModuleCommandPolicy) {
        self.manifest = manifest
        self.summary = summary
        self.policy = policy
    }
}

/// Identifier for work that outlives the invocation that started it.
public struct ModuleOperationID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates an operation identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Bounded, structured output of a completed command.
///
/// Values reuse ``CommandArgumentValue`` so outputs stay persistable and provider-safe. Raw errors,
/// UI objects, credentials, and private file paths must never be placed here.
public struct ModuleCommandOutput: Sendable, Hashable, Codable {
    /// Named output values.
    public let values: [String: CommandArgumentValue]

    /// An output carrying no values.
    public static let empty = ModuleCommandOutput()

    /// Creates a structured output.
    public init(_ values: [String: CommandArgumentValue] = [:]) {
        self.values = values
    }

    /// Returns a named output value, if present.
    public subscript(name: String) -> CommandArgumentValue? {
        values[name]
    }
}

/// Why a caller was refused.
public enum ModuleCommandDenialReason: String, Sendable, Codable, CaseIterable, Equatable {
    /// The caller lacks the grant required for this command's effect.
    case missingCallerGrant
    /// The caller lacks consent to receive this command's private content.
    case disclosureNotPermitted
    /// A required approval was absent, stale, or revoked.
    case approvalInvalid
}

/// Truthful outcome of one module command execution.
///
/// The cases are deliberately richer than ``CommandResult`` so a caller can tell "opened a draft"
/// apart from "performed the operation". ``commandResult`` projects them back onto the existing
/// three-case result so message-only consumers and persisted history stay compatible.
public enum ModuleCommandOutcome: Sendable, Hashable {
    /// The operation completed.
    case succeeded(message: String?, output: ModuleCommandOutput)
    /// The operation failed with a sanitized, user-facing message.
    case failed(message: String)
    /// The operation was cancelled before completing.
    case cancelled
    /// The caller was refused. No effect was performed.
    case denied(reason: ModuleCommandDenialReason, message: String)
    /// The command is known but cannot run right now.
    case unavailable(reason: CommandUnavailableReason, message: String)
    /// The command needs native user interaction the caller cannot perform.
    ///
    /// This is **not** success. Opening a draft or a window is reported here, never as
    /// ``succeeded``.
    case interactionRequired(message: String)
    /// Long-running work started and will continue after this invocation returns.
    case accepted(operationID: ModuleOperationID, message: String?)

    /// Projection onto the existing shared result type.
    ///
    /// Denied, unavailable, and interaction-required outcomes project to `.failure` so that privacy-
    /// safe history records them as `failed` rather than claiming a completed operation.
    public var commandResult: CommandResult {
        switch self {
        case .succeeded(let message, _):
            return .success(message: message)
        case .failed(let message):
            return .failure(message: message)
        case .cancelled:
            return .cancelled
        case .denied(_, let message):
            return .failure(message: message)
        case .unavailable(_, let message):
            return .failure(message: message)
        case .interactionRequired(let message):
            return .failure(message: message)
        case .accepted(_, let message):
            return .success(message: message)
        }
    }

    /// Whether the command's own effect was performed.
    ///
    /// ``accepted`` is `false`: starting a recording is not a completed export.
    public var didCompleteEffect: Bool {
        if case .succeeded = self { return true }
        return false
    }
}

/// Explicit authority carried by a caller, separate from the model's own arguments.
///
/// Grants are supplied by the host from trusted invocation provenance. Arguments supplied by a
/// model can never create a grant or impersonate a user-originated action.
public struct ModuleCallerGrants: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8

    /// Creates a grant set.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// A person performed this action in Commandly's own UI.
    public static let userInitiated = ModuleCallerGrants(rawValue: 1 << 0)
    /// An authorized automation caller, such as the reviewed AI bridge.
    public static let automation = ModuleCallerGrants(rawValue: 1 << 1)
    /// The caller may receive private content in the command's output.
    public static let sensitiveDisclosure = ModuleCallerGrants(rawValue: 1 << 2)
    /// The caller may cause filesystem mutations.
    public static let filesystemMutation = ModuleCallerGrants(rawValue: 1 << 3)
    /// The caller may cause external or network actions.
    public static let externalAction = ModuleCallerGrants(rawValue: 1 << 4)

    /// Grants for an action a person performed directly in Commandly.
    public static let directUser: ModuleCallerGrants = [
        .userInitiated, .sensitiveDisclosure, .filesystemMutation, .externalAction
    ]

    /// Whether these grants satisfy a command's declared policy.
    public func satisfy(_ policy: ModuleCommandPolicy) -> Bool {
        if contains(.userInitiated) == false, contains(.automation) == false {
            return false
        }
        switch policy.effect {
        case .readOnly, .localMutation:
            break
        case .filesystemMutation:
            guard contains(.filesystemMutation) else { return false }
        case .externalAction:
            guard contains(.externalAction) else { return false }
        }
        if policy.disclosure == .localPrivateContent || policy.disclosure == .remoteDisclosureAllowed {
            guard contains(.sensitiveDisclosure) else { return false }
        }
        return true
    }
}

/// One validated command invocation handed to a module handler.
public struct ModuleCommandInvocation: Sendable {
    /// Command being executed.
    public let commandID: CommandID
    /// Arguments already validated against the command's declared schema.
    public let arguments: CommandArguments
    /// Privacy-safe invocation metadata from the shared executor.
    public let context: CommandInvocationContext
    /// Authority carried by the caller.
    public let grants: ModuleCallerGrants

    /// Creates an invocation.
    public init(
        commandID: CommandID,
        arguments: CommandArguments,
        context: CommandInvocationContext,
        grants: ModuleCallerGrants
    ) {
        self.commandID = commandID
        self.arguments = arguments
        self.context = context
        self.grants = grants
    }
}

/// A module-owned operation handler.
///
/// Handlers call their module's domain services directly. They must not build SwiftUI views or
/// launcher sessions in order to perform headless work, and must not re-dispatch the UI action that
/// invoked them.
@MainActor
public protocol ModuleCommandHandling: Sendable {
    /// Performs the command and reports a truthful outcome.
    func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome
}

/// Dispatches a command reference through the application's one authoritative execution path.
///
/// Implemented by the host application over its shared command executor. Callers such as the AI
/// bridge use this instead of reaching into feature services.
@MainActor
public protocol ModuleCommandDispatching: Sendable {
    /// Resolves, authorizes, and executes a reference, returning a truthful outcome.
    func dispatch(
        reference: CommandReference,
        grants: ModuleCallerGrants,
        context: CommandInvocationContext
    ) async -> ModuleCommandOutcome
}
