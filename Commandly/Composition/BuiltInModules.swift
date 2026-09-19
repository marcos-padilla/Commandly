import ClipboardToolsModule
import CommandKit
import ModuleKit
import Infrastructure
import ModuleRuntime
import ScreenToolsModule
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
        timerStore: TimerStore,
        clipboardTools: ClipboardToolsDependencies = .inMemory,
        screenTools: ScreenToolsDependencies = .inMemory
    ) -> [any ModuleAssembly] {
        [
            TimersAssembly(makeStore: { timerStore }),
            ClipboardToolsAssembly(
                pasteboard: clipboardTools.pasteboard,
                clearing: clipboardTools.clearing,
                configuration: clipboardTools.configuration,
                makeObserver: clipboardTools.makeObserver
            ),
            screenTools.assembly
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
        clipboardTools: ClipboardToolsDependencies = .inMemory,
        screenTools: ScreenToolsDependencies = .inMemory,
        enablement: any ModuleEnablementProviding
    ) -> ModuleHost {
        let host = ModuleHost(enablement: enablement)
        for assembly in assemblies(
            timerStore: timerStore,
            clipboardTools: clipboardTools,
            screenTools: screenTools
        ) {
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


/// The narrow set of interfaces the Clipboard Tools module needs.
///
/// Grouped so `BuiltInModules` stays a registration list rather than growing a parameter per
/// feature. The module itself still receives only these interfaces, through its own initializer.
@MainActor
struct ClipboardToolsDependencies {
    let pasteboard: any PasteboardAccessing
    let clearing: any PasteboardClearing
    let configuration: any ClipboardToolsConfigurationProviding
    let makeObserver: @MainActor () -> any ClipboardAutoClearEventObserving

    init(
        pasteboard: any PasteboardAccessing,
        clearing: any PasteboardClearing,
        configuration: any ClipboardToolsConfigurationProviding,
        makeObserver: @escaping @MainActor () -> any ClipboardAutoClearEventObserving
    ) {
        self.pasteboard = pasteboard
        self.clearing = clearing
        self.configuration = configuration
        self.makeObserver = makeObserver
    }

    /// Dependencies that touch nothing real, for tests and previews.
    static var inMemory: ClipboardToolsDependencies {
        let pasteboard = InMemoryPasteboard()
        return ClipboardToolsDependencies(
            pasteboard: pasteboard,
            clearing: pasteboard,
            configuration: StaticClipboardToolsConfiguration(),
            makeObserver: { InertClipboardAutoClearEventObserver() }
        )
    }

    /// Live dependencies: the system pasteboard and real sleep/lock notifications.
    static func live(registry: LauncherApplicationRegistry) -> ClipboardToolsDependencies {
        let pasteboard = SystemPasteboard()
        return ClipboardToolsDependencies(
            pasteboard: pasteboard,
            clearing: pasteboard,
            configuration: LauncherRegistryClipboardToolsConfiguration(registry: registry),
            makeObserver: { WorkspaceClipboardAutoClearEventObserver() }
        )
    }
}


/// The narrow set of interfaces the Screen Tools module needs.
@MainActor
struct ScreenToolsDependencies {
    let assembly: ScreenToolsAssembly
    /// Retained so the registry can be bound after it is constructed.
    let configuration: LauncherRegistryScreenToolsConfiguration?

    init(
        assembly: ScreenToolsAssembly,
        configuration: LauncherRegistryScreenToolsConfiguration? = nil
    ) {
        self.assembly = assembly
        self.configuration = configuration
    }

    /// Dependencies that capture nothing, for tests and previews.
    static var inMemory: ScreenToolsDependencies {
        ScreenToolsDependencies(
            assembly: ScreenToolsAssembly(
                makeCapture: { UnavailableScreenToolsCapture() },
                recognizer: InMemoryImageRecognitionService(),
                sampler: UnavailableScreenColorSampler(),
                pasteboard: InMemoryPasteboard(),
                configuration: StaticScreenToolsConfiguration()
            )
        )
    }

    /// Live dependencies: real region capture, on-device recognition, and the system sampler.
    ///
    /// The registry is bound later through ``LauncherRegistryScreenToolsConfiguration/install(registry:)``.
    static func live() -> ScreenToolsDependencies {
        let configuration = LauncherRegistryScreenToolsConfiguration()
        return ScreenToolsDependencies(
            assembly: ScreenToolsAssembly(
                makeCapture: { NativeScreenshotCaptureService() },
                recognizer: NativeImageRecognitionService(),
                sampler: SystemScreenColorSampler(),
                pasteboard: SystemPasteboard(),
                configuration: configuration
            ),
            configuration: configuration
        )
    }
}
