import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import Infrastructure

/// IOKit power-source adapter used by battery protection and the "connected to power" rule.
struct IOKitPowerSourceService: PowerSourceReading {
    func snapshot() -> PowerSourceSnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 0
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0

            return PowerSourceSnapshot(
                isOnBattery: state == kIOPSBatteryPowerValue,
                percentRemaining: min(100, max(0, percent))
            )
        }
        return nil
    }
}

/// Core Graphics adapter that tells the built-in display apart from attached ones.
struct CoreGraphicsExternalDisplayService: ExternalDisplayReading {
    func hasExternalDisplay() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return KeepAwakeAutomationRules.hasExternalDisplay(
            builtInFlags: displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 }
        )
    }
}

/// Reads the lock flag the login session publishes for the current console session.
struct CoreGraphicsScreenLockService: ScreenLockReading {
    func isScreenLocked() -> Bool {
        KeepAwakeAutomationRules.isScreenLocked(
            sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any]
        )
    }
}

/// Posts a one-point pointer move and returns it, so macOS records user activity.
///
/// Every event is a plain `mouseMoved` inside the bounds of the display the pointer already sits
/// on: no click, no drag, and never a jump to another screen.
struct CoreGraphicsPointerNudgeService: PointerNudging {
    /// How long the pointer rests at the offset position before it is put back.
    static let returnDelay: TimeInterval = 0.08

    @discardableResult
    func nudge() -> Bool {
        guard let origin = Self.pointerLocation(),
              let target = KeepAwakeAutomationRules.nudgeTarget(
                  from: origin,
                  within: Self.displayBounds(containing: origin)
              ),
              Self.move(to: target) else {
            return false
        }

        // Put the pointer back only if nothing else moved it in the meantime, so a nudge that
        // lands while someone is using the Mac never fights their own hand.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnDelay) {
            guard let current = Self.pointerLocation(),
                  abs(current.x - target.x) <= 2,
                  abs(current.y - target.y) <= 2 else {
                return
            }
            _ = Self.move(to: origin)
        }
        return true
    }

    private static func pointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }

        return displays.prefix(Int(count))
            .map(CGDisplayBounds)
            .first { $0.contains(point) }
    }

    private static func move(to point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }
}
