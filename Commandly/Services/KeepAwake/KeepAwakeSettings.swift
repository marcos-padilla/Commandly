import Foundation

/// Menu bar glyph shown while a Keep Awake session is running.
enum KeepAwakeActiveIcon: String, CaseIterable, Identifiable, Sendable {
    case commandly
    case coffee
    case eye
    case moon
    case bulb

    var id: String { rawValue }

    /// SF Symbol drawn in the menu bar while the session runs.
    var symbolName: String {
        switch self {
        case .commandly: return "command"
        case .coffee: return "cup.and.saucer.fill"
        case .eye: return "eye.fill"
        case .moon: return "moon.zzz.fill"
        case .bulb: return "lightbulb.fill"
        }
    }

    var title: String {
        switch self {
        case .commandly: return "Commandly"
        case .coffee: return "Coffee"
        case .eye: return "Eye"
        case .moon: return "Moon"
        case .bulb: return "Lightbulb"
        }
    }

    static func sanitized(_ rawValue: String) -> KeepAwakeActiveIcon {
        KeepAwakeActiveIcon(rawValue: rawValue) ?? .commandly
    }
}

/// Tint applied to the active menu bar glyph.
enum KeepAwakeIconTint: String, CaseIterable, Identifiable, Sendable {
    case orange
    case green
    case blue
    case purple
    case pink
    case untinted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orange: return "Orange"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .untinted: return "No tint"
        }
    }

    static func sanitized(_ rawValue: String) -> KeepAwakeIconTint {
        KeepAwakeIconTint(rawValue: rawValue) ?? .orange
    }
}

/// Non-secret Keep Awake preferences.
struct KeepAwakeSettings: Equatable, Sendable {
    /// Session length in minutes for a manual start. `0` runs until it is switched off.
    var duration: Int
    /// Starts a session as soon as Commandly launches.
    var startsWithCommandly: Bool
    /// Keeps the Mac awake but lets the display go dark on its own.
    var allowsDisplaySleep: Bool
    var activeIcon: KeepAwakeActiveIcon
    var activeIconTint: KeepAwakeIconTint
    /// Moves the pointer one point on an interval so apps that watch input stay busy.
    var nudgesPointer: Bool
    /// Minutes between pointer nudges.
    var pointerNudgeInterval: Int
    /// Starts a session while an external display is attached.
    var startsWithExternalDisplay: Bool
    /// Starts a session while the Mac runs on wall power.
    var startsWhenConnectedToPower: Bool
    /// Starts a session while any chosen app is running.
    var startsWithRunningApplications: Bool
    /// Bundle identifiers watched by the running-apps rule.
    var runningApplicationBundleIdentifiers: [String]
    /// Drops the assertions while the screen is locked and takes them back on unlock.
    var pausesWhenScreenLocked: Bool
    /// Battery percentage at which a session stops. `0` never stops for battery.
    var batteryFloorPercent: Int

    static let `default` = KeepAwakeSettings(
        duration: 0,
        startsWithCommandly: false,
        allowsDisplaySleep: false,
        activeIcon: .commandly,
        activeIconTint: .orange,
        nudgesPointer: false,
        pointerNudgeInterval: 5,
        startsWithExternalDisplay: false,
        startsWhenConnectedToPower: false,
        startsWithRunningApplications: false,
        runningApplicationBundleIdentifiers: [],
        pausesWhenScreenLocked: false,
        batteryFloorPercent: 0
    )

    /// Whether any automation rule is switched on.
    var hasAutomation: Bool {
        startsWithExternalDisplay
            || startsWhenConnectedToPower
            || startsWithRunningApplications
            || pausesWhenScreenLocked
    }
}

/// Persists Keep Awake preferences.
protocol KeepAwakeSettingsStoring: AnyObject, Sendable {
    func load() -> KeepAwakeSettings
    func save(_ settings: KeepAwakeSettings)
}

