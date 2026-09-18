import CommandKit
import Foundation
import ModuleKit

/// Stable identifiers owned by the Timers & Focus module.
///
/// These values are persisted in Command Wheel profiles, menu-bar pins, shortcut overrides, and
/// usage history. They must not change.
public enum TimersModuleIdentifiers {
    /// The module itself.
    public static let module = ModuleID(rawValue: "timers")
    /// The Timers & Focus launcher application.
    public static let application = CommandID(rawValue: "timers.focus")
    /// Opens the timers surface.
    public static let openTool = CommandID(rawValue: "timers.focus.tool.open")
    /// Opens the new-timer draft. Does **not** start a timer.
    public static let newTimerTool = CommandID(rawValue: "timers.new")
    /// Starts a countdown immediately, without presenting the launcher.
    public static let startTool = CommandID(rawValue: "timers.start")
}

/// Argument names accepted by ``TimersModuleIdentifiers/startTool``.
public enum TimersCommandArgumentName {
    /// Countdown length in whole seconds.
    public static let durationSeconds = "durationSeconds"
    /// Optional countdown name.
    public static let title = "title"
}

/// Output names produced by ``TimersModuleIdentifiers/startTool``.
public enum TimersCommandOutputName {
    /// Stable identifier of the created timer.
    public static let timerID = "timerID"
    /// Resolved timer name.
    public static let title = "title"
    /// Countdown length in whole seconds.
    public static let durationSeconds = "durationSeconds"
    /// Current timer phase.
    public static let phase = "phase"
    /// ISO-8601 instant at which the countdown reaches zero.
    public static let endsAt = "endsAt"
}

/// Validation bounds for a started countdown.
///
/// The upper bound keeps a duration well inside `TimeInterval` arithmetic and rejects the overflow
/// values a caller or a model can otherwise supply.
public enum TimersDurationBounds {
    /// Shortest countdown that can be started.
    public static let minimumSeconds = 1
    /// Longest countdown that can be started: 24 hours.
    public static let maximumSeconds = 86_400
}

/// Canonical command definitions for the Timers & Focus module.
///
/// Launcher metadata, documentation, and AI tool schemas are all derived from these values.
public enum TimersCommands {
    /// Opens the Timers & Focus application surface.
    public static let application = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: TimersModuleIdentifiers.application,
            title: "Timers & Focus",
            subtitle: "Run named countdowns and focused work sessions",
            systemImage: "timer",
            category: .productivity,
            mode: .view,
            keywords: ["timer", "countdown", "focus", "pomodoro", "break"],
            badgeTitle: "Application"
        ),
        summary: "Opens the Timers & Focus application surface.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .readOnly,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Opens the timers surface.
    public static let open = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: TimersModuleIdentifiers.openTool,
            title: "Open Timers",
            subtitle: "Review and manage countdowns and focus sessions",
            systemImage: "timer",
            category: .productivity,
            mode: .action,
            keywords: ["open", "timers", "countdown", "focus", "pomodoro", "break"],
            badgeTitle: "Tool"
        ),
        summary: "Opens the timers surface so the user can review countdowns.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .readOnly,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Opens the new-timer draft.
    ///
    /// This command deliberately does not start a timer. Changing that would silently alter a
    /// shipped command's meaning and would let a caller believe a countdown was running.
    public static let newTimer = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: TimersModuleIdentifiers.newTimerTool,
            title: "New Timer",
            subtitle: "Open Timers with a new countdown draft",
            systemImage: "timer.circle",
            category: .productivity,
            mode: .action,
            keywords: ["new timer", "create timer", "countdown", "focus", "pomodoro"],
            badgeTitle: "Tool"
        ),
        summary: "Opens Timers with an empty countdown draft for the user to complete.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .readOnly,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Starts a countdown immediately.
    ///
    /// Reviewed for AI exposure: it performs only a local, in-process mutation, discloses no user
    /// content, and returns a stable identifier the caller can report truthfully.
    public static let start = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: TimersModuleIdentifiers.startTool,
            title: "Start Timer",
            subtitle: "Start a countdown without opening Timers",
            systemImage: "timer",
            category: .productivity,
            mode: .action,
            keywords: ["start timer", "countdown", "focus", "pomodoro", "begin"],
            arguments: [
                CommandArgument(
                    name: TimersCommandArgumentName.durationSeconds,
                    description: "Countdown length in whole seconds (1–86400).",
                    isRequired: true,
                    valueType: .integer
                ),
                CommandArgument(
                    name: TimersCommandArgumentName.title,
                    description: "Optional name for the countdown.",
                    isRequired: false,
                    valueType: .string
                )
            ],
            badgeTitle: "Tool"
        ),
        summary: "Starts a named countdown immediately and returns its identifier and end time.",
        policy: ModuleCommandPolicy(
            executionMode: .direct,
            effect: .localMutation,
            disclosure: .none,
            aiExposure: .reviewed,
            isIdempotent: false
        )
    )

    /// Every command the module owns, in stable order.
    public static let all: [ModuleCommandDefinition] = [application, open, newTimer, start]
}

/// Static manifest for the Timers & Focus module.
public enum TimersModuleManifest {
    /// Module metadata. Reading it constructs nothing.
    public static let value = ModuleManifest(
        id: TimersModuleIdentifiers.module,
        title: "Timers & Focus",
        summary: "Named countdowns and focused work sessions that keep running in the background.",
        status: .shipping,
        ownedApplicationIDs: [TimersModuleIdentifiers.application],
        ownedCommandIDs: TimersCommands.all.map(\.id),
        capabilities: [],
        activationPolicy: .onDemand,
        configurationVersion: 1,
        documentationArticleIDs: [TimersDocumentation.overviewArticleID]
    )
}
