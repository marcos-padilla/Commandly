import CommandKit
import SwiftUI

@MainActor
struct TimersApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "timers.focus")

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
        ]
    )

    private let store: TimerStore

    init(store: TimerStore) {
        self.store = store
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let soundEnabled = context.settings.value(for: "completionSound")?.booleanValue ?? true
        store.setCompletionSoundEnabled(soundEnabled)
        let model = TimersViewModel(
            store: store,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                TimersView(viewModel: $0)
            }
        )
    }
}
