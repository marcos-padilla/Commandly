import DesignSystem
import SwiftUI

struct GeneralSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        SettingsPageLayout(maxWidth: 720) {
            VStack(alignment: .leading, spacing: max(24, density.pageStackSpacing + 8)) {
                SettingsSection("Startup") {
                    SettingsToggleRow(
                        icon: "power",
                        title: "Open at Login",
                        subtitle: "Launch Commandly when you sign in.",
                        isOn: Binding(
                            get: { viewModel.opensAtLogin },
                            set: { viewModel.setOpensAtLogin($0) }
                        ),
                        isDisabled: viewModel.isUpdatingLoginItem
                    )

                    SettingsDivider()

                    HotkeySettingsRow(hotkeyDisplay: viewModel.hotkeyDisplay)

                    SettingsDivider()

                    SettingsToggleRow(
                        icon: "menubar.rectangle",
                        title: "Menu Bar Icon",
                        subtitle: "Show Commandly in the menu bar.",
                        isOn: Binding(
                            get: { viewModel.showMenuBarIcon },
                            set: { viewModel.setShowMenuBarIcon($0) }
                        )
                    )
                }

                SettingsSection("Interface") {
                    PreferencePickerRow(
                        icon: "rectangle.split.3x1",
                        title: "View Mode",
                        subtitle: "Choose the spacing used throughout Commandly.",
                        selection: Binding(
                            get: { viewModel.viewMode },
                            set: { viewModel.setViewMode($0) }
                        )
                    ) {
                        ForEach(AppViewModePreference.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    SettingsDivider()

                    PreferencePickerRow(
                        icon: "textformat.size",
                        title: "Text Size",
                        subtitle: "Increase text while preserving the current layout.",
                        selection: Binding(
                            get: { viewModel.textSize },
                            set: { viewModel.setTextSize($0) }
                        )
                    ) {
                        ForEach(AppTextSizePreference.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                }

                SettingsSection("Appearance") {
                    PreferencePickerRow(
                        icon: "circle.lefthalf.filled",
                        title: "Theme",
                        subtitle: "Follow macOS or keep a consistent light or dark appearance.",
                        selection: Binding(
                            get: { viewModel.appearance },
                            set: { viewModel.setAppearance($0) }
                        )
                    ) {
                        ForEach(AppAppearancePreference.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }

                SettingsSection("Input") {
                    SettingsToggleRow(
                        icon: "face.smiling",
                        title: "Emoji Picker Preference",
                        subtitle: "Saved for when Commandly’s picker ships.",
                        isOn: Binding(
                            get: { viewModel.prefersCommandlyEmojiPicker },
                            set: { viewModel.setPrefersCommandlyEmojiPicker($0) }
                        )
                    )
                }

                if let message = viewModel.statusMessage {
                    SettingsStatusBanner(message: message, tint: .orange)
                        .transition(.opacity)
                }
            }
        }
    }
}

private struct PreferencePickerRow<Selection: Hashable, Choices: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selection: Selection
    @ViewBuilder let choices: () -> Choices

    @Environment(\.commandlyLayoutDensity) private var density
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: density.spacing(.sm)) {
            settingsGlyph(icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: density.spacing(.sm))

            Picker(title, selection: $selection) {
                choices()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 236)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, max(9, density.rowVerticalPadding))
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(isHovered ? SettingsVisualStyle.hover : Color.clear)
        }
        .animation(CommandlyMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct HotkeySettingsRow: View {
    let hotkeyDisplay: String
    @Environment(\.commandlyLayoutDensity) private var density
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: density.spacing(.sm)) {
            settingsGlyph("keyboard", emphasized: isHovered)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey")
                    .commandlyFont(size: 12.5, weight: .medium)
                Text("Opens Commandly from anywhere.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: density.spacing(.xs))

            Text(hotkeyDisplay)
                .commandlyFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    SettingsVisualStyle.fieldBackground,
                    in: RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                )
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, max(8, density.rowVerticalPadding))
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(isHovered ? SettingsVisualStyle.hover : Color.clear)
        }
        .animation(CommandlyMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
