import Foundation
import Observation

/// Samples the machine's load on an interval and keeps a short history for the panel's charts.
///
/// Sampling only runs while something is watching: the panel calls `addObserver` when a section
/// appears and `removeObserver` when it goes away, so a closed menu bar panel costs nothing.
@Observable
@MainActor
final class SystemMetricsMonitor {
    private(set) var snapshot: SystemMetricsSnapshot = .empty
    /// Rolling processor load, oldest first, `0...1`.
    private(set) var processorHistory: [Double] = []
    private(set) var graphicsHistory: [Double] = []
    /// Rolling share of memory in use, oldest first, `0...1`.
    private(set) var memoryHistory: [Double] = []
    /// False when this Mac exposes no readable temperature sensors to Commandly.
    private(set) var hasTemperatureSensors = false

    private let reader: SystemMetricsReader
    private let interval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.businessmate360.Commandly.system-metrics",
        qos: .utility
    )
    private var timer: Timer?
    private var observers = 0
    private var isSampling = false

    init(
        reader: SystemMetricsReader = SystemMetricsReader(),
        interval: TimeInterval = 2
    ) {
        self.reader = reader
        self.interval = interval
    }

    /// Starts sampling for one watcher, taking a first sample right away so the panel is never
    /// blank while it waits for the first tick.
    func addObserver() {
        observers += 1
        guard timer == nil else { return }
        hasTemperatureSensors = reader.hasTemperatureSensors
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.sample() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func removeObserver() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers = 0
    }

    private func sample() {
        // Kernel and registry reads are cheap but not free, and the SMC can take milliseconds
        // per key, so a tick never runs on the main actor.
        guard isSampling == false else { return }
        isSampling = true
        queue.async {
            let snapshot = self.reader.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.publish(snapshot) }
            }
        }
    }

    private func publish(_ snapshot: SystemMetricsSnapshot) {
        isSampling = false
        self.snapshot = snapshot
        processorHistory = SystemMetricsFormat.appending(
            snapshot.processorUsage,
            to: processorHistory
        )
        graphicsHistory = SystemMetricsFormat.appending(
            snapshot.graphicsUsage,
            to: graphicsHistory
        )
        memoryHistory = SystemMetricsFormat.appending(
            snapshot.memory?.usedFraction,
            to: memoryHistory
        )
    }
}
