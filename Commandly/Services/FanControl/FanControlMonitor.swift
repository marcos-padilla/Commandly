import AppKit
import Foundation
import Observability
import Observation

/// Reads the fans from the System Management Controller and, where the hardware allows it, sets
/// their speed.
///
/// `@unchecked Sendable`: the discovered key set is built in `init` and only read afterwards,
/// and the monitor confines every call to one serial queue.
nonisolated final class FanHardware: @unchecked Sendable {
    /// The keys one fan exposes. A fan without `target` and `mode` can be read but not set.
    private struct FanKeys {
        let index: Int
        let actual: AppleSMCClient.Key
        let minimum: AppleSMCClient.Key?
        let maximum: AppleSMCClient.Key?
        let target: AppleSMCClient.Key?
        let mode: AppleSMCClient.Key?
    }

    /// Controller value that hands a fan back to macOS, and the one that takes it over.
    private static let systemManagedMode: Double = 0
    private static let forcedMode: Double = 1

    private let client: AppleSMCClient
    private let fans: [FanKeys]

    /// Whether any fan exposes the keys needed to set a speed.
    let isWritable: Bool

    var fanCount: Int { fans.count }

    init?() {
        guard let client = AppleSMCClient() else { return nil }
        self.client = client

        guard let countKey = client.key(named: "FNum"),
              let rawCount = client.readValue(countKey),
              rawCount > 0, rawCount < 16 else {
            return nil
        }

        var discovered: [FanKeys] = []
        for index in 0..<Int(rawCount) {
            guard let actual = client.key(named: "F\(index)Ac") else { continue }
            discovered.append(
                FanKeys(
                    index: index,
                    actual: actual,
                    minimum: client.key(named: "F\(index)Mn"),
                    maximum: client.key(named: "F\(index)Mx"),
                    target: client.key(named: "F\(index)Tg"),
                    // Some controllers spell the mode key with a lowercase d.
                    mode: client.key(named: "F\(index)Md") ?? client.key(named: "F\(index)md")
                )
            )
        }
        guard discovered.isEmpty == false else { return nil }

        fans = discovered
        isWritable = discovered.contains { $0.target != nil && $0.mode != nil }
    }

    func read() -> [Fan] {
        fans.map { keys in
            Fan(
                index: keys.index,
                actualRPM: client.readValue(keys.actual),
                targetRPM: keys.target.flatMap(client.readValue),
                minimumRPM: keys.minimum.flatMap(client.readValue),
                maximumRPM: keys.maximum.flatMap(client.readValue)
            )
        }
    }

    /// Aims every controllable fan at `fraction` of its own range.
    ///
    /// Returns false when no fan accepted the change, so the caller can hand control back rather
    /// than believing it took effect.
    @discardableResult
    func apply(speedFraction fraction: Double) -> Bool {
        var applied = false
        for keys in fans {
            guard let target = keys.target, let mode = keys.mode,
                  let minimum = keys.minimum.flatMap(client.readValue),
                  let maximum = keys.maximum.flatMap(client.readValue),
                  let rpm = FanControlRules.targetRPM(
                      fraction: fraction,
                      minimumRPM: minimum,
                      maximumRPM: maximum
                  ) else { continue }

            // Mode first: a target written while the controller still owns the fan is ignored.
            guard client.writeValue(Self.forcedMode, to: mode) else { continue }
            if client.writeValue(rpm, to: target) { applied = true }
        }
        return applied
    }

    /// Returns every fan to macOS. Safe to call when nothing was ever taken over.
    func handBackToSystem() {
        for keys in fans {
            guard let mode = keys.mode else { continue }
            client.writeValue(Self.systemManagedMode, to: mode)
        }
    }
}

/// Fan speeds for the panel, and the control mode when the hardware allows one.
///
/// Taking the fans over is a borrowed responsibility, so the monitor hands them back by itself
/// whenever it can no longer judge the machine's heat: a reading goes missing, the chip passes
/// the handback temperature, macOS reports thermal pressure, the Mac sleeps, or Commandly quits.
@Observable
@MainActor
final class FanControlMonitor {
    private(set) var fans: [Fan] = []
    /// `nil` while fan control is available.
    private(set) var unavailableReason: FanControlUnavailableReason?
    /// Set when control was handed back by the monitor rather than by the user.
    private(set) var handbackNotice: String?

