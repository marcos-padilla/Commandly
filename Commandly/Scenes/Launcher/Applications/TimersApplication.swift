import CommandKit
import SwiftUI

@MainActor
struct TimersApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "timers.focus")
    static let openToolID = CommandID(rawValue: "timers.focus.tool.open")
    static let newTimerToolID = CommandID(rawValue: "timers.new")

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
        configurationFields: [
            LauncherConfigurationField(
                id: "completion-sound",
                variable: "completionSound",
                title: "Completion sound",
                description: "Play a local macOS sound when a timer finishes.",
                kind: .toggle,
                defaultValue: .boolean(true)
            )
        ],
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
            )
        ]
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
        default:
            return .message("Timers tool is unavailable.")
        }
    }

    private func makeLaunch(
        opensNewTimer: Bool,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let soundEnabled = context.settings.value(for: "completionSound")?.booleanValue ?? true
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
