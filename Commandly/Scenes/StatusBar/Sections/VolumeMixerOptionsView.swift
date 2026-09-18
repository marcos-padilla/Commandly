import DesignSystem
import SwiftUI

/// The mixer's Options block: what the list shows and the three behaviors that reach outside it.
struct VolumeMixerOptionsView: View {
    @Bindable var model: VolumeMixerModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            StatusPanelDisclosureHeader(title: "Options", isExpanded: $isExpanded)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    StatusPanelToggleRow(
                        symbolName: "eye.slash",
                        title: "Hide inactive apps",
                        caption: "Apps with a custom volume or output stay listed either way.",
                        isOn: $model.settings.hidesInactiveApplications
                    )

                    optionToggle(
                        title: "Lower volume when headphones disconnect",
                        caption: "Turns the speakers down when wired or Bluetooth headphones go away.",
                        isOn: $model.settings.lowersVolumeOnHeadphonesDisconnect
                    )

                    if model.settings.lowersVolumeOnHeadphonesDisconnect {
                        disconnectLevelRow
                    }

                    optionToggle(
                        title: "Use finer volume steps",
                        caption: "Turns the volume keys into smaller system volume steps. Needs Accessibility permission.",
                        isOn: $model.settings.usesFinerVolumeSteps
                    )

                    optionToggle(
                        title: "Switch outputs with a shortcut",
                        caption: "Press \(RuntimeGlobalShortcutCatalog.soundOutputCycleHotKey.displayTitle) to move to the next output you chose below.",
                        isOn: $model.settings.switchesOutputsWithShortcut
                    )

                    if model.settings.switchesOutputsWithShortcut {
                        switcherDeviceList
                    }

                    appsInListRow
                }
                .padding(.leading, 19)
                .transition(.opacity)
            }
        }
    }

    private func optionToggle(
        title: String,
        caption: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: isOn) {
                Text(title)
                    .commandlyFont(size: 11, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Text(caption)
                .commandlyFont(size: 9.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 19)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disconnectLevelRow: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Lower to")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker(
                "Headphone disconnect level",
                selection: $model.settings.headphonesDisconnectVolumePercent
            ) {
                ForEach(VolumeMixerSettings.allowedDisconnectVolumePercents, id: \.self) { percent in
                    Text(percent == 0 ? "Silent" : "\(percent)%").tag(percent)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.leading, 19)
    }

    /// The outputs the shortcut cycles through. Ticking a device adds it to the end of the
    /// cycle, so the order is the order they were chosen in.
    private var switcherDeviceList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Outputs in the cycle")
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)

            if model.outputDevices.filter(\.canBeDefaultOutput).isEmpty {
                Text("No output device can be made the default right now.")
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.outputDevices.filter(\.canBeDefaultOutput)) { device in
                    Toggle(isOn: binding(for: device.uid)) {
                        Text(device.name)
                            .commandlyFont(size: 10.5)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LauncherPalette.hover)
        )
        .padding(.leading, 19)
    }

    private func binding(for uid: String) -> Binding<Bool> {
        Binding(
            get: { model.settings.switcherDeviceUIDs.contains(uid) },
            set: { isOn in
                var uids = model.settings.switcherDeviceUIDs
                if isOn {
                    guard uids.contains(uid) == false else { return }
                    uids.append(uid)
                } else {
                    uids.removeAll { $0 == uid }
                }
                model.settings.switcherDeviceUIDs = uids
            }
        )
    }

    /// Restores apps that were taken off the list, and says how many are missing.
    private var appsInListRow: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Apps in the list")
                .commandlyFont(size: 11, weight: .medium)
            Spacer(minLength: Spacing.xs.rawValue)

            if model.hiddenApplications.isEmpty {
                Text("All")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Section("Hidden") {
                        ForEach(model.hiddenApplications) { application in
                            Button("Show \(application.name)") {
                                model.showInList(id: application.id)
                            }
                        }
                    }
                    Divider()
                    Button("Show All") {
                        for application in model.hiddenApplications {
                            model.showInList(id: application.id)
                        }
                    }
                } label: {
                    Text("\(model.hiddenApplications.count) hidden")
                        .commandlyFont(size: 10.5)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }
}
