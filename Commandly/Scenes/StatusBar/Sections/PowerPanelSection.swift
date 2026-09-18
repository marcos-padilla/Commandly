import DesignSystem
import SwiftUI

/// Power tab: charge, draw, and the battery's condition.
struct PowerPanelSection: View {
    @Bindable var monitor: PowerMetricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if monitor.hasBattery {
                batteryBlock
            } else {
                Text("This Mac has no internal battery, so there is no charge to report.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            energyApplications

            if monitor.reading.temperatureCelsius != nil {
                Divider()
                detailRow(
                    symbolName: "thermometer.medium",
                    tint: CommandlyTint.orange.color,
                    title: "Battery temperature",
                    caption: nil,
                    value: SystemMetricsFormat.temperatureText(monitor.reading.temperatureCelsius)
                )
            }

            Divider()

            systemDrawRow

            Divider()

            batteryFlowRow

            Divider()

            timeRemainingRow

            Divider()

            healthRow
        }
        .statusPanelCard()
        .onAppear { monitor.addObserver() }
        .onDisappear { monitor.removeObserver() }
    }

    // MARK: - Charge

    private var batteryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: batterySymbol)
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Battery")
                    .commandlyFont(size: 12, weight: .medium)

                PanelMeter(fraction: chargeFraction, tint: chargeTint)

                Text(
                    monitor.reading.chargePercent.map { "\($0)%" } ?? "—"
                )
                .commandlyFont(size: 12, weight: .semibold)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery charge")

            if monitor.chargeHistory.count >= 2 {
                PanelSparkline(values: monitor.chargeHistory, tint: chargeTint, height: 28)
            }
        }
    }

    private var chargeFraction: Double {
        Double(monitor.reading.chargePercent ?? 0) / 100
    }

    private var chargeTint: Color {
        if monitor.reading.isCharging { return CommandlyTint.green.color }
        switch monitor.reading.chargePercent ?? 100 {
        case ..<10: return CommandlyTint.red.color
        case ..<20: return CommandlyTint.yellow.color
        default: return CommandlyTint.green.color
        }
    }

    private var batterySymbol: String {
        if monitor.reading.isCharging { return "battery.100.bolt" }
        switch monitor.reading.chargePercent ?? 100 {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<70: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    // MARK: - Rows

    private var energyApplications: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Apps using significant energy")
                .commandlyFont(size: 11.5, weight: .medium)
                .foregroundStyle(.secondary)
            Text("Per-app energy impact needs a process interface App Sandbox does not grant, so Commandly reports the totals below instead.")
                .commandlyFont(size: 10)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var systemDrawRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            detailRow(
                symbolName: "bolt.fill",
                tint: CommandlyTint.orange.color,
                title: "System",
                caption: monitor.reading.systemWatts == nil
                    ? "Measured only while the Mac runs on battery."
                    : nil,
                value: PowerMetricsRules.wattsText(monitor.reading.systemWatts)
            )
            if monitor.systemWattsHistory.count >= 2 {
                PanelSparkline(
                    values: normalizedWatts,
                    tint: CommandlyTint.orange.color,
                    height: 26,
                    isFilled: false
                )
            }
        }
    }

    /// Watt history scaled against its own peak, so the line has shape whatever the machine draws.
    private var normalizedWatts: [Double] {
        NetworkMetricsRules.normalized(monitor.systemWattsHistory)
    }

    private var batteryFlowRow: some View {
        detailRow(
            symbolName: "battery.50",
            tint: .secondary,
            title: "Battery",
            caption: batteryFlowCaption,
            value: PowerMetricsRules.wattsText(monitor.reading.batteryWatts.map(abs))
        )
    }

    private var batteryFlowCaption: String? {
        guard monitor.hasBattery else { return nil }
        if monitor.reading.isCharging { return "Charging" }
        return monitor.reading.isPluggedIn ? "Plugged in" : "On battery"
    }

    private var timeRemainingRow: some View {
        detailRow(
            symbolName: "clock",
            tint: CommandlyTint.green.color,
            title: "Battery time remaining",
            caption: "System estimate",
            value: PowerMetricsRules.timeRemainingText(monitor.reading.timeRemainingSeconds)
                ?? (monitor.reading.isPluggedIn ? "Plugged in" : "Calculating…")
        )
    }

    private var healthRow: some View {
        detailRow(
            symbolName: "heart.fill",
            tint: CommandlyTint.pink.color,
            title: "Battery health",
            caption: monitor.reading.cycleCount.map { "\($0) cycles" },
            value: monitor.reading.healthPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        )
    }

    private func detailRow(
        symbolName: String,
        tint: Color,
        title: String,
        caption: String?,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs.rawValue) {
            Image(systemName: symbolName)
                .commandlyFont(size: 12)
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 12, weight: .medium)
                if let caption {
                    Text(caption)
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.xs.rawValue)

            Text(value)
                .commandlyFont(size: 12, weight: .semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
