import AppKit
import Foundation
import IOKit
import IOKit.storage
import Observation

/// One mounted volume the panel can show.
nonisolated struct DiskVolume: Identifiable, Equatable, Sendable {
    /// The mount path, which is what identifies a volume for as long as it is mounted.
    var id: String { url.path }

    let url: URL
    let name: String
    /// File system name, such as APFS or HFS+.
    let fileSystem: String?
    let isInternal: Bool
    let isRemovable: Bool
    let totalBytes: UInt64
    /// Space a new file can actually claim, which is what Finder shows as available.
    let availableBytes: UInt64
    /// Space held by caches the system will reclaim when something needs it.
    let purgeableBytes: UInt64?

    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }
}

/// Cumulative block-storage byte counters for the whole Mac.
nonisolated struct DiskCounters: Equatable, Sendable {
    var read: UInt64 = 0
    var written: UInt64 = 0
}

/// One disk activity reading.
nonisolated struct DiskActivityReading: Equatable, Sendable {
    let readBytesPerSecond: Double?
    let writeBytesPerSecond: Double?
    let sessionReadBytes: UInt64
    let sessionWrittenBytes: UInt64

    static let empty = DiskActivityReading(
        readBytesPerSecond: nil,
        writeBytesPerSecond: nil,
        sessionReadBytes: 0,
        sessionWrittenBytes: 0
    )
}

/// Reads mounted volumes and block-storage throughput.
///
/// `@unchecked Sendable`: the previous counters and running totals are the only mutable state,
/// and the monitor confines every call to one serial queue.
nonisolated final class DiskSampler: @unchecked Sendable {
    private var previous: (counters: DiskCounters, time: TimeInterval)?
    private var sessionRead: UInt64 = 0
    private var sessionWritten: UInt64 = 0

    /// After a gap this long the previous reading becomes a fresh baseline rather than a spike.
    private static let maximumSampleGap: TimeInterval = 10

    func sampleActivity(now: TimeInterval) -> DiskActivityReading {
        guard let counters = Self.currentCounters() else {
            return DiskActivityReading(
                readBytesPerSecond: nil,
                writeBytesPerSecond: nil,
                sessionReadBytes: sessionRead,
                sessionWrittenBytes: sessionWritten
            )
        }
        defer { previous = (counters, now) }

        guard let previous,
              now > previous.time,
              now - previous.time <= Self.maximumSampleGap else {
            return DiskActivityReading(
                readBytesPerSecond: nil,
                writeBytesPerSecond: nil,
                sessionReadBytes: sessionRead,
                sessionWrittenBytes: sessionWritten
            )
        }

        let elapsed = now - previous.time
        let read = counters.read >= previous.counters.read
            ? Double(counters.read - previous.counters.read) / elapsed
            : nil
        let written = counters.written >= previous.counters.written
            ? Double(counters.written - previous.counters.written) / elapsed
            : nil

        if counters.read >= previous.counters.read {
            sessionRead &+= counters.read - previous.counters.read
        }
        if counters.written >= previous.counters.written {
            sessionWritten &+= counters.written - previous.counters.written
        }

        return DiskActivityReading(
            readBytesPerSecond: read,
            writeBytesPerSecond: written,
            sessionReadBytes: sessionRead,
            sessionWrittenBytes: sessionWritten
        )
    }

    /// Bytes read and written, summed across every block-storage driver in the IO registry.
    static func currentCounters() -> DiskCounters? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var counters = DiskCounters()
        var sawDriver = false
        // The advance lives in the condition so the `defer` only releases; advancing inside it
        // would take a reference on the next service that nothing releases.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let reference = IORegistryEntryCreateCFProperty(
                entry,
                kIOBlockStorageDriverStatisticsKey as CFString,
                kCFAllocatorDefault,
                0
            ), let statistics = reference.takeRetainedValue() as? [String: Any] else { continue }

            sawDriver = true
            if let read = statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber {
                counters.read &+= read.uint64Value
            }
            if let written = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                counters.written &+= written.uint64Value
            }
        }
        return sawDriver ? counters : nil
    }

    /// Every mounted volume the user can see, newest capacity figures included.
    static func mountedVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url -> DiskVolume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }

            let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
            let plain = values.volumeAvailableCapacity.map { UInt64($0) }
            let available = important ?? plain ?? 0
            // Everything the system would reclaim before reporting the disk full: the gap
            // between what is free right now and what a large file could actually claim.
            let purgeable: UInt64? = {
                guard let important, let plain, important > plain else { return nil }
                return important - plain
            }()

            return DiskVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                fileSystem: values.volumeLocalizedFormatDescription,
                isInternal: values.volumeIsInternal ?? false,
                isRemovable: (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false),
                totalBytes: UInt64(total),
                availableBytes: available,
                purgeableBytes: purgeable
            )
        }
        .sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Volumes and disk throughput for the panel.
