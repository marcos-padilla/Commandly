import AppKit
import DesignSystem
import SwiftUI

/// Volume Mixer tab: system output, alert output, microphone, and a volume slider per app.
struct VolumeMixerPanelSection: View {
    @Bindable var model: VolumeMixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            deviceRows

            if let message = model.outputSwitchError {
                noticeRow(message, symbolName: "exclamationmark.triangle.fill", isWarning: true)
            }

            Divider()

            applicationList

            Divider()

            VolumeMixerOptionsView(model: model)
        }
        .statusPanelCard()
        .onAppear { model.start() }
    }

    // MARK: - Devices

    private var deviceRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Spacing.xs.rawValue) {
                deviceLabel("Output", symbolName: "speaker.wave.2.fill")
                Spacer(minLength: Spacing.xs.rawValue)
                devicePicker(
                    label: "Output device",
                    selection: model.currentOutputDeviceUID ?? "",
                    options: model.outputDevices.filter(\.canBeDefaultOutput)
                        .map { ($0.uid, $0.name) },
                    onChange: { model.setSystemOutputDeviceUID($0) }
                )
            }

            systemVolumeRow

            HStack(spacing: Spacing.xs.rawValue) {
                deviceLabel("System sounds", symbolName: "bell.fill")
                Spacer(minLength: Spacing.xs.rawValue)
                devicePicker(
                    label: "Alert output device",
                    selection: model.currentSystemSoundOutputDeviceUID ?? "",
                    options: model.outputDevices.filter(\.canBeDefaultSystemOutput)
                        .map { ($0.uid, $0.name) },
                    onChange: { model.setSystemSoundOutputDeviceUID($0) }
                )
            }

            HStack(spacing: Spacing.xs.rawValue) {
                deviceLabel("Microphone", symbolName: "mic.fill")
                Spacer(minLength: Spacing.xs.rawValue)
                devicePicker(
                    label: "Input device",
                    selection: model.currentInputDeviceUID ?? "",
                    options: model.inputDevices.map { ($0.uid, $0.name) },
                    onChange: { model.setInputDeviceUID($0) }
                )
            }
        }
    }

    @ViewBuilder
    private var systemVolumeRow: some View {
        if let volume = model.systemOutputVolume {
            HStack(spacing: Spacing.xs.rawValue) {
                Button {
                    model.toggleSystemOutputMute()
                } label: {
                    Image(systemName: model.systemOutputMuted == true
                        ? "speaker.slash.fill"
                        : "speaker.fill")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.systemOutputMuted == nil)
                .accessibilityLabel(model.systemOutputMuted == true ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { model.systemOutputMuted == true ? 0 : volume },
                        set: { model.requestOutputAdjustment(volume: $0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .accessibilityLabel("System volume")

                Text(percentText(model.systemOutputMuted == true ? 0 : volume))
                    .commandlyFont(size: 11, weight: .medium)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
        } else {
            Text("This output has no software volume control.")
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
        }
    }

    private func deviceLabel(_ title: String, symbolName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(title)
                .commandlyFont(size: 11.5, weight: .medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func devicePicker(
        label: String,
        selection: String,
        options: [(uid: String, name: String)],
        onChange: @escaping (String) -> Void
    ) -> some View {
        Picker(
            label,
            selection: Binding(
                get: { selection },
                set: { newValue in
                    guard newValue != selection, newValue.isEmpty == false else { return }
                    onChange(newValue)
                }
            )
        ) {
            if options.contains(where: { $0.uid == selection }) == false {
                Text(selection.isEmpty ? "None" : "Unavailable").tag(selection)
            }
            ForEach(options, id: \.uid) { option in
                Text(option.name).tag(option.uid)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 156)
        .accessibilityLabel(label)
    }

    // MARK: - Applications

    @ViewBuilder
    private var applicationList: some View {
        if VolumeMixerModel.supportsPerApplicationVolume == false {
            noticeRow(
                "Per-app volume needs macOS 14.4 or later.",
                symbolName: "info.circle",
                isWarning: false
            )
        } else if model.needsAudioCapturePermission {
            VStack(alignment: .leading, spacing: 6) {
                noticeRow(
                    "Commandly needs audio recording access to change an app's volume.",
                    symbolName: "exclamationmark.triangle.fill",
                    isWarning: true
                )
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(
                        // Audio recording consent lives under Privacy & Security.
                        URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                        ) ?? URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if model.visibleApplications.isEmpty {
            Text(
                model.settings.hidesInactiveApplications
                    ? "No app is playing right now."
                    : "No app is holding an audio connection right now."
            )
            .commandlyFont(size: 10.5)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.visibleApplications) { application in
                    VolumeMixerApplicationRow(model: model, application: application)
                }
            }
        }
    }

    private func noticeRow(
        _ message: String,
        symbolName: String,
        isWarning: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbolName)
                .commandlyFont(size: 10.5)
                .foregroundStyle(
                    isWarning ? SemanticColors.color(for: .danger) : Color.secondary
                )
                .accessibilityHidden(true)
            Text(message)
                .commandlyFont(size: 10)
                .foregroundStyle(
                    isWarning ? SemanticColors.color(for: .danger) : Color.secondary
                )
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// One application row: its icon, name, chosen output, volume, and mute switch.
private struct VolumeMixerApplicationRow: View {
    @Bindable var model: VolumeMixerModel
    let application: MixerApplication

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Spacing.xs.rawValue) {
                ApplicationLauncherIcon(bundleIdentifier: iconIdentifier, size: 26)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(application.name)
                            .commandlyFont(size: 12, weight: .medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if application.isPlaying {
                            Circle()
                                .fill(SemanticColors.color(for: .success))
                                .frame(width: 5, height: 5)
                                .accessibilityLabel("Playing")
                        }
                    }
                    if application.isBypassed {
                        Text("Drives its own audio")
                            .commandlyFont(size: 9)
                            .foregroundStyle(.tertiary)
                    } else if application.outputDeviceUnavailable {
                        Text("Chosen output unavailable")
                            .commandlyFont(size: 9)
                            .foregroundStyle(SemanticColors.color(for: .danger))
                    }
                }

                Spacer(minLength: Spacing.xs.rawValue)

                if application.isBypassed == false {
                    routePicker
                }
            }

            if application.isBypassed == false {
                HStack(spacing: Spacing.xs.rawValue) {
                    Slider(
                        value: Binding(
                            get: { application.volume },
                            set: { model.setVolume($0, for: application) }
                        ),
                        in: 0...MixerRoutingRules.maximumVolume
                    )
                    .controlSize(.small)
                    .accessibilityLabel("\(application.name) volume")

                    Text("\(Int((application.volume * 100).rounded()))%")
                        .commandlyFont(size: 11, weight: .medium)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)

                    Button {
                        model.toggleMute(application)
                    } label: {
                        Image(systemName: application.volume > 0.001
                            ? "speaker.wave.2.fill"
                            : "speaker.slash.fill")
                            .commandlyFont(size: 11)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        application.volume > 0.001
                            ? "Mute \(application.name)"
                            : "Unmute \(application.name)"
                    )
                }
            }
        }
        .contextMenu {
            if application.persistenceID != nil {
                Button("Hide \(application.name) From the List") {
                    model.hideFromList(application)
                }
            }
            if application.isBypassed == false, MixerRoutingRules.isUnity(application.volume) == false {
                Button("Reset to 100%") {
                    model.setVolume(1, for: application)
                }
            }
        }
    }

    /// Icons come from the bundle identifier when there is one; a bare executable has none, so
    /// the row falls back to the generic application glyph.
    private var iconIdentifier: String {
        application.persistenceID ?? application.id
    }

    private var routePicker: some View {
        Picker(
            "Output for \(application.name)",
            selection: Binding(
                get: {
                    application.selectedOutputDeviceUID ?? MixerRoutingRules.systemDefaultSelectionID
                },
                set: { newValue in
                    model.setOutputDeviceUID(
                        newValue == MixerRoutingRules.systemDefaultSelectionID ? nil : newValue,
                        for: application
                    )
                }
            )
        ) {
            Text("Default").tag(MixerRoutingRules.systemDefaultSelectionID)
            ForEach(model.outputDevices) { device in
                Text(device.name).tag(device.uid)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 132)
        .accessibilityLabel("Output for \(application.name)")
    }
}