    var settings: FanControlSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            if settings.mode != oldValue.mode { handbackNotice = nil }
            applyControl()
        }
    }

    var isAvailable: Bool { unavailableReason == nil }

    private let store: any FanControlSettingsStoring
    private let temperatures: SystemMetricsMonitor
    private let logger: AppLogger
    private let interval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.businessmate360.Commandly.fan-control",
        qos: .utility
    )
    private var hardware: FanHardware?
    private var timer: Timer?
    private var observers = 0
    private var sleepObserver: NSObjectProtocol?
    private var lastSuccessfulReadingAt: Date?
    private var hasDiscoveredHardware = false

    init(
        store: any FanControlSettingsStoring = UserDefaultsFanControlSettingsStore(),
        temperatures: SystemMetricsMonitor,
        logger: AppLogger = Loggers.application,
        interval: TimeInterval = 2
    ) {
        self.store = store
        self.temperatures = temperatures
        self.logger = logger
        self.interval = interval
        self.settings = store.load()
    }

    func addObserver() {
        observers += 1
        guard timer == nil else { return }
        discoverHardwareIfNeeded()
        // Curve mode follows chip temperature, which the system monitor is the one reading.
        temperatures.addObserver()
        sample()

        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.sample() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if sleepObserver == nil {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    // Nothing watches the chip while the Mac is asleep.
                    self.handBackControl(notice: "Control returned to macOS for sleep.")
                }
            }
        }
    }

    func removeObserver() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
        temperatures.removeObserver()
    }

    /// Hands the fans back and stops watching. Called when Commandly quits.
    func tearDown() {
        timer?.invalidate()
        timer = nil
        observers = 0
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        let hardware = self.hardware
        queue.async { hardware?.handBackToSystem() }
    }

    private func discoverHardwareIfNeeded() {
        guard hasDiscoveredHardware == false else { return }
        hasDiscoveredHardware = true
        queue.async {
            let hardware = FanHardware()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.hardware = hardware
                    guard let hardware else {
                        self.unavailableReason = .controllerUnavailable
                        return
                    }
                    guard hardware.fanCount > 0 else {
                        self.unavailableReason = .noFans
                        return
                    }
                    self.unavailableReason = hardware.isWritable ? nil : .notWritable
                }
            }
        }
    }

    private func sample() {
        guard let hardware else { return }
        queue.async {
            let fans = hardware.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.publish(fans) }
            }
        }
    }

    private func publish(_ fans: [Fan]) {
        self.fans = fans
        if fans.contains(where: { $0.actualRPM != nil }) {
            lastSuccessfulReadingAt = Date()
        }
        applyControl()
    }

    /// Applies the current mode, or hands control back when it can no longer be trusted.
    private func applyControl() {
        guard let hardware, unavailableReason == nil else { return }
        guard settings.mode != .system else {
            queue.async { hardware.handBackToSystem() }
            return
        }

        let elapsed = lastSuccessfulReadingAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let chipTemperature = temperatures.snapshot.processorTemperature
        let isPressured = ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical

        guard FanControlRules.mustHandBackControl(
            chipTemperature: chipTemperature,
            secondsSinceLastReading: elapsed,
            isThermallyPressured: isPressured
        ) == false else {
            handBackControl(notice: handbackReason(
                chipTemperature: chipTemperature,
                elapsed: elapsed,
                isPressured: isPressured
            ))
            return
        }

        let fraction: Double?
        switch settings.mode {
        case .system:
            fraction = nil
        case .manual:
            fraction = settings.manualSpeedFraction
        case .curve:
            fraction = chipTemperature.flatMap {
                FanControlRules.speedFraction(atCelsius: $0, curve: settings.curve)
            }
        }
        guard let fraction else {
            handBackControl(notice: "Control returned to macOS: no chip reading to follow.")
            return
        }

        queue.async {
            let applied = hardware.apply(speedFraction: fraction)
            guard applied == false else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.handBackControl(notice: "The controller refused the speed change.")
                }
            }
        }
    }

    private func handbackReason(
        chipTemperature: Double?,
        elapsed: TimeInterval,
        isPressured: Bool
    ) -> String {
        if isPressured { return "Control returned to macOS: the Mac reported thermal pressure." }
        if chipTemperature == nil || elapsed > FanControlRules.sensorHandbackInterval {
            return "Control returned to macOS: sensor readings stopped."
        }
        return "Control returned to macOS: the chip reached its handback temperature."
    }

    private func handBackControl(notice: String) {
        let hardware = self.hardware
        queue.async { hardware?.handBackToSystem() }
        guard settings.mode != .system else { return }
        settings.mode = .system
        handbackNotice = notice
        logger.info("Fan control handed back to macOS")
    }
}
