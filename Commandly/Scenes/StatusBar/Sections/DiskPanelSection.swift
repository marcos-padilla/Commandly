import AppKit
import DesignSystem
import SwiftUI

/// Disks tab: the mounted volumes, how full the chosen one is, live throughput, and the tools
/// that act on it.
struct DiskPanelSection: View {
    @Bindable var monitor: DiskMetricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            volumePicker

            if let volume = monitor.selectedVolume {
                Divider()
                usage(of: volume)
            }

            Divider()

            liveActivity

            Divider()

            smartBlock

            Divider()

            externalProtection

            if let volume = monitor.selectedVolume {
                Divider()
                tools(for: volume)
            }
        }
        .statusPanelCard()
        .onAppear { monitor.addObserver() }
        .onDisappear { monitor.removeObserver() }
    }

    // MARK: - Volume picker

    private var volumePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("Select disk")

            if monitor.volumes.isEmpty {
                Text("No mounted volume is readable right now.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(monitor.volumes) { volume in
                        volumeTile(volume)
                    }
                }
            }
        }
    }

    private func volumeTile(_ volume: DiskVolume) -> some View {
        let isSelected = monitor.selectedVolume?.id == volume.id
        return Button {
            monitor.selectedVolumeID = volume.id
        } label: {
            HStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive")
                    .commandlyFont(size: 12)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.name)
                        .commandlyFont(size: 12, weight: .medium)
                        .lineLimit(1)
                    Text("\(Int((volume.usedFraction * 100).rounded()))% used")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : LauncherPalette.hover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(volume.name)
        .accessibilityValue("\(Int((volume.usedFraction * 100).rounded())) percent used")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Usage

    private func usage(of volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("Disk usage")

            HStack(spacing: 6) {
                Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive")
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(volume.name)
                    .commandlyFont(size: 13, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let fileSystem = volume.fileSystem {
                    badge(fileSystem)
                }
                badge(volume.isRemovable ? "External" : "Internal")
            }

            PanelMeter(fraction: volume.usedFraction, tint: usageTint(volume.usedFraction), height: 7)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int((volume.usedFraction * 100).rounded()))% used")
                        .commandlyFont(size: 12, weight: .medium)
                    Text(
                        "\(SystemMetricsFormat.byteText(volume.usedBytes)) / \(SystemMetricsFormat.byteText(volume.totalBytes))"
                    )
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.xs.rawValue)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(SystemMetricsFormat.byteText(volume.availableBytes)) available")
                        .commandlyFont(size: 12, weight: .medium)
                    if let purgeable = volume.purgeableBytes, purgeable > 0 {
                        Text("\(SystemMetricsFormat.byteText(purgeable)) purgeable")
                            .commandlyFont(size: 10)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func usageTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: return CommandlyTint.blue.color
        case ..<0.9: return CommandlyTint.yellow.color
        default: return CommandlyTint.red.color
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .commandlyFont(size: 9.5, weight: .medium)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LauncherPalette.hover))
    }

    // MARK: - Live activity

    private var liveActivity: some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("Live activity")

            HStack(spacing: 0) {
                activityTile(
                    title: "Read",
                    symbolName: "arrow.down",
                    tint: CommandlyTint.blue.color,
                    bytesPerSecond: monitor.activity.readBytesPerSecond
                )
                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(width: 1, height: 30)
                activityTile(
                    title: "Write",
                    symbolName: "arrow.up",
                    tint: CommandlyTint.pink.color,
                    bytesPerSecond: monitor.activity.writeBytesPerSecond
                )
            }

            PanelDualSparkline(
                primary: NetworkMetricsRules.normalized(monitor.readHistory),
                secondary: NetworkMetricsRules.normalized(monitor.writeHistory),
                primaryTint: CommandlyTint.blue.color,
                secondaryTint: CommandlyTint.pink.color,
                height: 34
            )

            HStack(spacing: Spacing.xs.rawValue) {
                Text("This session")
                    .commandlyFont(size: 11.5)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.xs.rawValue)
                Label(
                    NetworkMetricsRules.totalText(monitor.activity.sessionReadBytes),
                    systemImage: "arrow.down"
                )
                .commandlyFont(size: 11.5, weight: .medium)
                .monospacedDigit()
                Label(
                    NetworkMetricsRules.totalText(monitor.activity.sessionWrittenBytes),
                    systemImage: "arrow.up"
                )
                .commandlyFont(size: 11.5, weight: .medium)
                .monospacedDigit()
            }
        }
    }

    private func activityTile(
        title: String,
        symbolName: String,
        tint: Color,
        bytesPerSecond: Double?
    ) -> some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: symbolName)
                .commandlyFont(size: 13, weight: .semibold)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(NetworkMetricsRules.rateText(bytesPerSecond))
                    .commandlyFont(size: 15, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .commandlyFont(size: 10.5)
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

    // MARK: - SMART

    private var smartBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            blockTitle("SMART")
            Text("Drive health counters come from a device interface App Sandbox does not open, so Commandly cannot read them.")
                .commandlyFont(size: 10)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - External volumes

    private var externalProtection: some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("External disks")

            HStack(spacing: Spacing.xs.rawValue) {
                Button {
                    if let volume = monitor.selectedVolume { monitor.eject(volume) }
                } label: {
                    Label("Eject", systemImage: "eject")
                        .commandlyFont(size: 11, weight: .medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(canEjectSelected == false)

                Button {
                    monitor.ejectAll()
                } label: {
                    Label("Eject all", systemImage: "eject.fill")
                        .commandlyFont(size: 11, weight: .medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(monitor.ejectableVolumes.isEmpty)

                Spacer(minLength: 0)
            }

            if let message = monitor.ejectError {
                Text(message)
                    .commandlyFont(size: 10)
                    .foregroundStyle(SemanticColors.color(for: .danger))
                    .fixedSize(horizontal: false, vertical: true)
            } else if monitor.ejectableVolumes.isEmpty {
                Text("No external disk is ready to eject.")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canEjectSelected: Bool {
        guard let volume = monitor.selectedVolume else { return false }
        return volume.isRemovable && volume.isInternal == false
    }

    // MARK: - Tools

    private func tools(for volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("Tools")

            HStack(spacing: Spacing.xs.rawValue) {
                Text(volume.name)
                    .commandlyFont(size: 11.5, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs.rawValue)
                Button {
                    monitor.revealInFinder(volume)
                } label: {
                    Label("Open", systemImage: "folder")
                        .commandlyFont(size: 11, weight: .medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                openStorageSettings()
            } label: {
                Label("Storage settings", systemImage: "gearshape")
                    .commandlyFont(size: 11, weight: .medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func openStorageSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.Storage"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func blockTitle(_ title: String) -> some View {
        Text(title)
            .commandlyFont(size: 11, weight: .semibold)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}