@Observable
@MainActor
final class DiskMetricsMonitor {
    private(set) var volumes: [DiskVolume] = []
    private(set) var activity: DiskActivityReading = .empty
    private(set) var readHistory: [Double] = []
    private(set) var writeHistory: [Double] = []
    /// The volume whose detail the panel shows. Falls back to the first one listed.
    var selectedVolumeID: String?
    /// Set when an eject could not finish, so the panel can say which volume refused.
    private(set) var ejectError: String?

    var selectedVolume: DiskVolume? {
        volumes.first { $0.id == selectedVolumeID } ?? volumes.first
    }

    var ejectableVolumes: [DiskVolume] {
        volumes.filter { $0.isRemovable && $0.isInternal == false }
    }

    private let sampler: DiskSampler
    private let interval: TimeInterval
    private let queue = DispatchQueue(
        label: "com.businessmate360.Commandly.disk-metrics",
        qos: .utility
    )
    private var timer: Timer?
    private var observers = 0
    /// Volumes change far less often than throughput does, so they are re-read every few ticks.
    private var ticksSinceVolumeRefresh = 0
    private static let volumeRefreshTicks = 5

    init(sampler: DiskSampler = DiskSampler(), interval: TimeInterval = 1) {
        self.sampler = sampler
        self.interval = interval
    }

    func addObserver() {
        observers += 1
        guard timer == nil else { return }
        refreshVolumes()
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
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

    /// Unmounts and ejects one removable volume.
    func eject(_ volume: DiskVolume) {
        ejectError = nil
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            refreshVolumes()
        } catch {
            ejectError = "\(volume.name) could not be ejected. It may still be in use."
        }
    }

    /// Ejects every removable volume, reporting the ones that refused.
    func ejectAll() {
        ejectError = nil
        var refused: [String] = []
        for volume in ejectableVolumes {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            } catch {
                refused.append(volume.name)
            }
        }
        refreshVolumes()
        if refused.isEmpty == false {
            ejectError = "\(refused.joined(separator: ", ")) could not be ejected."
        }
    }

    func revealInFinder(_ volume: DiskVolume) {
        NSWorkspace.shared.open(volume.url)
    }

    private func tick() {
        ticksSinceVolumeRefresh += 1
        if ticksSinceVolumeRefresh >= Self.volumeRefreshTicks {
            ticksSinceVolumeRefresh = 0
            refreshVolumes()
        }
        sample()
    }

    private func refreshVolumes() {
        queue.async {
            let volumes = DiskSampler.mountedVolumes()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.volumes != volumes { self.volumes = volumes }
                    if let selectedVolumeID = self.selectedVolumeID,
                       volumes.contains(where: { $0.id == selectedVolumeID }) == false {
                        self.selectedVolumeID = volumes.first?.id
                    }
                }
            }
        }
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async {
            let activity = self.sampler.sampleActivity(now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.publish(activity) }
            }
        }
    }

    private func publish(_ activity: DiskActivityReading) {
        self.activity = activity
        readHistory = appending(activity.readBytesPerSecond, to: readHistory)
        writeHistory = appending(activity.writeBytesPerSecond, to: writeHistory)
    }

    private func appending(_ value: Double?, to history: [Double]) -> [Double] {
        var next = history
        next.append(max(0, value ?? 0))
        if next.count > SystemMetricsFormat.historyLength {
            next.removeFirst(next.count - SystemMetricsFormat.historyLength)
        }
        return next
    }
}
