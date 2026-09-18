import DesignSystem
import SwiftUI

/// Fans tab: what each fan is doing, and who decides its speed.
struct FanControlPanelSection: View {
    @Bindable var monitor: FanControlMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let reason = monitor.unavailableReason {
                unavailableNotice(reason)
            } else {
                fanRows
                Divider()
                controlMode
            }
        }
        .statusPanelCard()
        .onAppear { monitor.addObserver() }
        .onDisappear { monitor.removeObserver() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.xs.rawValue) {
            Image(systemName: "fanblades.fill")
                .commandlyFont(size: 20, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Fan Control")
                        .commandlyFont(size: 14, weight: .semibold)
                    Text("BETA")
                        .commandlyFont(size: 8.5, weight: .bold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
                Text(monitor.settings.mode.title)
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Fans

    @ViewBuilder
    private var fanRows: some View {
        if monitor.fans.isEmpty {
            Text("Waiting for the first reading…")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(monitor.fans) { fan in
                    fanRow(fan)
                }
            }
        }
    }

    private func fanRow(_ fan: Fan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.xs.rawValue) {
                Text(fan.displayName)
                    .commandlyFont(size: 12, weight: .medium)
                Spacer(minLength: Spacing.xs.rawValue)
                Text(rpmText(fan.actualRPM))
                    .commandlyFont(size: 12, weight: .semibold)
                    .monospacedDigit()
            }
            if let fraction = fan.speedFraction {
                PanelMeter(fraction: fraction, tint: CommandlyTint.teal.color, height: 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fan.displayName)
        .accessibilityValue(rpmText(fan.actualRPM))
    }

    private func rpmText(_ rpm: Double?) -> String {
        guard let rpm, rpm.isFinite else { return "Current — RPM" }
        return "Current \(Int(rpm.rounded())) RPM"
    }

    // MARK: - Control

    private var controlMode: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Spacing.xs.rawValue) {
                Text("Control mode")
                    .commandlyFont(size: 13, weight: .medium)
                Spacer(minLength: Spacing.xs.rawValue)
                Picker("Control mode", selection: $monitor.settings.mode) {
                    ForEach(FanControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            if monitor.settings.mode == .manual {
                manualSpeed
            }

            if monitor.settings.mode == .curve {
                curveEditor
            }

            if let notice = monitor.handbackNotice {
                Text(notice)
                    .commandlyFont(size: 10)
                    .foregroundStyle(SemanticColors.color(for: .danger))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Control stays active until you return to System. It returns automatically if Commandly quits, the Mac sleeps, sensor readings fail, or thermal pressure rises.")
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var manualSpeed: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Speed")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
            Slider(value: $monitor.settings.manualSpeedFraction, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("Manual fan speed")
            Text("\(Int((monitor.settings.manualSpeedFraction * 100).rounded()))%")
                .commandlyFont(size: 11, weight: .medium)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// Each curve point is a temperature and the speed the fans should reach by then.
    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("At each temperature, aim for")
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)

            ForEach(Array(monitor.settings.curve.enumerated()), id: \.offset) { index, point in
                HStack(spacing: Spacing.xs.rawValue) {
                    Text("\(Int(point.temperatureCelsius.rounded())) °C")
                        .commandlyFont(size: 10.5)
                        .monospacedDigit()
                        .frame(width: 46, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { monitor.settings.curve[index].speedFraction },
                            set: { monitor.settings.curve[index].speedFraction = $0 }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .accessibilityLabel("Fan speed at \(Int(point.temperatureCelsius.rounded())) degrees")

                    Text("\(Int((point.speedFraction * 100).rounded()))%")
                        .commandlyFont(size: 10.5, weight: .medium)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }

            Button("Reset Curve") {
                monitor.settings.curve = FanControlRules.defaultCurve
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LauncherPalette.hover)
        )
    }

    // MARK: - Unavailable

    private func unavailableNotice(_ reason: FanControlUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title(for: reason))
                .commandlyFont(size: 12, weight: .medium)
            Text(explanation(for: reason))
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func title(for reason: FanControlUnavailableReason) -> String {
        switch reason {
        case .controllerUnavailable: return "Fan sensors are not reachable"
        case .noFans: return "This Mac has no fans"
        case .notWritable: return "These fans cannot be set"
        }
    }

    private func explanation(for reason: FanControlUnavailableReason) -> String {
        switch reason {
        case .controllerUnavailable:
            return "The System Management Controller is reached through a device interface that App Sandbox does not open, so Commandly can neither read fan speed nor set it in this build."
        case .noFans:
            return "Fanless Macs move heat through their enclosure, so there is nothing here to read or control."
        case .notWritable:
            return "The controller reports these fans but not the keys that would change their speed, so they stay under macOS."
        }
    }
}
