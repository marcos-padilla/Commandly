import Foundation
import IOKit
import IOKit.ps
import Observation

/// One power reading.
///
/// Every field is optional: a desktop has no battery, and a sandboxed app cannot open the
/// sensors that report total system draw, so the panel shows only what is real.
nonisolated struct PowerReading: Equatable, Sendable {
    var hasBattery = false
    var chargePercent: Int?
    var isCharging = false
    var isPluggedIn = false
    /// Signed: positive while charging, negative while the battery is being drained.
    var batteryWatts: Double?
    /// What the Mac as a whole is drawing. Derived from battery flow when it is on battery.
    var systemWatts: Double?
    /// The charger's rated output.
    var adapterMaxWatts: Double?
    /// The system's own estimate, in seconds, while discharging.
    var timeRemainingSeconds: TimeInterval?
    /// Full-charge capacity against design capacity.
    var healthPercent: Double?
    var cycleCount: Int?
    var temperatureCelsius: Double?

    static let empty = PowerReading()
}

/// Derivations shared by the power panel.
nonisolated enum PowerMetricsRules {
    /// A Mac running on battery consumes exactly what the battery gives up, so the discharge
    /// rate is the system draw. On wall power the battery says nothing about the rest of the
    /// Mac, and without a readable power sensor there is no honest figure to show.
    static func systemWatts(batteryWatts: Double?, isPluggedIn: Bool) -> Double? {
        guard isPluggedIn == false, let batteryWatts, batteryWatts < 0 else { return nil }
        return abs(batteryWatts)
    }

    /// "8h 47m", or `nil` while macOS is still calculating.
    static func timeRemainingText(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func wattsText(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "—" }
        return watts < 10
            ? String(format: "%.1f W", watts)
            : "\(Int(watts.rounded())) W"
    }
}

/// Reads the battery and charger from the IO registry and the power-source list.
///
/// `@unchecked Sendable`: the cached battery service is the only mutable state and the monitor
/// confines every call to one serial queue.
nonisolated final class PowerSampler: @unchecked Sendable {
    /// Whether this Mac has an internal battery at all. Immutable for a boot, so a desktop does
    /// not keep probing a service it can never have.
    static let hasInternalBattery: Bool = {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()

    private var batteryService: io_service_t = 0

    deinit {
        if batteryService != 0 { IOObjectRelease(batteryService) }
    }

    func sample() -> PowerReading {
        var reading = PowerReading()
        guard let properties = batteryProperties() else { return reading }

        reading.hasBattery = true
        reading.isPluggedIn = (properties["ExternalConnected"] as? Bool) ?? false
        reading.isCharging = (properties["IsCharging"] as? Bool) ?? false

        let millivolts = Self.integer("Voltage", in: properties) ?? 0
        let milliamps = Self.integer("Amperage", in: properties)
            ?? Self.integer("InstantAmperage", in: properties)
            ?? 0
        if millivolts > 0, milliamps != 0 {
            // Power is volts times amps, signed by the amperage.
            reading.batteryWatts = (Double(millivolts) / 1_000) * (Double(milliamps) / 1_000)
        }

        if let adapter = properties["AdapterDetails"] as? [String: Any],
           let rated = adapter["Watts"] as? Int, rated > 0 {
            reading.adapterMaxWatts = Double(rated)
        }

        if let capacity = Self.integer("CurrentCapacity", in: properties),
           let maximum = Self.integer("MaxCapacity", in: properties), maximum > 0 {
            reading.chargePercent = Int((Double(capacity) / Double(maximum) * 100).rounded())
        }
        reading.cycleCount = Self.integer("CycleCount", in: properties)

        if let design = Self.integer("DesignCapacity", in: properties), design > 0 {
            // NominalChargeCapacity is the smoothed figure macOS itself reports; the raw ones
            // stand in when it is absent.
            let fullCharge = Self.integer("NominalChargeCapacity", in: properties)
                ?? Self.integer("FullChargeCapacity", in: properties)
                ?? Self.integer("AppleRawMaxCapacity", in: properties)
            if let fullCharge, fullCharge > 0 {
                reading.healthPercent = min(100, Double(fullCharge) / Double(design) * 100)
            }
        }

        // Reported in hundredths of a degree.
        if let raw = Self.integer("Temperature", in: properties), raw > 0 {
            let celsius = Double(raw) / 100
            if celsius > 0, celsius < 100 { reading.temperatureCelsius = celsius }
        }

        reading.timeRemainingSeconds = Self.timeToEmpty(
            isPluggedIn: reading.isPluggedIn,
            isCharging: reading.isCharging
        )
        reading.systemWatts = PowerMetricsRules.systemWatts(
            batteryWatts: reading.batteryWatts,
            isPluggedIn: reading.isPluggedIn
        )
        return reading
    }

    private func batteryProperties() -> [String: Any]? {
        guard Self.hasInternalBattery else { return nil }
        if batteryService == 0 {
            batteryService = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching("AppleSmartBattery")
            )
        }
        guard batteryService != 0 else { return nil }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            batteryService, &properties, kCFAllocatorDefault, 0
        ) == kIOReturnSuccess,
            let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            IOObjectRelease(batteryService)
            batteryService = 0
            return nil
        }
        return dictionary
    }

    /// The public power-source estimate. A negative value means macOS is still calculating, so
    /// it is reported as unknown rather than as a number nobody should read.
    private static func timeToEmpty(isPluggedIn: Bool, isCharging: Bool) -> TimeInterval? {
        guard isPluggedIn == false, isCharging == false else { return nil }
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let minutes = description[kIOPSTimeToEmptyKey] as? Int,
                  minutes > 0 else { continue }
            return TimeInterval(minutes) * 60
        }
        return nil
    }

    private static func integer(_ key: String, in properties: [String: Any]) -> Int? {
        if let value = number(properties[key]) { return value }
        if let batteryData = properties["BatteryData"] as? [String: Any] {
            return number(batteryData[key])
        }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            let wide = value.int64Value
            guard wide >= Int64(Int.min), wide <= Int64(Int.max) else { return nil }
            return Int(wide)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}

/// Battery and power draw for the panel.
@Observable
@MainActor
final class PowerMetricsMonitor {
    private(set) var reading: PowerReading = .empty
    /// Charge history, `0...1`, oldest first.
    private(set) var chargeHistory: [Double] = []
    /// System draw history in watts, oldest first.
    private(set) var systemWattsHistory: [Double] = []

    var hasBattery: Bool { PowerSampler.hasInternalBattery }

    private let sampler: PowerSampler
    private let interval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.businessmate360.Commandly.power-metrics",
        qos: .utility
    )
    private var timer: Timer?
    private var observers = 0

    init(sampler: PowerSampler = PowerSampler(), interval: TimeInterval = 3) {
        self.sampler = sampler
        self.interval = interval
    }

    func addObserver() {
        observers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.sample() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func removeObserver() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers = 0
    }

    private func sample() {
        queue.async {
            let reading = self.sampler.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.publish(reading) }
            }
        }
    }

    private func publish(_ reading: PowerReading) {
        self.reading = reading
        if let percent = reading.chargePercent {
            chargeHistory = append(Double(percent) / 100, to: chargeHistory)
        }
        if let watts = reading.systemWatts {
            systemWattsHistory = append(watts, to: systemWattsHistory)
        }
    }

    private func append(_ value: Double, to history: [Double]) -> [Double] {
        var next = history
        next.append(max(0, value))
        if next.count > SystemMetricsFormat.historyLength {
            next.removeFirst(next.count - SystemMetricsFormat.historyLength)
        }
        return next
    }
}
