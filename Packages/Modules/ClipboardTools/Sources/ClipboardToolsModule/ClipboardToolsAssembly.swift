import CommandKit
import Foundation
import Infrastructure
import ModuleKit

/// Supplies the module's current configuration.
///
/// The host resolves these from the launcher's existing preferences, so the module reads settings
/// without owning a second store.
@MainActor
public protocol ClipboardToolsConfigurationProviding: AnyObject, Sendable {
    /// Current values for the module's declared configuration variables.
    func currentValues() -> [String: ModuleConfigurationValue]
}

/// Configuration provider backed by a fixed dictionary, for tests and previews.
@MainActor
public final class StaticClipboardToolsConfiguration: ClipboardToolsConfigurationProviding {
    private var values: [String: ModuleConfigurationValue]

    /// Creates a provider.
    public init(values: [String: ModuleConfigurationValue] = [:]) {
        self.values = values
    }

    /// Replaces the configuration, as a settings change would.
    public func update(_ values: [String: ModuleConfigurationValue]) {
        self.values = values
    }

    public func currentValues() -> [String: ModuleConfigurationValue] { values }
}

/// Narrow assembly for the Clipboard Tools module.
///
/// It receives only the pasteboard interfaces and a configuration reader. It never sees the
/// Commandly executable, the launcher, or a general-purpose service container.
///
/// Everything outside ``activate()`` is metadata: reading the manifest, commands, settings, or
/// documentation touches no clipboard content and starts no observer.
@MainActor
public struct ClipboardToolsAssembly: ModuleAssembly {
    private let pasteboard: any PasteboardAccessing
    private let clearing: any PasteboardClearing
    private let configuration: any ClipboardToolsConfigurationProviding
    private let makeObserver: @MainActor () -> any ClipboardAutoClearEventObserving

    /// Creates the assembly.
    ///
    /// - Parameter makeObserver: builds the system-event source. Called once, on activation, so
    ///   constructing the assembly registers no observers.
    public init(
        pasteboard: any PasteboardAccessing,
        clearing: any PasteboardClearing,
        configuration: any ClipboardToolsConfigurationProviding,
        makeObserver: @escaping @MainActor () -> any ClipboardAutoClearEventObserving = {
            InertClipboardAutoClearEventObserver()
        }
    ) {
        self.pasteboard = pasteboard
        self.clearing = clearing
        self.configuration = configuration
        self.makeObserver = makeObserver
    }

    public var manifest: ModuleManifest { ClipboardToolsManifest.value }

    public var commandDefinitions: [ModuleCommandDefinition] { ClipboardToolsCommands.all }

    public var settings: ModuleSettingsContribution? { ClipboardToolsSettings.contribution }

    public var documentation: ModuleDocumentationContribution? {
        ClipboardToolsDocumentation.contribution
    }

    public func activate() async throws -> ModuleActivation {
        let configuration = self.configuration
        let operations = ClipboardToolsOperations(
            pasteboard: pasteboard,
            clearing: clearing,
            makeCleaner: {
                TrackingParameterCleaner(
                    additionalParameterNames: ClipboardToolsSettings
                        .additionalTrackingParameters(from: configuration.currentValues())
                )
            }
        )
        let scheduler = ClipboardAutoClearScheduler(
            pasteboard: clearing,
            observer: makeObserver(),
            configuration: ClipboardToolsSettings
                .autoClearConfiguration(from: configuration.currentValues())
        )
        return ModuleActivation(
            handlers: [
                ClipboardToolsIdentifiers.plainText: FlattenClipboardCommandHandler(
                    operations: operations
                ),
                ClipboardToolsIdentifiers.cleanURL: CleanCopiedLinkCommandHandler(
                    operations: operations
                ),
                ClipboardToolsIdentifiers.clearNow: ClearClipboardCommandHandler(
                    operations: operations
                ),
                ClipboardToolsIdentifiers.application: ClipboardToolsPresentationHandler()
            ],
            lifecycle: ClipboardToolsLifecycle(
                scheduler: scheduler,
                operations: operations,
                configuration: configuration
            )
        )
    }
}

/// Retained behavior for the Clipboard Tools module.
///
/// It owns the auto-clear scheduler and releases it on deactivation, so a disabled module keeps no
/// observers and no pending countdown. Disabling never deletes anything the user saved.
@MainActor
public final class ClipboardToolsLifecycle: ModuleLifecycle {
    /// The auto-clear scheduler this lifetime owns.
    public let scheduler: ClipboardAutoClearScheduler
    /// The module's operations, exposed so the shell can bind UI to the same instance.
    public let operations: ClipboardToolsOperations

    private let configuration: any ClipboardToolsConfigurationProviding

    /// Creates the lifecycle.
    public init(
        scheduler: ClipboardAutoClearScheduler,
        operations: ClipboardToolsOperations,
        configuration: any ClipboardToolsConfigurationProviding
    ) {
        self.scheduler = scheduler
        self.operations = operations
        self.configuration = configuration
    }

    public func activate() async throws {
        scheduler.start()
    }

    public func prepareForDeactivation() async -> ModuleDeactivationDecision {
        .allow
    }

    public func deactivate() async {
        scheduler.stop()
    }

    /// Re-reads settings and applies them to the running scheduler.
    ///
    /// Called when the user changes the module's preferences, so a settings edit takes effect
    /// without restarting the module.
    public func configurationDidChange() {
        scheduler.apply(
            ClipboardToolsSettings.autoClearConfiguration(from: configuration.currentValues())
        )
    }

    /// Notifies the module that the clipboard changed, so the idle countdown restarts and an
    /// automatic link clean can run.
    ///
    /// The shell's clipboard monitor calls this; the module does not poll the pasteboard itself,
    /// which would duplicate Clipboard History's existing monitor.
    public func clipboardDidChange() async {
        scheduler.noteClipboardChanged()
        guard ClipboardToolsSettings
            .cleansLinksAutomatically(from: configuration.currentValues()) else {
            return
        }
        _ = await operations.cleanCopiedLink()
    }
}
