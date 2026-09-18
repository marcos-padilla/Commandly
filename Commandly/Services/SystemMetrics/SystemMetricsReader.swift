import Darwin
import Foundation
import IOKit

/// Reads one sample of processor, graphics, and memory load from the kernel and the IO registry.
///
/// Everything here is a synchronous kernel or registry call, so the monitor runs it off the main
/// actor. The reader keeps the previous processor tick counts, because processor load is a
/// difference between two readings rather than a value the kernel publishes directly.
///
/// `@unchecked Sendable`: the only mutable state is the previous tick count, and the monitor
/// confines every call to its own serial queue.
nonisolated final class SystemMetricsReader: @unchecked Sendable {
    private struct ProcessorTicks: Equatable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        var total: UInt64 { user &+ system &+ idle &+ nice }
        var busy: UInt64 { user &+ system &+ nice }

        func delta(since previous: ProcessorTicks) -> ProcessorTicks {
            ProcessorTicks(
                user: user &- previous.user,
                system: system &- previous.system,
                idle: idle &- previous.idle,
                nice: nice &- previous.nice
            )
        }
    }

    private var previousTicks: ProcessorTicks?
    private let temperatures: TemperatureSensorReader?

    init(temperatures: TemperatureSensorReader? = TemperatureSensorReader()) {
        self.temperatures = temperatures
    }

    /// Whether temperature sensors could be reached at all on this Mac.
    var hasTemperatureSensors: Bool { temperatures?.isAvailable ?? false }

    func sample() -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            sampledAt: Date(),
            processorUsage: processorUsage(),
            graphicsUsage: Self.graphicsUsage(),
            processorTemperature: temperatures?.processorTemperature(),
            graphicsTemperature: temperatures?.graphicsTemperature(),
            memory: Self.memoryUsage(),
            uptime: Self.uptime()
        )
    }

    // MARK: - Processor

    /// Load across all cores since the previous sample. The first sample after a start has no
    /// predecessor, so it reports load since boot, which settles within one tick.
    private func processorUsage() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let current = ProcessorTicks(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
        let measured = previousTicks.map { current.delta(since: $0) } ?? current
        previousTicks = current
        guard measured.total > 0 else { return nil }
        return min(1, Double(measured.busy) / Double(measured.total))
    }

    // MARK: - Graphics

    /// "Device Utilization %", published by the graphics accelerator in the IO registry.
    private static func graphicsUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        // The advance lives in the `while` condition so the `defer` only releases. With the
        // advance inside the defer, returning from the loop would release the entry it was done
        // with and then take a reference on the next service that nothing releases — one leaked
        // object per sample on a Mac with two accelerators.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            // Only the performance statistics, never the whole property tree: copying every
            // property each tick is what makes continuous graphics sampling expensive.
            guard let reference = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ), let statistics = reference.takeRetainedValue() as? [String: Any],
                  let utilization = statistics["Device Utilization %"] as? Int else { continue }
            return min(1, Double(utilization) / 100)
        }
        return nil
    }

    // MARK: - Memory

    private static func memoryUsage() -> MemoryUsage? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        let total = ProcessInfo.processInfo.physicalMemory
        let page = UInt64(pageSize)
        let applicationBytes = SystemMetricsFormat.applicationMemory(
            totalBytes: total,
            pageSize: page,
            internalPages: UInt64(statistics.internal_page_count),
            purgeablePages: UInt64(statistics.purgeable_count)
        )

        return MemoryUsage(
            usedBytes: SystemMetricsFormat.memoryUsed(
                totalBytes: total,
                applicationBytes: applicationBytes,
                pageSize: page,
                wiredPages: UInt64(statistics.wire_count),
                compressorPages: UInt64(statistics.compressor_page_count)
            ),
            applicationBytes: applicationBytes,
            totalBytes: total,
            compressedBytes: SystemMetricsFormat.pageBytes(
                pageCount: UInt64(statistics.compressor_page_count),
                pageSize: page,
                totalBytes: total
            ),
            cachedFileBytes: SystemMetricsFormat.pageBytes(
                pageCount: UInt64(statistics.external_page_count),
                pageSize: page,
                totalBytes: total
            ),
            swapUsedBytes: swapUsed(),
            pressure: memoryPressure()
        )
    }

    private static func swapUsed() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    private static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(kernelLevel: level)
    }

    // MARK: - Uptime

    private static func uptime() -> TimeInterval? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 else {
            // `systemUptime` is a monotonic clock that does not count time asleep, so it is the
            // fallback rather than the first choice.
            return ProcessInfo.processInfo.systemUptime
        }
        let booted = Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
        return max(0, Date().timeIntervalSince(booted))
    }
}
