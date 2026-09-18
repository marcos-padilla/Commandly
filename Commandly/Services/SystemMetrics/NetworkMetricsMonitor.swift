import Darwin
import Foundation
import Observation

/// Cumulative byte counters summed across the interfaces that carry real traffic.
nonisolated struct NetworkCounters: Equatable, Sendable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
}

/// One network reading: current speed plus what this session has moved.
nonisolated struct NetworkReading: Equatable, Sendable {
    /// `nil` until there is a previous sample to measure against.
    let downloadBytesPerSecond: Double?
    let uploadBytesPerSecond: Double?
    /// Accumulated since Commandly started watching, not since the Mac booted.
    let sessionDownloadBytes: UInt64
    let sessionUploadBytes: UInt64

    static let empty = NetworkReading(
        downloadBytesPerSecond: nil,
        uploadBytesPerSecond: nil,
        sessionDownloadBytes: 0,
        sessionUploadBytes: 0
    )
}

/// Which interfaces count toward "the network", and how their counters become a speed.
nonisolated enum NetworkMetricsRules {
    /// After a gap this long — sampling was paused, the Mac slept — the previous reading is
    /// treated as a fresh baseline instead of producing a spike that never happened.
    static let maximumSampleGap: TimeInterval = 10

    /// Loopback and virtual interfaces carry traffic that never leaves the Mac, and counting
    /// them makes local development look like network use.
    static func includesInterface(_ name: String) -> Bool {
        let excludedPrefixes = ["lo", "gif", "stf", "utun", "awdl", "llw", "bridge", "ap", "anpi"]
        return excludedPrefixes.contains { name.hasPrefix($0) } == false
    }

    /// Bytes per second between two counter readings. Counters that went backwards mean an
    /// interface was reset, which is a new baseline rather than negative traffic.
    static func speed(
        previous: NetworkCounters,
        current: NetworkCounters,
        elapsed: TimeInterval
    ) -> (down: Double?, up: Double?) {
        guard elapsed > 0 else { return (nil, nil) }
        let down = current.received >= previous.received
            ? Double(current.received - previous.received) / elapsed
            : nil
        let up = current.sent >= previous.sent
            ? Double(current.sent - previous.sent) / elapsed
            : nil
        return (down, up)
    }

    /// A transfer rate the way macOS writes it.
    static func rateText(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.isAdaptive = false
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    static func totalText(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Scales a rate history to `0...1` against its own peak, so a quiet period does not draw a
    /// flat line and a busy one does not clip.
    static func normalized(_ history: [Double]) -> [Double] {
        guard let peak = history.max(), peak > 0 else {
            return Array(repeating: 0, count: history.count)
        }
        return history.map { min(1, max(0, $0 / peak)) }
    }
}

/// Samples interface counters and derives speed and session totals.
///
/// `@unchecked Sendable`: the previous counters and running totals are the only mutable state
/// and the monitor confines every call to one serial queue.
nonisolated final class NetworkSampler: @unchecked Sendable {
    private var previous: (counters: NetworkCounters, time: TimeInterval)?
    private var sessionDownload: UInt64 = 0
    private var sessionUpload: UInt64 = 0
    private let readCounters: @Sendable () -> NetworkCounters?

    init(
        readCounters: @escaping @Sendable () -> NetworkCounters? = NetworkSampler.currentCounters
    ) {
        self.readCounters = readCounters
    }

    func sample(now: TimeInterval) -> NetworkReading {
        guard let counters = readCounters() else {
            return NetworkReading(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                sessionDownloadBytes: sessionDownload,
                sessionUploadBytes: sessionUpload
            )
        }
        defer { previous = (counters, now) }

        guard let previous,
              now > previous.time,
              now - previous.time <= NetworkMetricsRules.maximumSampleGap else {
            return NetworkReading(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                sessionDownloadBytes: sessionDownload,
                sessionUploadBytes: sessionUpload
            )
        }

        let speed = NetworkMetricsRules.speed(
            previous: previous.counters,
            current: counters,
            elapsed: now - previous.time
        )
        if counters.received >= previous.counters.received {
            sessionDownload &+= counters.received - previous.counters.received
        }
        if counters.sent >= previous.counters.sent {
            sessionUpload &+= counters.sent - previous.counters.sent
        }

        return NetworkReading(
            downloadBytesPerSecond: speed.down,
            uploadBytesPerSecond: speed.up,
            sessionDownloadBytes: sessionDownload,
            sessionUploadBytes: sessionUpload
        )
    }

    /// Sums received and sent bytes across the physical interfaces through the routing socket.
    ///
    /// `NET_RT_IFLIST2` reports 64-bit counters; the 32-bit counters `getifaddrs` returns wrap
    /// after a few gigabytes and corrupt any total built on them.
    static func currentCounters() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var result = NetworkCounters()
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = base.advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr.self).pointee
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.advanced(by: offset)
                        .assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil,
                       NetworkMetricsRules.includesInterface(String(cString: nameBuffer)) {
                        result.received &+= info.ifm_data.ifi_ibytes
                        result.sent &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }
        return result
    }
}

/// Live network throughput for the panel, with a short history for its chart.
@Observable
@MainActor
final class NetworkMetricsMonitor {
    private(set) var reading: NetworkReading = .empty
    /// Download rate history in bytes per second, oldest first.
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []

    /// The last finished speed test, kept so the panel still shows a result after reopening.
    private(set) var speedTestResult: NetworkSpeedTestResult?
    private(set) var isRunningSpeedTest = false
    private(set) var speedTestError: String?

    private let sampler: NetworkSampler
    private let speedTest: NetworkSpeedTest
    private let interval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.businessmate360.Commandly.network-metrics",
        qos: .utility
    )
    private var timer: Timer?
    private var observers = 0
    private var speedTestTask: Task<Void, Never>?

    init(
        sampler: NetworkSampler = NetworkSampler(),
        speedTest: NetworkSpeedTest = NetworkSpeedTest(),
        interval: TimeInterval = 1
    ) {
        self.sampler = sampler
        self.speedTest = speedTest
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
        speedTestTask?.cancel()
        speedTestTask = nil
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async {
            let reading = self.sampler.sample(now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.publish(reading) }
            }
        }
    }

    private func publish(_ reading: NetworkReading) {
        self.reading = reading
        downloadHistory = appending(reading.downloadBytesPerSecond, to: downloadHistory)
        uploadHistory = appending(reading.uploadBytesPerSecond, to: uploadHistory)
    }

    private func appending(_ value: Double?, to history: [Double]) -> [Double] {
        var next = history
        next.append(max(0, value ?? 0))
        if next.count > SystemMetricsFormat.historyLength {
            next.removeFirst(next.count - SystemMetricsFormat.historyLength)
        }
        return next
    }

    /// Measures the connection. Always user-initiated: the test moves real data over the
    /// network, so it never runs on its own.
    func runSpeedTest() {
        guard isRunningSpeedTest == false else { return }
        isRunningSpeedTest = true
        speedTestError = nil
        speedTestTask?.cancel()
        speedTestTask = Task { [speedTest] in
            do {
                let result = try await speedTest.run()
                guard Task.isCancelled == false else { return }
                speedTestResult = result
                speedTestError = nil
            } catch is CancellationError {
                // Leaving the tab cancels the test; nothing to report.
            } catch {
                speedTestError = "The speed test could not finish."
            }
            isRunningSpeedTest = false
            speedTestTask = nil
        }
    }
}
