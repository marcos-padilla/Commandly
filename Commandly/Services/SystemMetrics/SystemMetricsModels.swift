import Foundation

/// How hard the system is working to keep memory available.
nonisolated enum MemoryPressure: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical
    case unknown

    /// Maps the kernel's `kern.memorystatus_vm_pressure_level` value.
    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

/// The memory breakdown the panel shows.
nonisolated struct MemoryUsage: Sendable, Equatable {
    /// Memory in use, the way Activity Monitor counts it: app memory, wired, and compressor.
    let usedBytes: UInt64
    /// Memory apps hold that the system cannot simply reclaim.
    let applicationBytes: UInt64
    let totalBytes: UInt64
    /// Physical RAM held by the compressor. Already counted inside `usedBytes`.
    let compressedBytes: UInt64
    /// File-backed pages the system can drop. `usedBytes` already excludes them.
    let cachedFileBytes: UInt64
    /// `nil` when swap usage could not be read.
    let swapUsedBytes: UInt64?
    let pressure: MemoryPressure

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }
}

/// One complete reading of the machine's load.
///
/// Every value is optional because each source can be unavailable on its own: a Mac with no
/// readable sensors still reports processor load, and a sandboxed process that cannot open the
/// SMC still reports everything else.
nonisolated struct SystemMetricsSnapshot: Sendable, Equatable {
    let sampledAt: Date
    /// Processor load across all cores, `0...1`.
    let processorUsage: Double?
    /// Graphics load, `0...1`.
    let graphicsUsage: Double?
    /// Degrees Celsius.
    let processorTemperature: Double?
    let graphicsTemperature: Double?
    let memory: MemoryUsage?
    /// Seconds since the Mac started.
    let uptime: TimeInterval?

    static let empty = SystemMetricsSnapshot(
        sampledAt: .distantPast,
        processorUsage: nil,
        graphicsUsage: nil,
        processorTemperature: nil,
        graphicsTemperature: nil,
        memory: nil,
        uptime: nil
    )
}

/// Formatting and derivation rules for the System panel, kept apart from the readers so they can
/// be exercised without a machine to measure.
nonisolated enum SystemMetricsFormat {
    /// How many samples each sparkline keeps.
    static let historyLength = 60

    /// Memory in use: app memory, plus wired pages, plus whatever the compressor holds.
    static func memoryUsed(
        totalBytes: UInt64,
        applicationBytes: UInt64,
        pageSize: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64
    ) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let wired = wiredPages.multipliedReportingOverflow(by: pageSize)
        guard wired.overflow == false else { return 0 }
        let compressed = compressorPages.multipliedReportingOverflow(by: pageSize)
        guard compressed.overflow == false else { return 0 }

        let appAndWired = applicationBytes.addingReportingOverflow(wired.partialValue)
        guard appAndWired.overflow == false else { return 0 }
        let total = appAndWired.partialValue.addingReportingOverflow(compressed.partialValue)
        guard total.overflow == false else { return 0 }
        return min(total.partialValue, totalBytes)
    }

    /// App memory. Purgeable internal pages do not count, because the system can reclaim them
    /// without asking the app.
    static func applicationMemory(
        totalBytes: UInt64,
        pageSize: UInt64,
        internalPages: UInt64,
        purgeablePages: UInt64
    ) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let activePages = internalPages.subtractingReportingOverflow(purgeablePages)
        guard activePages.overflow == false else { return 0 }
        let bytes = activePages.partialValue.multipliedReportingOverflow(by: pageSize)
        guard bytes.overflow == false else { return 0 }
        return min(bytes.partialValue, totalBytes)
    }

    static func pageBytes(pageCount: UInt64, pageSize: UInt64, totalBytes: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let bytes = pageCount.multipliedReportingOverflow(by: pageSize)
        guard bytes.overflow == false else { return 0 }
        return min(bytes.partialValue, totalBytes)
    }

    /// Byte counts the way macOS writes them, so the panel reads like the rest of the system.
    static func byteText(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "Zero KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Total RAM, rounded to the whole number people know their Mac by.
    static func totalMemoryText(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        guard gigabytes >= 1 else { return byteText(bytes) }
        return "\(Int(gigabytes.rounded())) GB"
    }

    static func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    static func temperatureText(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        return "\(Int(celsius.rounded())) °C"
    }

    /// "Up for 6d 13h", falling back to hours and minutes on a Mac that started recently.
    static func uptimeText(_ uptime: TimeInterval?) -> String? {
        guard let uptime, uptime > 0 else { return nil }
        let total = Int(uptime)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "Up for \(days)d \(hours)h" }
        if hours > 0 { return "Up for \(hours)h \(minutes)m" }
        return "Up for \(minutes)m"
    }

    /// Keeps a rolling history at `historyLength` samples, oldest first.
    static func appending(_ value: Double?, to history: [Double]) -> [Double] {
        guard let value else { return history }
        var next = history
        next.append(min(max(value, 0), 1))
        if next.count > historyLength {
            next.removeFirst(next.count - historyLength)
        }
        return next
    }
}
