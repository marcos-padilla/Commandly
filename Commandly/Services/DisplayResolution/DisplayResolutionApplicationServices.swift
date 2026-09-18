import AppCore
import AppKit
import Foundation

@MainActor
struct DisplayResolutionApplicationServices {
    let coordinator: DisplayResolutionCoordinator

    static func live(appearance: AuxiliaryWindowAppearance) -> Self {
        let clock = ContinuousSystemClock()
        let controller = DisplayResolutionService(driver: NativeDisplayConfigurationDriver(clock: clock), clock: clock)
        return .init(coordinator: DisplayResolutionCoordinator(controller: controller, clock: clock,
            ticker: NativeDisplayResolutionTicker(), environment: NativeDisplayResolutionEnvironmentMonitor(),
            window: DisplayResolutionWindowController(appearance: appearance), openSettings: {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
                    throw DisplayResolutionSettingsError.unavailable
                }
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }, onRequestQuit: { NSApp.terminate(nil) }))
    }

    /// A real native window over fictional modes. Apply/Keep/Revert never change a system display.
    static func inMemory(appearance: AuxiliaryWindowAppearance = AuxiliaryWindowAppearance()) -> Self {
        let clock = ContinuousSystemClock()
        let controller = DisplayResolutionService(driver: GeneratedDisplayConfigurationDriver(), clock: clock)
        return .init(coordinator: DisplayResolutionCoordinator(controller: controller, clock: clock,
            ticker: NativeDisplayResolutionTicker(), environment: InMemoryDisplayResolutionEnvironmentMonitor(),
            window: DisplayResolutionWindowController(appearance: appearance), openSettings: {}, onRequestQuit: {}))
    }
}

private enum DisplayResolutionSettingsError: Error { case unavailable }

@MainActor
private final class InMemoryDisplayResolutionEnvironmentMonitor: DisplayResolutionEnvironmentObserving {
    func start(_ action: @escaping @MainActor () -> Void) {}
    func stop() {}
}

/// Explicit sample data; records only its own in-memory configuration.
private actor GeneratedDisplayConfigurationDriver {
    private let identity = DisplayHardwareIdentity(displayID: 1, uuid: "generated-display", vendor: 1, model: 1, serial: 1)
    private let choices = [
        DisplayModeFingerprint(ioID: 1, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800, refreshRate: 60, flags: 0, isUsable: true),
        DisplayModeFingerprint(ioID: 2, width: 1280, height: 800, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60, flags: 0, isUsable: true),
        DisplayModeFingerprint(ioID: 3, width: 1280, height: 800, pixelWidth: 1280, pixelHeight: 800, refreshRate: 60, flags: 1, isUsable: true),
        DisplayModeFingerprint(ioID: 4, width: 512, height: 384, pixelWidth: 512, pixelHeight: 384, refreshRate: 0, flags: 0, isUsable: true)
    ]
    private var selectedIndex = 0
    func snapshot() -> DisplayHardwareSnapshot {
        .init(displays: [.init(identity: identity, name: "Generated Display Fixture", isActive: true, isMirrored: false,
            originX: 0, originY: 0, current: choices[selectedIndex], modes: choices, modesAreTruncated: false)])
    }
    func configure(_ change: DisplayConfigurationChange) throws -> DisplayHardwareSnapshot {
        guard snapshot().hasSameConfiguration(as: change.expected), change.display == identity,
              let index = choices.firstIndex(of: change.mode) else { throw DisplayResolutionSettingsError.unavailable }
        selectedIndex = index
        return snapshot()
    }
}

extension GeneratedDisplayConfigurationDriver: DisplayConfigurationDriving {}
