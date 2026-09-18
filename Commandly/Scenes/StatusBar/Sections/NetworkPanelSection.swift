import DesignSystem
import SwiftUI

/// Network tab: live throughput, what this session moved, and an on-demand speed test.
struct NetworkPanelSection: View {
    @Bindable var monitor: NetworkMetricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rateRow

            PanelDualSparkline(
                primary: NetworkMetricsRules.normalized(monitor.downloadHistory),
                secondary: NetworkMetricsRules.normalized(monitor.uploadHistory),
                primaryTint: CommandlyTint.blue.color,
                secondaryTint: CommandlyTint.green.color
            )

            Divider()

            applicationActivity

            Divider()

            sessionRow

            Divider()

            speedTest
        }
        .statusPanelCard()
        .onAppear { monitor.addObserver() }
        .onDisappear { monitor.removeObserver() }
    }

    // MARK: - Live rates

    private var rateRow: some View {
        HStack(spacing: 0) {
            rateTile(
                title: "Download",
                symbolName: "arrow.down",
                tint: CommandlyTint.blue.color,
                bytesPerSecond: monitor.reading.downloadBytesPerSecond
            )

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(width: 1, height: 34)

            rateTile(
                title: "Upload",
                symbolName: "arrow.up",
                tint: CommandlyTint.green.color,
                bytesPerSecond: monitor.reading.uploadBytesPerSecond
            )
        }
    }

    private func rateTile(
        title: String,
        symbolName: String,
        tint: Color,
        bytesPerSecond: Double?
    ) -> some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: symbolName)
                .commandlyFont(size: 14, weight: .semibold)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(NetworkMetricsRules.rateText(bytesPerSecond))
                    .commandlyFont(size: 16, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(NetworkMetricsRules.rateText(bytesPerSecond))
    }

    // MARK: - Per-application activity

    private var applicationActivity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apps using network")
                .commandlyFont(size: 11.5, weight: .medium)
                .foregroundStyle(.secondary)
            Text("macOS does not report per-app network use to a sandboxed app, so Commandly shows the totals above instead.")
                .commandlyFont(size: 10)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Session totals

    private var sessionRow: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("This session")
                .commandlyFont(size: 11.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs.rawValue)
            Label(
                NetworkMetricsRules.totalText(monitor.reading.sessionDownloadBytes),
                systemImage: "arrow.down"
            )
            .commandlyFont(size: 11.5, weight: .medium)
            .monospacedDigit()
            Label(
                NetworkMetricsRules.totalText(monitor.reading.sessionUploadBytes),
                systemImage: "arrow.up"
            )
            .commandlyFont(size: 11.5, weight: .medium)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moved this session")
    }

    // MARK: - Speed test

    private var speedTest: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.xs.rawValue) {
                Button {
                    monitor.runSpeedTest()
                } label: {
                    Label(
                        monitor.speedTestResult == nil ? "Test speed" : "Test again",
                        systemImage: "speedometer"
                    )
                    .commandlyFont(size: 11, weight: .medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(monitor.isRunningSpeedTest)

                Spacer(minLength: Spacing.xs.rawValue)

                if monitor.isRunningSpeedTest {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Measuring the connection")
                } else if let result = monitor.speedTestResult {
                    HStack(spacing: 8) {
                        Text("↓\(Int(result.downloadMegabitsPerSecond.rounded()))")
                        Text("↑\(Int(result.uploadMegabitsPerSecond.rounded())) Mbps")
                    }
                    .commandlyFont(size: 12, weight: .semibold)
                    .monospacedDigit()
                }
            }

            if let message = monitor.speedTestError {
                Text(message)
                    .commandlyFont(size: 10)
                    .foregroundStyle(SemanticColors.color(for: .danger))
            } else if let result = monitor.speedTestResult {
                Text("Latency: \(Int(result.latencyMilliseconds.rounded())) ms")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            } else {
                Text("Measures this connection against Cloudflare's public speed service. It runs only when you ask.")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
