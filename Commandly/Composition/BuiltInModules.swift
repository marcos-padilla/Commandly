import CommandKit
import ModuleKit
import ModuleRuntime
import TimersModule

/// The application's explicit list of compiled-in feature modules.
///
/// Adding a normal feature means writing its module target and adding **one line here**. It must
/// not require editing a feature switch in the runtime, the settings root, launcher search, the
/// documentation catalog, or the AI executor.
///
/// Platform exceptions that genuinely cannot register at runtime are listed in
/// `docs/ARCHITECTURE.md`: app extensions, the System Companion helper, and the Quick Look
/// generator are declared at build time in the Xcode project and in `Info.plist`.
@MainActor
enum BuiltInModules {
    /// Every module compiled into this build, in registration order.
    ///
    /// Reading this list constructs assemblies but starts **no** services: an assembly's manifest,
    /// commands, settings, and documentation are all metadata, and services are created only when
    /// the host activates the module.
    static func assemblies(
        timerStore: TimerStore
    ) -> [any ModuleAssembly] {
        [
            TimersAssembly(makeStore: { timerStore })
        ]
    }

    /// Builds a host with every built-in module registered.
    ///
    /// - Parameters:
    ///   - timerStore: the store the launcher's Timers UI also binds to, so the UI and the
    ///     `timers.start` command share one module lifetime rather than two stores.
    ///   - enablement: effective enablement, backed by the existing launcher preferences so group
    ///     and application inheritance is not duplicated.
    static func makeHost(
        timerStore: TimerStore,
        enablement: any ModuleEnablementProviding
    ) -> ModuleHost {
        let host = ModuleHost(enablement: enablement)
        for assembly in assemblies(timerStore: timerStore) {
            do {
                try host.register(assembly)
            } catch {
                // A built-in module's metadata is authored in this repository and validated by
                // tests, so an invalid registration is a programming error, not a runtime
                // condition a user can reach.
                preconditionFailure("Built-in module registration must be valid: \(error)")
            }
        }
        return host
    }
}

/// Backs module enablement with the launcher's existing application preferences.
///
/// A module's effective enablement is the enablement of the launcher applications it owns,
/// including inherited group settings. This keeps one enablement store rather than introducing a
/// second source of truth.
@MainActor
final class LauncherRegistryModuleEnablementProvider: ModuleEnablementProviding {
    private let registry: LauncherApplicationRegistry
    private let applicationIDsByModule: [ModuleID: [CommandID]]

    /// Creates a provider over the launcher registry.
    init(registry: LauncherApplicationRegistry, manifests: [ModuleManifest]) {
        self.registry = registry
        self.applicationIDsByModule = Dictionary(
            manifests.map { ($0.id, $0.ownedApplicationIDs) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func isEnabled(_ moduleID: ModuleID) -> Bool {
        guard let applicationIDs = applicationIDsByModule[moduleID],
              applicationIDs.isEmpty == false else {
            // A module with no launcher application of its own has nothing to inherit from and is
            // governed only by its own registration.
            return true
        }
        return applicationIDs.contains { registry.isEffectivelyEnabled($0) }
    }
}
