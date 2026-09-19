import AppKit
import ClipboardToolsModule
import CommandKit
import Foundation
import ModuleKit

/// Delivers sleep, display-sleep, and screen-lock events to the Clipboard Tools module.
///
/// The module declares what it wants to happen; this adapter owns the macOS notification details.
/// Every observer it registers is released in ``stop()``, so a disabled module leaves nothing
/// behind.
@MainActor
final class WorkspaceClipboardAutoClearEventObserver: ClipboardAutoClearEventObserving {
    /// Distributed notification macOS posts when the screen locks.
    ///
    /// Not a public constant, so it is named here in one place rather than scattered as a literal.
    private static let screenLockNotification = Notification.Name("com.apple.screenIsLocked")

    private var tokens: [any NSObjectProtocol] = []
    private var lockToken: (any NSObjectProtocol)?

    func start(handler: @escaping @MainActor (ClipboardAutoClearTrigger) -> Void) {
        // Repeated starts would otherwise stack observers and fire a trigger several times.
        stop()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, ClipboardAutoClearTrigger)] = [
            (NSWorkspace.willSleepNotification, .systemSleep),
            (NSWorkspace.screensDidSleepNotification, .displaySleep)
        ]
        for (name, trigger) in workspaceEvents {
            let token = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { handler(trigger) }
            }
            tokens.append(token)
        }

        lockToken = DistributedNotificationCenter.default().addObserver(
            forName: Self.screenLockNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler(.screenLock) }
        }
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in tokens {
            workspaceCenter.removeObserver(token)
        }
        tokens.removeAll()
        if let lockToken {
            DistributedNotificationCenter.default().removeObserver(lockToken)
            self.lockToken = nil
        }
    }

    // Intentionally no `deinit` cleanup. Releasing observers is the module lifecycle's job:
    // `ClipboardToolsLifecycle.deactivate()` stops the scheduler, which stops this observer.
    // Deallocation is not a reliable teardown point, and a nonisolated `deinit` cannot touch this
    // main-actor state anyway.
}

/// Reads the Clipboard Tools module's configuration from the launcher's existing preferences.
///
/// The module keeps one settings schema and the launcher keeps one preferences store; this adapter
/// projects between them so there is no second source of truth.
@MainActor
final class LauncherRegistryClipboardToolsConfiguration: ClipboardToolsConfigurationProviding {
    private let registry: LauncherApplicationRegistry
    private let applicationID: CommandID

    /// Creates a provider over the launcher registry.
    init(
        registry: LauncherApplicationRegistry,
        applicationID: CommandID = ClipboardToolsIdentifiers.application
    ) {
        self.registry = registry
        self.applicationID = applicationID
    }

    func currentValues() -> [String: ModuleConfigurationValue] {
        guard let settings = registry.resolvedSettings(for: applicationID) else { return [:] }
        return settings.configuration.mapValues { $0.moduleValue }
    }
}
