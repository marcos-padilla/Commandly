import CommandKit
import Foundation
import ModuleKit

/// Why a start request was rejected before any timer was created.
public enum TimerStartValidationError: Error, Equatable, Sendable {
    /// The duration argument was missing or was not a whole number.
    case missingDuration
    /// The duration is outside ``TimersDurationBounds``.
    case durationOutOfRange
    /// The supplied title was not text.
    case invalidTitle

    /// Sanitized, user-facing message. Carries no caller-supplied content.
    public var userFacingMessage: String {
        switch self {
        case .missingDuration:
            return "A timer needs a duration in seconds."
        case .durationOutOfRange:
            return "Timer duration must be between 1 second and 24 hours."
        case .invalidTitle:
            return "That timer name isn’t valid."
        }
    }
}

/// A validated request to start a countdown.
public struct TimerStartRequest: Equatable, Sendable {
    /// Countdown length in whole seconds, already bounds-checked.
    public let durationSeconds: Int
    /// Countdown name, already trimmed. Empty means "use the default name".
    public let title: String

    /// Creates a validated request.
    ///
    /// Prefer ``TimerStartRequest/validate(arguments:)`` when the input came from a command
    /// reference or an AI tool call.
    public init(durationSeconds: Int, title: String) {
        self.durationSeconds = durationSeconds
        self.title = title
    }

    /// Validates raw command arguments into a start request.
    ///
    /// Validation happens before any timer is created, so a rejected request has no effect.
    public static func validate(
        arguments: CommandArguments
    ) throws -> TimerStartRequest {
        guard case .integer(let seconds)? = arguments[
            TimersCommandArgumentName.durationSeconds
        ] else {
            throw TimerStartValidationError.missingDuration
        }
        guard seconds >= TimersDurationBounds.minimumSeconds,
              seconds <= TimersDurationBounds.maximumSeconds else {
            throw TimerStartValidationError.durationOutOfRange
        }

        var title = ""
        if let rawTitle = arguments[TimersCommandArgumentName.title] {
            guard case .string(let text) = rawTitle else {
                throw TimerStartValidationError.invalidTitle
            }
            title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return TimerStartRequest(durationSeconds: seconds, title: title)
    }
}

/// A started countdown, described well enough for a caller to report it truthfully.
public struct StartedTimer: Equatable, Sendable {
    /// Stable identifier of the created timer.
    public let id: UUID
    /// Resolved timer name.
    public let title: String
    /// Countdown length in whole seconds.
    public let durationSeconds: Int
    /// Current phase.
    public let phase: CountdownTimerPhase
    /// Instant at which the countdown reaches zero.
    public let endsAt: Date

    /// Creates a started-timer description.
    public init(
        id: UUID,
        title: String,
        durationSeconds: Int,
        phase: CountdownTimerPhase,
        endsAt: Date
    ) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.phase = phase
        self.endsAt = endsAt
    }
}

/// The module's one timer-starting operation.
///
/// Both the Timers UI's own start action and the `timers.start` command go through this type, so
/// there is a single implementation of "start a countdown". It performs no presentation: the
/// countdown continues after the launcher is dismissed because ``TimerStore`` owns its own ticking.
@MainActor
public struct TimerOperations {
    private let store: TimerStore

    /// Creates operations bound to a timer store.
    public init(store: TimerStore) {
        self.store = store
    }

    /// Starts a countdown from a validated request.
    ///
    /// - Returns: the created timer, including the instant it ends.
    public func start(_ request: TimerStartRequest) -> StartedTimer {
        let id = store.createTimer(
            name: request.title,
            duration: TimeInterval(request.durationSeconds),
            startsImmediately: true
        )
        let created = store.timer(id: id)
        let remaining = store.remainingTime(for: id) ?? TimeInterval(request.durationSeconds)
        return StartedTimer(
            id: id,
            title: created?.name ?? (request.title.isEmpty ? "Timer" : request.title),
            durationSeconds: request.durationSeconds,
            phase: created?.phase ?? .running,
            endsAt: store.displayDate.addingTimeInterval(remaining)
        )
    }
}

/// Handler for ``TimersModuleIdentifiers/startTool``.
///
/// It calls ``TimerOperations`` directly. It never constructs a view or a launcher session, so the
/// command works headlessly from search, a shortcut, the Command Wheel, the menu bar, or the AI
/// bridge.
@MainActor
public struct StartTimerCommandHandler: ModuleCommandHandling {
    private let operations: TimerOperations
    private let formatter: ISO8601DateFormatter

    /// Creates a start handler.
    public init(operations: TimerOperations) {
        self.operations = operations
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.formatter = formatter
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(TimersCommands.start.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to start timers."
            )
        }

        let request: TimerStartRequest
        do {
            request = try TimerStartRequest.validate(arguments: invocation.arguments)
        } catch let error as TimerStartValidationError {
            return .failed(message: error.userFacingMessage)
        } catch {
            return .failed(message: "That timer request isn’t valid.")
        }

        let started = operations.start(request)
        return .succeeded(
            message: "Started “\(started.title)”.",
            output: ModuleCommandOutput([
                TimersCommandOutputName.timerID: .string(started.id.uuidString),
                TimersCommandOutputName.title: .string(started.title),
                TimersCommandOutputName.durationSeconds: .integer(started.durationSeconds),
                TimersCommandOutputName.phase: .string(started.phase.rawValue),
                TimersCommandOutputName.endsAt: .string(formatter.string(from: started.endsAt))
            ])
        )
    }
}

/// Handler for the module's presentation commands.
///
/// These commands open native UI. The handler reports ``ModuleCommandOutcome/interactionRequired``
/// rather than claiming success, so an automation caller is never told a countdown was started when
/// only a draft was opened. The launcher shell presents these commands through its own session
/// path; this handler exists so that a non-interactive caller receives a truthful answer.
@MainActor
public struct TimersPresentationCommandHandler: ModuleCommandHandling {
    /// Creates a presentation handler.
    public init() {}

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        switch invocation.commandID {
        case TimersModuleIdentifiers.newTimerTool:
            return .interactionRequired(
                message: "Opening a new timer draft needs Commandly’s window."
            )
        default:
            return .interactionRequired(
                message: "Opening Timers needs Commandly’s window."
            )
        }
    }
}
