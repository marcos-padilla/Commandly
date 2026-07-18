import AppKit
import CoreGraphics

nonisolated enum CommandWheelMouseButton: Sendable, Equatable {
    case left
    case right
    case other
}

nonisolated enum CommandWheelClickSource: Sendable, Equatable {
    case local
    case global
}

nonisolated struct CommandWheelClickEvent: Sendable, Equatable {
    let screenLocation: CGPoint
    let button: CommandWheelMouseButton
    let source: CommandWheelClickSource

    static func == (lhs: CommandWheelClickEvent, rhs: CommandWheelClickEvent) -> Bool {
        lhs.screenLocation.x == rhs.screenLocation.x
            && lhs.screenLocation.y == rhs.screenLocation.y
            && lhs.button == rhs.button
            && lhs.source == rhs.source
    }
}

nonisolated enum CommandWheelLocalClickDisposition: Sendable, Equatable {
    case passThrough
    case consume
}

/// Owned local/global click-monitor boundary for toggle mode. Hold mode never installs monitors.
@MainActor
protocol CommandWheelEventMonitorManaging: AnyObject {
    var hasMonitors: Bool { get }

    func install(
        localHandler: @escaping (CommandWheelClickEvent) -> CommandWheelLocalClickDisposition,
        globalHandler: @escaping (CommandWheelClickEvent) -> Void
    )

    func removeAll()
}

/// Native event-monitor adapter. It observes only mouse-down events while toggle mode is active;
/// it never observes global keyboard input.
@MainActor
final class NSEventCommandWheelEventMonitorManager: CommandWheelEventMonitorManaging {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var localHandler:
        ((CommandWheelClickEvent) -> CommandWheelLocalClickDisposition)?
    private var globalHandler: ((CommandWheelClickEvent) -> Void)?
    private var callbackGeneration: UInt64 = 0

    var hasMonitors: Bool {
        localMonitor != nil || globalMonitor != nil
    }

    func install(
        localHandler: @escaping (CommandWheelClickEvent) -> CommandWheelLocalClickDisposition,
        globalHandler: @escaping (CommandWheelClickEvent) -> Void
    ) {
        let installGeneration = replaceHandlers(
            localHandler: localHandler,
            globalHandler: globalHandler
        )

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // AppKit documents local monitors as main-thread callbacks. `assumeIsolated` keeps the
            // synchronous decision actor-correct. Only the Sendable disposition leaves the actor
            // closure; the non-Sendable NSEvent remains in AppKit's callback scope.
            let disposition: CommandWheelLocalClickDisposition = MainActor.assumeIsolated {
                guard let self, self.callbackGeneration == installGeneration else {
                    return .passThrough
                }
                let snapshot = Self.localSnapshot(event)
                return self.localHandler?(snapshot) ?? .passThrough
            }
            return disposition == .consume ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let snapshot = Self.globalSnapshot(event)
            DispatchQueue.main.async { [weak self] in
                self?.deliverGlobal(snapshot, generation: installGeneration)
            }
        }
    }

    func removeAll() {
        callbackGeneration &+= 1
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        localHandler = nil
        globalHandler = nil
    }

    private func replaceHandlers(
        localHandler: @escaping (CommandWheelClickEvent) -> CommandWheelLocalClickDisposition,
        globalHandler: @escaping (CommandWheelClickEvent) -> Void
    ) -> UInt64 {
        removeAll()
        self.localHandler = localHandler
        self.globalHandler = globalHandler
        return callbackGeneration
    }

    private func deliverGlobal(
        _ event: CommandWheelClickEvent,
        generation: UInt64
    ) {
        guard generation == callbackGeneration else { return }
        globalHandler?(event)
    }

    #if DEBUG
    /// Installs only the delivery closures so generation behavior can be tested without native
    /// global-input registration or macOS privacy prompts.
    func installHandlersForTesting(
        globalHandler: @escaping (CommandWheelClickEvent) -> Void
    ) {
        _ = replaceHandlers(
            localHandler: { _ in .passThrough },
            globalHandler: globalHandler
        )
    }

    var callbackGenerationForTesting: UInt64 { callbackGeneration }

    func deliverGlobalForTesting(
        _ event: CommandWheelClickEvent,
        generation: UInt64
    ) {
        deliverGlobal(event, generation: generation)
    }
    #endif

    private static func localSnapshot(_ event: NSEvent) -> CommandWheelClickEvent {
        let location = event.window?.convertPoint(toScreen: event.locationInWindow)
            ?? NSEvent.mouseLocation
        return CommandWheelClickEvent(
            screenLocation: location,
            button: button(for: event.type),
            source: .local
        )
    }

    private nonisolated static func globalSnapshot(_ event: NSEvent) -> CommandWheelClickEvent {
        CommandWheelClickEvent(
            screenLocation: NSEvent.mouseLocation,
            button: button(for: event.type),
            source: .global
        )
    }

    private nonisolated static func button(for type: NSEvent.EventType) -> CommandWheelMouseButton {
        switch type {
        case .leftMouseDown:
            return .left
        case .rightMouseDown:
            return .right
        default:
            return .other
        }
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}
