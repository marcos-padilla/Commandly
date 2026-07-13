import AppKit
import Darwin
import Foundation

/// Remembers the external application that was active before Commandly raised its launcher.
///
/// Sampling `NSWorkspace.frontmostApplication` after the launcher opens would identify Commandly
/// itself. Keeping this small main-actor tracker lets destructive bulk actions continue to protect
/// the application the user was actually working in.
@MainActor
final class SystemActivityProtectionTracker {
    typealias ProcessIdentifierProvider = @MainActor () -> pid_t?

    private let commandlyProcessIdentifier: pid_t
    private let frontmostProcessIdentifier: ProcessIdentifierProvider
    private(set) var protectedProcessIdentifier: pid_t?

    init(
        commandlyProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        frontmostProcessIdentifier: @escaping ProcessIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.commandlyProcessIdentifier = commandlyProcessIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        captureFrontmostApplication()
    }

    func captureFrontmostApplication() {
        guard let processIdentifier = frontmostProcessIdentifier(),
              processIdentifier != commandlyProcessIdentifier else {
            return
        }
        protectedProcessIdentifier = processIdentifier
    }
}

/// Samples aggregate machine state away from the main actor and uses AppKit only for
/// short running-application lookups and actions.
actor NativeSystemActivityService: SystemActivityServicing {
    private nonisolated struct CPUTicks: Sendable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }

        func delta(since previous: CPUTicks) -> CPUTicks {
            CPUTicks(
                user: Self.delta(current: user, previous: previous.user),
                system: Self.delta(current: system, previous: previous.system),
                idle: Self.delta(current: idle, previous: previous.idle),
                nice: Self.delta(current: nice, previous: previous.nice)
            )
        }

        private static func delta(current: UInt64, previous: UInt64) -> UInt64 {
            current >= previous ? current - previous : current
        }
    }

    private var previousCPUTicks: CPUTicks?
    private let protectionTracker: SystemActivityProtectionTracker

    @MainActor
    init(protectionTracker: SystemActivityProtectionTracker = SystemActivityProtectionTracker()) {
        self.protectionTracker = protectionTracker
    }

    func snapshot() async throws -> SystemActivitySnapshot {
        try Task.checkCancellation()
        let resources = try resourceSnapshot()
        try Task.checkCancellation()
        let applications = await runningApplicationSnapshots()
        try Task.checkCancellation()
        return SystemActivitySnapshot(resources: resources, applications: applications)
    }

    func activate(processIdentifier: Int32) async -> Bool {
        await MainActor.run {
            guard let application = NSRunningApplication(processIdentifier: processIdentifier),
                  application.isTerminated == false else {
                return false
            }
            return application.activate(options: [.activateAllWindows])
        }
    }

    func terminate(
        processIdentifier: Int32,
        mode: SystemApplicationTerminationMode
    ) async -> Bool {
        await MainActor.run {
            guard let application = NSRunningApplication(processIdentifier: processIdentifier),
                  application.isTerminated == false else {
                return false
            }
            switch mode {
            case .graceful:
                return application.terminate()
            case .force:
                return application.forceTerminate()
            }
        }
    }

    private func resourceSnapshot() throws -> SystemResourceSnapshot {
        let cpuUsage = try sampleCPUUsage()
        let memory = try sampleMemory()
        let disk = try sampleDisk()
        let processInfo = ProcessInfo.processInfo
        return SystemResourceSnapshot(
            sampledAt: Date(),
            cpuUsage: cpuUsage,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            systemUptime: processInfo.systemUptime,
            thermalState: Self.thermalState(from: processInfo.thermalState)
        )
    }

    private func sampleCPUUsage() throws -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SystemActivityServiceError.cpuSampleUnavailable
        }

        let current = CPUTicks(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
        let measured = previousCPUTicks.map { current.delta(since: $0) } ?? current
        previousCPUTicks = current
        guard measured.total > 0 else { return 0 }
        return Double(measured.busy) / Double(measured.total)
    }

    private func sampleMemory() throws -> (used: UInt64, total: UInt64) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SystemActivityServiceError.memorySampleUnavailable
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            throw SystemActivityServiceError.memorySampleUnavailable
        }

        let total = ProcessInfo.processInfo.physicalMemory
        let availablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let multiplied = availablePages.multipliedReportingOverflow(by: UInt64(pageSize))
        let available = multiplied.overflow ? total : min(multiplied.partialValue, total)
        return (used: total - available, total: total)
    }

    private func sampleDisk() throws -> (used: UInt64, total: UInt64) {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        } catch {
            throw SystemActivityServiceError.diskSampleUnavailable
        }
        guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            throw SystemActivityServiceError.diskSampleUnavailable
        }
        return (used: total >= free ? total - free : 0, total: total)
    }

    private func runningApplicationSnapshots() async -> [SystemApplicationSnapshot] {
        await MainActor.run {
            protectionTracker.captureFrontmostApplication()
            let frontmostPID = protectionTracker.protectedProcessIdentifier
                ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            return NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.isTerminated == false }
                .map { application in
                    SystemApplicationSnapshot(
                        processIdentifier: application.processIdentifier,
                        bundleIdentifier: application.bundleIdentifier,
                        localizedName: application.localizedName
                            ?? application.bundleIdentifier
                            ?? "Application",
                        isFrontmost: application.processIdentifier == frontmostPID,
                        isHidden: application.isHidden
                    )
                }
                .sorted {
                    $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName)
                        == .orderedAscending
                }
        }
    }

    private static func thermalState(from state: ProcessInfo.ThermalState) -> SystemThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
