import Foundation

/// One fan as the controller reports it.
nonisolated struct Fan: Identifiable, Equatable, Sendable {
    var id: Int { index }

    let index: Int
    /// Current speed in revolutions per minute.
    let actualRPM: Double?
    /// Speed the controller is currently aiming for.
    let targetRPM: Double?
    let minimumRPM: Double?
    let maximumRPM: Double?

    var displayName: String { "Fan \(index + 1)" }

    /// Where this fan sits between its own limits, `0...1`.
    var speedFraction: Double? {
        guard let actualRPM, let minimumRPM, let maximumRPM, maximumRPM > minimumRPM else {
            return nil
        }
        return min(1, max(0, (actualRPM - minimumRPM) / (maximumRPM - minimumRPM)))
    }
}

/// How fan speed is being decided.
nonisolated enum FanControlMode: String, CaseIterable, Identifiable, Sendable {
    /// macOS decides, which is what every Mac does until something takes over.
    case system
    /// One speed the user chose, held until they change it.
    case manual
    /// A speed that follows chip temperature through the user's curve.
    case curve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .manual: return "Manual"
        case .curve: return "Curve"
        }
    }
}

/// One point of a fan curve: at `temperatureCelsius` and above, aim for `speedFraction`.
nonisolated struct FanCurvePoint: Equatable, Sendable, Identifiable, Codable {
    var id: Int { Int(temperatureCelsius.rounded()) }

    var temperatureCelsius: Double
    /// Where to sit between the fan's own minimum and maximum, `0...1`.
    var speedFraction: Double
}

/// Why fan control is not available, when it is not.
nonisolated enum FanControlUnavailableReason: Equatable, Sendable {
    /// The controller could not be opened. App Sandbox does not grant that interface.
    case controllerUnavailable
    /// The controller opened but reports no fans, which is what a fanless Mac does.
    case noFans
    /// The controller exposes the fans but not the keys that would set their speed.
    case notWritable
}

/// Rules for turning a curve and a temperature into a fan speed, and for deciding when control
/// has to be handed back to the system.
nonisolated enum FanControlRules {
    /// The curve a Mac starts with: quiet until the chip is warm, then rising steadily.
    static let defaultCurve: [FanCurvePoint] = [
        FanCurvePoint(temperatureCelsius: 45, speedFraction: 0),
        FanCurvePoint(temperatureCelsius: 60, speedFraction: 0.25),
        FanCurvePoint(temperatureCelsius: 75, speedFraction: 0.6),
        FanCurvePoint(temperatureCelsius: 90, speedFraction: 1),
    ]

    /// Chip temperature at which control returns to the system no matter what the curve says.
    static let thermalHandbackCelsius: Double = 95

    /// How long a fan reading may be missing before control is handed back.
    static let sensorHandbackInterval: TimeInterval = 10

    /// The speed a curve asks for at one temperature, interpolated between its points.
    ///
    /// Below the first point the curve holds its first value; above the last it holds the last.
    /// An empty curve asks for nothing, which leaves the system in charge.
    static func speedFraction(atCelsius temperature: Double, curve: [FanCurvePoint]) -> Double? {
        let sorted = curve.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if temperature <= first.temperatureCelsius { return clampFraction(first.speedFraction) }
        if temperature >= last.temperatureCelsius { return clampFraction(last.speedFraction) }

        for (lower, upper) in zip(sorted, sorted.dropFirst())
        where temperature >= lower.temperatureCelsius && temperature <= upper.temperatureCelsius {
            let span = upper.temperatureCelsius - lower.temperatureCelsius
            guard span > 0 else { return clampFraction(upper.speedFraction) }
            let progress = (temperature - lower.temperatureCelsius) / span
            let fraction = lower.speedFraction
                + (upper.speedFraction - lower.speedFraction) * progress
            return clampFraction(fraction)
        }
        return clampFraction(last.speedFraction)
    }

    /// Turns a fraction of a fan's range into the RPM to ask the controller for.
    static func targetRPM(fraction: Double, minimumRPM: Double, maximumRPM: Double) -> Double? {
        guard maximumRPM > minimumRPM else { return nil }
        return minimumRPM + (maximumRPM - minimumRPM) * clampFraction(fraction)
    }

    /// Whether control must be handed back to macOS right now.
    ///
    /// Control is a borrowed responsibility: anything that means Commandly can no longer judge
    /// the machine's heat — a missing reading, a chip above the handback temperature, the app
    /// going away — returns the fans to the system rather than leaving them where they were.
    static func mustHandBackControl(
        chipTemperature: Double?,
        secondsSinceLastReading: TimeInterval,
        isThermallyPressured: Bool
    ) -> Bool {
        if isThermallyPressured { return true }
        if secondsSinceLastReading > sensorHandbackInterval { return true }
        guard let chipTemperature else { return true }
        return chipTemperature >= thermalHandbackCelsius
    }

    private static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

/// Persisted fan control preferences.
nonisolated struct FanControlSettings: Equatable, Sendable {
    var mode: FanControlMode
    /// Where a manual fan sits between its own limits, `0...1`.
    var manualSpeedFraction: Double
    var curve: [FanCurvePoint]

    static let `default` = FanControlSettings(
        mode: .system,
        manualSpeedFraction: 0.35,
        curve: FanControlRules.defaultCurve
    )
}

/// Persists fan control preferences.
protocol FanControlSettingsStoring: AnyObject, Sendable {
    func load() -> FanControlSettings
    func save(_ settings: FanControlSettings)
}

/// UserDefaults-backed fan control store.
///
/// The mode deliberately does not survive a relaunch: taking the fans over is an active choice,
/// and a fresh launch always starts with macOS in charge.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set.
final class UserDefaultsFanControlSettingsStore: FanControlSettingsStoring, @unchecked Sendable {
    private enum Key {
        static let manualSpeedFraction = "fanControl.manualSpeedFraction"
        static let curve = "fanControl.curve"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FanControlSettings {
        let fallback = FanControlSettings.default
        let storedFraction = defaults.object(forKey: Key.manualSpeedFraction) as? Double
        let curve: [FanCurvePoint]
        if let data = defaults.data(forKey: Key.curve),
           let decoded = try? JSONDecoder().decode([FanCurvePoint].self, from: data),
           decoded.isEmpty == false {
            curve = decoded
        } else {
            curve = fallback.curve
        }

        return FanControlSettings(
            mode: .system,
            manualSpeedFraction: min(1, max(0, storedFraction ?? fallback.manualSpeedFraction)),
            curve: curve
        )
    }

    func save(_ settings: FanControlSettings) {
        defaults.set(
            min(1, max(0, settings.manualSpeedFraction)),
            forKey: Key.manualSpeedFraction
        )
        if let data = try? JSONEncoder().encode(settings.curve) {
            defaults.set(data, forKey: Key.curve)
        }
    }
}
