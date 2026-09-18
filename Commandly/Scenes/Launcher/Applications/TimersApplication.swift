import CommandKit
import ModuleKit
import SwiftUI
import TimersModule

@MainActor
struct TimersApplication: LauncherApplication, LauncherApplicationToolBackgroundInvoking {
    static let applicationID = TimersModuleIdentifiers.application
    static let openToolID = TimersModuleIdentifiers.openTool
    static let newTimerToolID = TimersModuleIdentifiers.newTimerTool
    static let startToolID = TimersModuleIdentifiers.startTool

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Timers & Focus",
        subtitle: "Run named countdowns and focused work sessions",
        systemImage: "timer",
        category: .productivity,
        mode: .view,
        keywords: ["timer", "countdown", "focus", "pomodoro", "break"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: TimersActionID.beginNew,
                title: "New Timer",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 30,
        configurationFields: TimersSettings.contribution.launcherConfigurationFields,
        documentation: RegisteredApplicationDocumentation.timers
    )

    private let store: TimerStore

    init(store: TimerStore) {
        self.store = store
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.openToolID,
                parentID: Self.applicationID,
                title: "Open Timers",
                subtitle: "Review and manage countdowns and focus sessions",
                systemImage: "timer",
                keywords: ["open", "timers", "countdown", "focus", "pomodoro", "break"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.newTimerToolID,
                parentID: Self.applicationID,
                title: "New Timer",
                subtitle: "Open Timers with a new countdown draft",
                systemImage: "timer.circle",
                order: 1,
                keywords: ["new timer", "create timer", "countdown", "focus", "pomodoro"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.startToolID,
                parentID: Self.applicationID,
                title: TimersCommands.start.manifest.title,
                subtitle: TimersCommands.start.manifest.subtitle,
                systemImage: TimersCommands.start.manifest.systemImage,
                category: TimersCommands.start.manifest.category,
                order: 2,
                keywords: TimersCommands.start.manifest.keywords,
                arguments: TimersCommands.start.manifest.arguments
            )
        ]
    }

    /// `timers.start` performs its work without presenting the launcher, so the shared executor
    /// dispatches it here instead of opening a session.
    var backgroundToolIDs: Set<CommandID> { [Self.startToolID] }

    /// Grants used for a command that already cleared the shared executor's authorization gate.
    ///
    /// `LauncherApplicationToolBackgroundInvoking` does not forward the invocation context, so this
    /// boundary cannot see which caller it is serving. The authoritative authorization therefore
    /// happens **before** dispatch: `SharedCommandModuleDispatcher` checks an automation caller's
    /// real grants against the command's policy, and the launcher's availability gate covers
    /// user-initiated callers.
    ///
    /// What is passed here is the minimum `timers.start`'s policy requires — an identity grant and
    /// nothing else. It confers no filesystem, external-action, or disclosure authority, which is
    /// safe precisely because this command is a local, non-disclosing mutation. The identity bit is
    /// **not** a trustworthy signal at this boundary, so a command with a stronger policy must not
    /// be routed through here until the real invocation context is forwarded. That is recorded as
    /// outstanding work in `docs/MODULARIZATION_PROGRESS.md`.
    private static let backgroundInvocationGrants: ModuleCallerGrants = [.userInitiated]

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        guard toolID == Self.startToolID else {
            return .failure(message: "Timers tool is unavailable.")
        }
        store.setCompletionSoundEnabled(
            settings.value(for: TimersSettings.completionSoundVariable)?.booleanValue ?? true
        )
        let outcome = await StartTimerCommandHandler(
            operations: TimerOperations(store: store)
        ).execute(
            ModuleCommandInvocation(
                commandID: toolID,
                arguments: arguments,
                context: CommandInvocationContext(source: .search),
                grants: Self.backgroundInvocationGrants
            )
        )
        return outcome.commandResult
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(opensNewTimer: false, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID:
            return makeLaunch(opensNewTimer: false, context: context)
        case Self.newTimerToolID:
            return makeLaunch(opensNewTimer: true, context: context)
        case Self.startToolID:
            // Reached only if a caller bypasses the background-tool path. Starting a timer is a
            // direct operation; it must never fall back to opening the surface and reporting
            // success as though a countdown had begun.
            return .message("Start Timer runs without opening Timers.")
        default:
            return .message("Timers tool is unavailable.")
        }
    }

    private func makeLaunch(
        opensNewTimer: Bool,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let soundEnabled = context.settings
            .value(for: TimersSettings.completionSoundVariable)?.booleanValue ?? true
        store.setCompletionSoundEnabled(soundEnabled)
        let model = TimersViewModel(
            store: store,
            onGoBack: context.navigation.goBack
        )
        if opensNewTimer {
            model.beginCreating()
        }
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                TimersView(viewModel: $0)
            }
        )
    }
}
