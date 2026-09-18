import AppKit
import Foundation

/// Session-scoped mouse delivery, injected so runtime tests never observe the user's clicks.
@MainActor
protocol WindowSwitcherMouseMonitoring: AnyObject {
    func start(onMouseDown: @escaping (CGPoint) -> Void)
    func stop()
}

/// Public AppKit mouse monitors for the non-shipping switcher prototype.
/// Only click locations are delivered; no event content is retained or logged.
@MainActor
final class WindowSwitcherMouseMonitor: WindowSwitcherMouseMonitoring {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onMouseDown: ((CGPoint) -> Void)?
    private var generation: UInt64 = 0

    func start(onMouseDown: @escaping (CGPoint) -> Void) {
        stop()
        self.onMouseDown = onMouseDown
        let expectedGeneration = generation
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.deliver(Self.screenLocation(for: event), generation: expectedGeneration)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let location = Self.screenLocation(for: event)
            DispatchQueue.main.async { [weak self] in
                self?.deliver(location, generation: expectedGeneration)
            }
        }
    }

    func stop() {
        generation &+= 1
        onMouseDown = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func deliver(_ location: CGPoint, generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        onMouseDown?(location)
    }

    private static func screenLocation(for event: NSEvent) -> CGPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}