/// UserDefaults-backed Keep Awake preference store.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set; this type only
/// reads and writes scalar preference keys.
final class UserDefaultsKeepAwakeSettingsStore: KeepAwakeSettingsStoring, @unchecked Sendable {
    private enum Key {
        static let duration = "keepAwake.duration"
        static let startsWithCommandly = "keepAwake.startsWithCommandly"
        static let allowsDisplaySleep = "keepAwake.allowsDisplaySleep"
        static let activeIcon = "keepAwake.activeIcon"
        static let activeIconTint = "keepAwake.activeIconTint"
        static let nudgesPointer = "keepAwake.nudgesPointer"
        static let pointerNudgeInterval = "keepAwake.pointerNudgeInterval"
        static let startsWithExternalDisplay = "keepAwake.startsWithExternalDisplay"
        static let startsWhenConnectedToPower = "keepAwake.startsWhenConnectedToPower"
        static let startsWithRunningApplications = "keepAwake.startsWithRunningApplications"
        static let runningApplicationBundleIdentifiers = "keepAwake.runningApplicationBundleIdentifiers"
        static let pausesWhenScreenLocked = "keepAwake.pausesWhenScreenLocked"
        static let batteryFloorPercent = "keepAwake.batteryFloorPercent"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> KeepAwakeSettings {
        let fallback = KeepAwakeSettings.default
        let storedInterval = defaults.object(forKey: Key.pointerNudgeInterval) as? Int
        return KeepAwakeSettings(
            duration: KeepAwakeAutomationRules.sanitizedDuration(defaults.integer(forKey: Key.duration)),
            startsWithCommandly: defaults.bool(forKey: Key.startsWithCommandly),
            allowsDisplaySleep: defaults.bool(forKey: Key.allowsDisplaySleep),
            activeIcon: KeepAwakeActiveIcon.sanitized(
                defaults.string(forKey: Key.activeIcon) ?? fallback.activeIcon.rawValue
            ),
            activeIconTint: KeepAwakeIconTint.sanitized(
                defaults.string(forKey: Key.activeIconTint) ?? fallback.activeIconTint.rawValue
            ),
            nudgesPointer: defaults.bool(forKey: Key.nudgesPointer),
            pointerNudgeInterval: KeepAwakeAutomationRules.sanitizedPointerNudgeInterval(
                storedInterval ?? fallback.pointerNudgeInterval
            ),
            startsWithExternalDisplay: defaults.bool(forKey: Key.startsWithExternalDisplay),
            startsWhenConnectedToPower: defaults.bool(forKey: Key.startsWhenConnectedToPower),
            startsWithRunningApplications: defaults.bool(forKey: Key.startsWithRunningApplications),
            runningApplicationBundleIdentifiers: KeepAwakeAutomationRules.sanitizedBundleIdentifiers(
                defaults.stringArray(forKey: Key.runningApplicationBundleIdentifiers) ?? []
            ),
            pausesWhenScreenLocked: defaults.bool(forKey: Key.pausesWhenScreenLocked),
            batteryFloorPercent: KeepAwakeAutomationRules.sanitizedBatteryFloor(
                defaults.integer(forKey: Key.batteryFloorPercent)
            )
        )
    }

    func save(_ settings: KeepAwakeSettings) {
        defaults.set(KeepAwakeAutomationRules.sanitizedDuration(settings.duration), forKey: Key.duration)
        defaults.set(settings.startsWithCommandly, forKey: Key.startsWithCommandly)
        defaults.set(settings.allowsDisplaySleep, forKey: Key.allowsDisplaySleep)
        defaults.set(settings.activeIcon.rawValue, forKey: Key.activeIcon)
        defaults.set(settings.activeIconTint.rawValue, forKey: Key.activeIconTint)
        defaults.set(settings.nudgesPointer, forKey: Key.nudgesPointer)
        defaults.set(
            KeepAwakeAutomationRules.sanitizedPointerNudgeInterval(settings.pointerNudgeInterval),
            forKey: Key.pointerNudgeInterval
        )
        defaults.set(settings.startsWithExternalDisplay, forKey: Key.startsWithExternalDisplay)
        defaults.set(settings.startsWhenConnectedToPower, forKey: Key.startsWhenConnectedToPower)
        defaults.set(settings.startsWithRunningApplications, forKey: Key.startsWithRunningApplications)
        defaults.set(
            KeepAwakeAutomationRules.sanitizedBundleIdentifiers(settings.runningApplicationBundleIdentifiers),
            forKey: Key.runningApplicationBundleIdentifiers
        )
        defaults.set(settings.pausesWhenScreenLocked, forKey: Key.pausesWhenScreenLocked)
        defaults.set(
            KeepAwakeAutomationRules.sanitizedBatteryFloor(settings.batteryFloorPercent),
            forKey: Key.batteryFloorPercent
        )
    }
}

/// In-memory Keep Awake store for previews and tests.
///
/// `@unchecked Sendable`: a single stored value guarded by `lock`.
final class InMemoryKeepAwakeSettingsStore: KeepAwakeSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: KeepAwakeSettings

    init(settings: KeepAwakeSettings = .default) {
        self.settings = settings
    }

    func load() -> KeepAwakeSettings {
        lock.withLock { settings }
    }

    func save(_ settings: KeepAwakeSettings) {
        lock.withLock { self.settings = settings }
    }
}
