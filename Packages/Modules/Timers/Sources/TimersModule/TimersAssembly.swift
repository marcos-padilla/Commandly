import CommandKit
import Foundation
import ModuleKit

/// Narrow assembly for the Timers & Focus module.
///
/// The assembly receives only the timer store it needs. It is never handed a general-purpose
/// service container, and it does not import the Commandly executable or any shell type.
///
/// Everything outside ``activate()`` is metadata: constructing the assembly and reading its
/// manifest, commands, settings, or documentation starts no timer and touches no user state.
@MainActor
public struct TimersAssembly: ModuleAssembly {
    private let makeStore: @MainActor () -> TimerStore

    /// Creates an assembly that lazily builds its own timer store.
    public init() {
        self.init(makeStore: { TimerStore() })
    }

    /// Creates an assembly with an injected store factory.
    ///
    /// The factory is called at most once, when the host activates the module.
    public init(makeStore: @escaping @MainActor () -> TimerStore) {
        self.makeStore = makeStore
    }

    public var manifest: ModuleManifest { TimersModuleManifest.value }

    public var commandDefinitions: [ModuleCommandDefinition] { TimersCommands.all }

    public var settings: ModuleSettingsContribution? { TimersSettings.contribution }

    public var documentation: ModuleDocumentationContribution? {
        TimersDocumentation.contribution
    }

    public func activate() async throws -> ModuleActivation {
        let store = makeStore()
        let operations = TimerOperations(store: store)
        let presentation = TimersPresentationCommandHandler()
        return ModuleActivation(
            handlers: [
                TimersModuleIdentifiers.startTool: StartTimerCommandHandler(
                    operations: operations
                ),
                TimersModuleIdentifiers.application: presentation,
                TimersModuleIdentifiers.openTool: presentation,
                TimersModuleIdentifiers.newTimerTool: presentation
            ],
            lifecycle: TimersLifecycle(store: store)
        )
    }
}

/// Retained behavior for the Timers module.
///
/// The store owns a one-second refresh source that exists only while a countdown runs. Deactivating
/// the module stops that source so a disabled module does not keep a run-loop timer alive.
/// Countdown state itself is not deleted: disabling a module is not permission to destroy its data.
@MainActor
public final class TimersLifecycle: ModuleLifecycle {
    /// The store this lifetime owns. Exposed so the shell can bind its Timers UI to the same
    /// instance the command handlers use, rather than constructing a second store.
    public let store: TimerStore

    /// Creates a lifecycle around a store.
    public init(store: TimerStore) {
        self.store = store
    }

    public func activate() async throws {
        // The store schedules its refresh source on demand when a countdown starts, so there is
        // nothing to start here. Refreshing brings any restored countdown up to date.
        store.refresh()
    }

    public func prepareForDeactivation() async -> ModuleDeactivationDecision {
        .allow
    }

    public func deactivate() async {
        store.stopAutomaticUpdates()
    }
}
