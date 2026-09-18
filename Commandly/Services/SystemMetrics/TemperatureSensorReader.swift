import Darwin
import Foundation
import IOKit

/// Which Apple silicon generation a Mac is, which decides where its processor sensors live.
nonisolated enum ChipGeneration: Equatable, Sendable {
    case appleM1
    case appleM2
    case appleM3
    case appleM4
    case appleM5
    case unmappedAppleSilicon
    case other

    /// Whether this generation has a known per-core sensor set.
    var hasMappedCoreSensors: Bool {
        switch self {
        case .appleM1, .appleM2, .appleM3, .appleM4, .appleM5: return true
        case .unmappedAppleSilicon, .other: return false
        }
    }
}

/// Picks the sensors a chip generation actually publishes, and keeps a reading steady across the
/// occasional missed sample.
///
/// Sensor keys are per generation: a Mac reports many temperature keys, and only some of them
/// are the processor cores. Reading the wrong one shows an enclosure or power-supply temperature
/// as if it were the chip.
nonisolated enum TemperatureSensorSelector {
    /// Below this, a reading is a sensor that is not really reporting rather than a cold chip.
    static let minimumPlausibleTemperature = 10.0
    /// Above this, the reading is not a temperature.
    static let maximumPlausibleTemperature = 125.0

    private static let appleM1CoreKeys: Set<String> = [
        "Tp09", "Tp0T",
        "Tp01", "Tp05", "Tp0D", "Tp0H",
        "Tp0L", "Tp0P", "Tp0X", "Tp0b",
    ]

    private static let appleM2CoreKeys: Set<String> = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]

    private static let appleM3CoreKeys: Set<String> = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49",
        "Tf4A", "Tf4B", "Tf4D", "Tf4E",
    ]

    private static let appleM4CoreKeys: Set<String> = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ]

    private static let appleM5CoreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C",
        "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X",
        "Tp0a", "Tp0d", "Tp0g", "Tp0j",
        "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    static func generation(brandString: String?) -> ChipGeneration {
        let brand = brandString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard brand.hasPrefix("Apple M") else {
            return brand.hasPrefix("Apple ") ? .unmappedAppleSilicon : .other
        }
        let remainder = brand.dropFirst("Apple M".count)
        guard let first = remainder.first, let number = Int(String(first)) else {
            return .unmappedAppleSilicon
        }
        // "Apple M3 Pro" is generation three; "Apple M31" would not be a chip.
        let afterNumber = remainder.dropFirst()
        guard afterNumber.isEmpty || afterNumber.first == " " else { return .unmappedAppleSilicon }

        switch number {
        case 1: return .appleM1
        case 2: return .appleM2
        case 3: return .appleM3
        case 4: return .appleM4
        case 5: return .appleM5
        default: return .unmappedAppleSilicon
        }
    }

    static func currentGeneration() -> ChipGeneration {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return .unmappedAppleSilicon
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return .unmappedAppleSilicon
        }
        return generation(brandString: String(cString: buffer))
    }

    /// Whether a key is a temperature sensor worth reading for the processor at all.
    static func isProcessorTemperatureKey(_ key: String, generation: ChipGeneration) -> Bool {
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return true }
        return generation == .appleM3 && key.hasPrefix("Tf")
    }

    static func isCoreKey(_ key: String, generation: ChipGeneration) -> Bool {
        switch generation {
        case .appleM1: return appleM1CoreKeys.contains(key)
        case .appleM2: return appleM2CoreKeys.contains(key)
        case .appleM3: return appleM3CoreKeys.contains(key)
        case .appleM4: return appleM4CoreKeys.contains(key)
        case .appleM5: return appleM5CoreKeys.contains(key)
        case .unmappedAppleSilicon, .other: return false
        }
    }

    /// The processor temperature to show: the hottest mapped core, or — on a Mac that does not
    /// carry the sensors its generation is mapped to — the hottest plausible processor sensor.
    static func displayedProcessorTemperature(
        readings: [(key: String, value: Double)],
        generation: ChipGeneration
    ) -> Double? {
        let plausible = readings.filter { isPlausible($0.value) }
        guard plausible.isEmpty == false else { return nil }

        let cores = plausible.filter { isCoreKey($0.key, generation: generation) }
        if let hottestCore = cores.map(\.value).max() { return hottestCore }
        return plausible.map(\.value).max()
    }

    static func isPlausible(_ value: Double) -> Bool {
        value >= minimumPlausibleTemperature && value < maximumPlausibleTemperature
    }
}

/// Reads chip temperatures from the System Management Controller.
///
/// The SMC is reached through an IOKit user client. App Sandbox does not grant that by default,
/// so on a sandboxed build this reports nothing and every caller treats temperatures as
/// unavailable rather than as zero.
///
/// `@unchecked Sendable`: the connection and the discovered key list are set up in `init` and
/// only read afterwards, and the owner confines every call to one serial queue.
nonisolated final class TemperatureSensorReader: @unchecked Sendable {
    private let client: AppleSMCClient
    private let generation: ChipGeneration
    private let processorKeys: [AppleSMCClient.Key]
    private let graphicsKeys: [AppleSMCClient.Key]

    var isAvailable: Bool { processorKeys.isEmpty == false || graphicsKeys.isEmpty == false }

    init?() {
        guard let client = AppleSMCClient() else { return nil }
        self.client = client
        // Key discovery enumerates the whole controller, so it happens once here and every later
        // sample reads the keys it found directly.
        //
        // The generation is read into a local first: `keys` takes a closure, and `self` is not
        // fully initialized yet.
        let chip = TemperatureSensorSelector.currentGeneration()
        let allKeys = client.keys { name in
            name.hasPrefix("T") && name.count == 4
        }
        processorKeys = allKeys.filter {
            TemperatureSensorSelector.isProcessorTemperatureKey($0.name, generation: chip)
        }
        graphicsKeys = allKeys.filter { $0.name.hasPrefix("Tg") }
        generation = chip
    }

    func processorTemperature() -> Double? {
        let readings = processorKeys.compactMap { key -> (key: String, value: Double)? in
            guard let value = client.readValue(key) else { return nil }
            return (key.name, value)
        }
        return TemperatureSensorSelector.displayedProcessorTemperature(
            readings: readings,
            generation: generation
        )
    }

    func graphicsTemperature() -> Double? {
        graphicsKeys
            .compactMap(client.readValue)
            .filter(TemperatureSensorSelector.isPlausible)
            .max()
    }
}
