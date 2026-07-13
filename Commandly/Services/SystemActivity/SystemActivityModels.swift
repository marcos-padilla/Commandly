import Foundation

/// A stable, UI-safe representation of macOS thermal pressure.
nonisolated enum SystemThermalState: String, CaseIterable, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var title: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

/// One immutable aggregate resource sample.
nonisolated struct SystemResourceSnapshot: Sendable, Equatable {
    let sampledAt: Date
    let cpuUsage: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let diskUsedBytes: UInt64
    let diskTotalBytes: UInt64
    let systemUptime: TimeInterval
    let thermalState: SystemThermalState

    init(
        sampledAt: Date,
        cpuUsage: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        diskUsedBytes: UInt64,
        diskTotalBytes: UInt64,
        systemUptime: TimeInterval,
        thermalState: SystemThermalState
    ) {
        self.sampledAt = sampledAt
        self.cpuUsage = min(max(cpuUsage, 0), 1)
        self.memoryUsedBytes = min(memoryUsedBytes, memoryTotalBytes)
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedBytes = min(diskUsedBytes, diskTotalBytes)
        self.diskTotalBytes = diskTotalBytes
        self.systemUptime = max(systemUptime, 0)
        self.thermalState = thermalState
    }
}

/// One immutable regular GUI-application sample.
nonisolated struct SystemApplicationSnapshot: Identifiable, Sendable, Equatable, Hashable {
    var id: Int32 { processIdentifier }

    let processIdentifier: Int32
    let bundleIdentifier: String?
    let localizedName: String
    let isFrontmost: Bool
    let isHidden: Bool

    init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        localizedName: String,
        isFrontmost: Bool,
        isHidden: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isFrontmost = isFrontmost
        self.isHidden = isHidden
    }
}

/// A coherent resource and running-application sample returned by the service.
nonisolated struct SystemActivitySnapshot: Sendable, Equatable {
    let resources: SystemResourceSnapshot
    let applications: [SystemApplicationSnapshot]

    init(resources: SystemResourceSnapshot, applications: [SystemApplicationSnapshot]) {
        self.resources = resources
        self.applications = applications
    }
}

nonisolated enum SystemApplicationTerminationMode: Sendable, Equatable {
    case graceful
    case force
}

/// Narrow native boundary used by the System Activity application and deterministic tests.
nonisolated protocol SystemActivityServicing: Sendable {
    func snapshot() async throws -> SystemActivitySnapshot

    @discardableResult
    func activate(processIdentifier: Int32) async -> Bool

    @discardableResult
    func terminate(
        processIdentifier: Int32,
        mode: SystemApplicationTerminationMode
    ) async -> Bool
}

nonisolated enum SystemActivityServiceError: LocalizedError, Sendable, Equatable {
    case cpuSampleUnavailable
    case memorySampleUnavailable
    case diskSampleUnavailable

    var errorDescription: String? {
        switch self {
        case .cpuSampleUnavailable:
            return "CPU usage is unavailable."
        case .memorySampleUnavailable:
            return "Memory usage is unavailable."
        case .diskSampleUnavailable:
            return "Storage usage is unavailable."
        }
    }
}
