import CoreGraphics
import Foundation

/// A condition that can start a Keep Awake session on its own.
nonisolated enum KeepAwakeAutomationCondition: String, CaseIterable, Hashable, Sendable, Identifiable {
    case externalDisplay
    case connectedToPower
    case runningApplications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalDisplay: return "External display"
        case .connectedToPower: return "Connected to power"
        case .runningApplications: return "Chosen apps running"
        }
    }

    var symbolName: String {
        switch self {
        case .externalDisplay: return "display"
        case .connectedToPower: return "powerplug.fill"
        case .runningApplications: return "app.fill"
        }
    }
}

/// What the automation rules want done with the current session.
nonisolated enum KeepAwakeAutomationAction: Equatable, Sendable {
    case none
    case activate
    case deactivate
}

/// Pure decision rules behind Keep Awake.
///
/// Everything here is a plain function of its inputs so the session logic can be exercised
/// without displays, power sources, or a pointer.
nonisolated enum KeepAwakeAutomationRules {
    private static let screenLockedKey = "CGSSessionScreenIsLocked"

    /// Session lengths offered by the duration picker, in minutes. `0` means indefinite.
    static let allowedDurations: [Int] = [15, 30, 60, 120, 240, 480, 0]

    /// Intervals offered by the pointer-nudge picker, in minutes.
    static let allowedPointerNudgeIntervals: [Int] = [1, 2, 5, 10, 15, 30]

    /// Battery percentages offered by the low-battery stop picker. `0` means never stop.
    static let allowedBatteryFloors: [Int] = [0, 10, 15, 20, 30, 50]

    static func sanitizedDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    static func sanitizedPointerNudgeInterval(_ minutes: Int) -> Int {
        allowedPointerNudgeIntervals.contains(minutes) ? minutes : 5
    }

    static func sanitizedBatteryFloor(_ percent: Int) -> Int {
        allowedBatteryFloors.contains(percent) ? percent : 0
    }

    /// Trims a stored bundle identifier list to unique, non-empty entries in their saved order.
    static func sanitizedBundleIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && seen.insert($0).inserted }
    }

    /// A display list counts as having an external display when any entry is not built in.
    static func hasExternalDisplay(builtInFlags: [Bool]) -> Bool {
        builtInFlags.contains(false)
    }

    static func isScreenLocked(sessionDictionary: [String: Any]?) -> Bool {
        guard let value = sessionDictionary?[screenLockedKey] else { return false }
        if let locked = value as? Bool { return locked }
        return (value as? NSNumber)?.boolValue ?? false
    }

    static func selectedApplicationsAreRunning(
        selectedBundleIdentifiers: [String],
        runningBundleIdentifiers: [String]
    ) -> Bool {
        guard selectedBundleIdentifiers.isEmpty == false else { return false }
        let selected = Set(selectedBundleIdentifiers)
        return runningBundleIdentifiers.contains(where: selected.contains)
    }

    /// The enabled conditions that are currently satisfied.
    static func matchingConditions(
        externalDisplayEnabled: Bool,
        externalDisplayConnected: Bool,
        powerEnabled: Bool,
        connectedToPower: Bool,
        runningApplicationsEnabled: Bool,
        selectedApplicationsRunning: Bool
    ) -> Set<KeepAwakeAutomationCondition> {
        var matches = Set<KeepAwakeAutomationCondition>()
        if externalDisplayEnabled, externalDisplayConnected {
            matches.insert(.externalDisplay)
        }
        if powerEnabled, connectedToPower {
            matches.insert(.connectedToPower)
        }
        if runningApplicationsEnabled, selectedApplicationsRunning {
            matches.insert(.runningApplications)
        }
        return matches
    }

    /// Decides what automation should do next.
    ///
    /// A manual session is never cut short by automation: only a session automation itself
    /// started is deactivated when its last condition stops matching.
    static func action(
        matchingConditions: Set<KeepAwakeAutomationCondition>,
        sessionActive: Bool,
        automaticSessionActive: Bool
    ) -> KeepAwakeAutomationAction {
        guard matchingConditions.isEmpty == false else {
            return automaticSessionActive ? .deactivate : .none
        }
        return sessionActive ? .none : .activate
    }

    /// Whether battery protection allows a session to run.
    static func batteryAllowsSession(floorPercent: Int, power: PowerReadingInput?) -> Bool {
        guard floorPercent > 0, let power, power.isOnBattery else { return true }
        return power.percentRemaining > floorPercent
    }

    /// Whether a running session must stop because the battery reached its floor.
    static func batteryRequiresStop(floorPercent: Int, power: PowerReadingInput?) -> Bool {
        guard floorPercent > 0, let power, power.isOnBattery else { return false }
        return power.percentRemaining <= floorPercent
    }

    /// The minimal power facts the battery rules need, so tests do not build a full snapshot.
    struct PowerReadingInput: Equatable, Sendable {
        let isOnBattery: Bool
        let percentRemaining: Int

        init(isOnBattery: Bool, percentRemaining: Int) {
            self.isOnBattery = isOnBattery
            self.percentRemaining = percentRemaining
        }
    }

    /// A point one unit away from `origin` that stays inside the display it belongs to.
    ///
    /// Returns `nil` when the display is unknown or too small to hold a one-point move, so the
    /// caller leaves the pointer alone instead of dragging it to another screen.
    static func nudgeTarget(from origin: CGPoint, within bounds: CGRect?) -> CGPoint? {
        guard let bounds, bounds.width > 4, bounds.height > 4 else { return nil }
        let safe = bounds.insetBy(dx: 2, dy: 2)
        let x = min(max(origin.x, safe.minX), safe.maxX)
        let y = min(max(origin.y, safe.minY), safe.maxY)

        if x + 1 <= safe.maxX { return CGPoint(x: x + 1, y: y) }
        if x - 1 >= safe.minX { return CGPoint(x: x - 1, y: y) }
        if y + 1 <= safe.maxY { return CGPoint(x: x, y: y + 1) }
        if y - 1 >= safe.minY { return CGPoint(x: x, y: y - 1) }
        return nil
    }

    /// Countdown text for a session that ends at a known time.
    static func remainingText(until end: Date, now: Date = .now) -> String {
        let total = max(0, Int(end.timeIntervalSince(now)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }

    /// Human-readable label for a duration in minutes.
    static func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Indefinite"
        case 60: return "1 hour"
        case let value where value % 60 == 0: return "\(value / 60) hours"
        default: return "\(minutes) minutes"
        }
    }
}
