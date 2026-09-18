import DesignSystem
import SwiftUI

/// System tab: chip temperatures, processor and graphics load, the memory breakdown, and uptime.
struct SystemPanelSection: View {
    @Bindable var monitor: SystemMetricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            temperatures

            Divider()

            hardwareUsage

            Divider()

            memory

            if let uptime = SystemMetricsFormat.uptimeText(monitor.snapshot.uptime) {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(uptime)
                        .commandlyFont(size: 11.5, weight: .medium)
                    Spacer(minLength: 0)
                }
            }
        }
        .statusPanelCard()
        .onAppear { monitor.addObserver() }
        .onDisappear { monitor.removeObserver() }
    }

    // MARK: - Temperatures

    private var temperatures: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("Temperatures")

            if monitor.hasTemperatureSensors {
                HStack(spacing: 8) {
                    temperatureTile(
                        title: "CPU",
                        symbolName: "cpu",
                        celsius: monitor.snapshot.processorTemperature
                    )
                    temperatureTile(
                        title: "GPU",
                        symbolName: "cpu.fill",
                        celsius: monitor.snapshot.graphicsTemperature
                    )
                }
            } else {
                Text("This Mac does not expose its temperature sensors to Commandly.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func temperatureTile(title: String, symbolName: String, celsius: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            Text(SystemMetricsFormat.temperatureText(celsius))
                .commandlyFont(size: 17, weight: .semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LauncherPalette.hover)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) temperature")
        .accessibilityValue(SystemMetricsFormat.temperatureText(celsius))
    }

    // MARK: - Hardware usage

    private var hardwareUsage: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("Hardware usage")

            usageRow(
                title: "CPU",
                fraction: monitor.snapshot.processorUsage,
                history: monitor.processorHistory,
                tint: CommandlyTint.blue.color
            )

            usageRow(
                title: "GPU",
                fraction: monitor.snapshot.graphicsUsage,
                history: monitor.graphicsHistory,
                tint: CommandlyTint.cyan.color
            )
        }
    }

    @ViewBuilder
    private func usageRow(
        title: String,
        fraction: Double?,
        history: [Double],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Spacing.xs.rawValue) {
                Text(title)
                    .commandlyFont(size: 12, weight: .medium)
                    .frame(width: 42, alignment: .leading)

                PanelMeter(fraction: fraction ?? 0, tint: tint)

                Text(SystemMetricsFormat.percentText(fraction))
                    .commandlyFont(size: 12, weight: .semibold)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) usage")
            .accessibilityValue(SystemMetricsFormat.percentText(fraction))

            if history.count >= 2 {
                PanelSparkline(values: history, tint: tint, height: 30)
            }
        }
    }

    // MARK: - Memory

    @ViewBuilder
    private var memory: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("Memory")

            if let memory = monitor.snapshot.memory {
                HStack(spacing: Spacing.xs.rawValue) {
                    Text("Pressure")
                        .commandlyFont(size: 12, weight: .medium)
                    pressureBadge(memory.pressure)
                    Spacer(minLength: Spacing.xs.rawValue)
                    Text(
                        "\(SystemMetricsFormat.byteText(memory.usedBytes)) / \(SystemMetricsFormat.totalMemoryText(memory.totalBytes))"
                    )
                    .commandlyFont(size: 12, weight: .medium)
                    .monospacedDigit()
                }

                detailRow("Compressed", value: SystemMetricsFormat.byteText(memory.compressedBytes))
                detailRow("Cached files", value: SystemMetricsFormat.byteText(memory.cachedFileBytes))
                detailRow(
                    "Swap used",
                    value: memory.swapUsedBytes.map(SystemMetricsFormat.byteText) ?? "—"
                )

                if monitor.memoryHistory.count >= 2 {
                    PanelSparkline(
                        values: monitor.memoryHistory,
                        tint: CommandlyTint.mint.color,
                        height: 30
                    )
                }
            } else {
                Text("Memory statistics are unavailable.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pressureBadge(_ pressure: MemoryPressure) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(pressureTint(pressure))
                .frame(width: 6, height: 6)
            Text(pressure.title)
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(pressureTint(pressure))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(pressureTint(pressure).opacity(0.14)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory pressure")
        .accessibilityValue(pressure.title)
    }

    private func pressureTint(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return CommandlyTint.green.color
        case .warning: return CommandlyTint.yellow.color
        case .critical: return CommandlyTint.red.color
        case .unknown: return CommandlyTint.graphite.color
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text(title)
                .commandlyFont(size: 11.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs.rawValue)
            Text(value)
                .commandlyFont(size: 11.5, weight: .medium)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func blockTitle(_ title: String) -> some View {
        Text(title)
            .commandlyFont(size: 12, weight: .semibold)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}
