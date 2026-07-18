import AppKit
import Foundation

/// One immutable capture of the connected display topology for a Command Wheel invocation.
///
/// The capture receives its own identifier so display-change callbacks can never accidentally
/// mutate or validate a newer invocation using an older topology.
nonisolated struct CommandWheelDisplayEnvironmentSnapshot: Sendable, Equatable {
    let sessionID: UUID
    let displays: [CommandWheelDisplaySnapshot]
    let activeDisplayIdentifier: String?
}

/// Captures AppKit display state at the system boundary. Geometry and positioning consume only
/// immutable `CommandWheelDisplaySnapshot` values and never retain `NSScreen` instances.
@MainActor
protocol CommandWheelDisplayResolving: AnyObject {
    func capture(pointerLocation: CGPoint) -> CommandWheelDisplayEnvironmentSnapshot
    func isDisplayConnected(identifier: String) -> Bool
}

/// Native `NSScreen` adapter used immediately before Commandly changes application focus.
@MainActor
final class NSScreenCommandWheelDisplayResolver: CommandWheelDisplayResolving {
    typealias ScreenProvider = @MainActor () -> [NSScreen]
    typealias MainScreenProvider = @MainActor () -> NSScreen?

    private let screens: ScreenProvider
    private let mainScreen: MainScreenProvider
    private let makeUUID: () -> UUID

    init(
        screens: @escaping ScreenProvider = { NSScreen.screens },
        mainScreen: @escaping MainScreenProvider = { NSScreen.main },
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.screens = screens
        self.mainScreen = mainScreen
        self.makeUUID = makeUUID
    }

    func capture(pointerLocation: CGPoint) -> CommandWheelDisplayEnvironmentSnapshot {
        let nativeScreens = screens()
        let snapshots = nativeScreens
            .map(Self.snapshot(for:))
            .filter(\.isUsable)
            .sorted { $0.identifier < $1.identifier }

        let mainIdentifier = mainScreen().map(Self.identifier(for:))
        let activeIdentifier: String?
        if let mainIdentifier, snapshots.contains(where: { $0.identifier == mainIdentifier }) {
            activeIdentifier = mainIdentifier
        } else {
            activeIdentifier = CommandWheelPositioningEngine.display(
                containing: pointerLocation,
                in: snapshots
            )?.identifier
        }

        return CommandWheelDisplayEnvironmentSnapshot(
            sessionID: makeUUID(),
            displays: snapshots,
            activeDisplayIdentifier: activeIdentifier
        )
    }

    func isDisplayConnected(identifier: String) -> Bool {
        screens().contains { Self.identifier(for: $0) == identifier }
    }

    static func snapshot(for screen: NSScreen) -> CommandWheelDisplaySnapshot {
        CommandWheelDisplaySnapshot(
            identifier: identifier(for: screen),
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            scale: screen.backingScaleFactor
        )
    }

    static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber {
            return "display-\(number.uint32Value)"
        }

        // AppKit normally supplies NSScreenNumber. The frame fallback remains deterministic for
        // the current process and deliberately does not pretend to be durable across reboots.
        let frame = screen.frame.standardized
        return [
            "display-frame",
            String(describing: frame.origin.x),
            String(describing: frame.origin.y),
            String(describing: frame.size.width),
            String(describing: frame.size.height),
        ].joined(separator: ":")
    }
}
