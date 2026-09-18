import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observability
import Observation

/// Direction of one volume-key press.
nonisolated enum PreciseVolumeDirection: Equatable, Sendable {
    case up
    case down
}

/// The media keys the monitor cares about, as reported in a system-defined event's `data1`.
nonisolated enum PreciseVolumeMediaKey: Int32, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7

    var direction: PreciseVolumeDirection? {
        switch self {
        case .volumeUp: return .up
        case .volumeDown: return .down
        case .mute: return nil
        }
    }
}

/// Thins out the burst a hardware volume wheel produces.
///
/// A wheel emits far more presses per turn than a keyboard does, and forwarding each one as a
/// fine step is no finer than the coarse step it replaced. Presses closer together than the
/// minimum spacing are dropped, and a quick reversal has to repeat before it is believed, so a
/// wheel that jitters one detent backwards does not walk the volume back down.
nonisolated struct PreciseVolumeGate: Sendable {
    var minimumSpacing: TimeInterval = 0.03
    var reversalWindow: TimeInterval = 0.30
    var reversalConfirmations = 2

    private var lastAcceptedAt: TimeInterval?
    private var lastDirection: PreciseVolumeDirection?
    private var reversalDirection: PreciseVolumeDirection?
    private var reversalCount = 0

    mutating func reset() {
        lastAcceptedAt = nil
        lastDirection = nil
        reversalDirection = nil
        reversalCount = 0
    }

    mutating func accepts(_ direction: PreciseVolumeDirection, at time: TimeInterval) -> Bool {
        if let lastAcceptedAt, time - lastAcceptedAt <= minimumSpacing { return false }

        if let lastDirection, direction != lastDirection,
           let lastAcceptedAt, time - lastAcceptedAt < reversalWindow {
            if reversalDirection == direction {
                reversalCount += 1
            } else {
                reversalDirection = direction
                reversalCount = 1
            }
            guard reversalCount > reversalConfirmations else { return false }
        } else {
            reversalDirection = nil
            reversalCount = 0
        }

        lastDirection = direction
        lastAcceptedAt = time
        reversalDirection = nil
        reversalCount = 0
        return true
    }
}

/// Turns the volume keys into macOS' fine volume step.
///
/// macOS already has a quarter-step, reached by holding Option and Shift with a volume key. This
/// intercepts the plain press and re-posts it with those modifiers, so every press moves the
/// volume by a quarter of the usual amount without anyone holding anything.
///
/// The tap runs only while the preference is on and Accessibility is granted; without that
/// permission the keys keep their normal behavior.
@Observable
@MainActor
final class PreciseVolumeStepMonitor {
    /// Set when the event tap could not be created, so the panel can say why nothing changed.
    private(set) var tapFailed = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gate = PreciseVolumeGate()
    private var isEnabled = false
    private let logger: AppLogger

    /// Marks the events this monitor posts, so its own output is never re-processed.
    private static let forwardedMarker: Int64 = 0x434D_4C56
    /// `NSEvent.EventType.systemDefined` as a `CGEventType` raw value.
    private static let systemDefinedEventType: UInt32 = 14
    /// The `NSEvent` subtype that carries media keys.
    private static let mediaKeySubtype: Int16 = 8

    init(logger: AppLogger = Loggers.application) {
        self.logger = logger
    }

    /// Follows the preference. Re-checks Accessibility every time, because it can be granted or
    /// revoked while the app runs.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard enabled, AXIsProcessTrusted() else {
            stop()
            return
        }
        start()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        gate.reset()
        tapFailed = false
    }

    private func start() {
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) == false {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<PreciseVolumeStepMonitor>.fromOpaque(userInfo)
                .takeUnretainedValue()
            // The tap is installed on the main run loop, so the callback arrives on the main
            // thread. Only the decision crosses back out; the event itself never leaves here.
            let decision = MainActor.assumeIsolated {
                monitor.decide(type: type, event: event)
            }
            return decision == .forward ? Unmanaged.passUnretained(event) : nil
        }

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefinedEventType),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapFailed = true
            logger.error("Finer volume steps could not create its event tap")
            return
        }

        tap = created
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        tapFailed = false
    }

    /// What the tap should do with one event.
    private enum TapDecision: Sendable {
        /// Let the event continue to whatever normally handles it.
        case forward
        /// Drop the event; a replacement has already been posted, or there is nothing to do.
        case swallow
    }

    private func decide(type: CGEventType, event: CGEvent) -> TapDecision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system disables a tap that took too long, or that user input interrupted.
            if isEnabled, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                stop()
            }
            return .forward
        }

        guard isEnabled,
              type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.mediaKeySubtype else {
            return .forward
        }
        // Our own re-post: let it through untouched or the two would bounce forever.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.forwardedMarker else {
            return .forward
        }
        // Someone already asked for the fine step by hand.
        guard event.flags.contains(.maskAlternate) == false
            || event.flags.contains(.maskShift) == false else {
            return .forward
        }

        guard let press = Self.volumePress(fromData1: nsEvent.data1) else {
            return .forward
        }
        // The key-up half of a press we already answered has nothing left to do.
        guard press.isDown else { return .swallow }
        guard gate.accepts(press.direction, at: ProcessInfo.processInfo.systemUptime) else {
            return .swallow
        }

        Self.postFineVolumeKey(press.keyCode)
        return .swallow
    }

    private static func volumePress(
        fromData1 data1: Int
    ) -> (keyCode: Int32, direction: PreciseVolumeDirection, isDown: Bool)? {
        let keyCode = Int32((data1 >> 16) & 0xffff)
        guard let mediaKey = PreciseVolumeMediaKey(rawValue: keyCode),
              let direction = mediaKey.direction else { return nil }
        let state = (data1 >> 8) & 0xff
        return (keyCode, direction, state == 0x0a)
    }

    /// Re-posts one volume key with the Option+Shift flags macOS reads as "quarter step".
    private static func postFineVolumeKey(_ keyCode: Int32) {
        let fineFlags: UInt = 0x80000 | 0x20000
        for state in [0x0a, 0x0b] {
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8) | fineFlags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: mediaKeySubtype,
                data1: Int((keyCode << 16) | Int32(state << 8)),
                data2: -1
            )?.cgEvent
            event?.setIntegerValueField(.eventSourceUserData, value: forwardedMarker)
            event?.post(tap: .cghidEventTap)
        }
    }
}
