import SwiftUI
import DesignSystem

struct GeneralSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                SettingsPageHeader(
                    title: viewModel.selectedPane.title,
                    subtitle: viewModel.selectedPane.subtitle
                )

                SettingsCard {
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

                SettingsCard {
                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        HStack(spacing: Spacing.sm.rawValue) {
                            settingsGlyph("textformat.size")
                            Text("Text Size")
                                .commandlyFont(size: 12.5, weight: .medium)
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            ForEach(AppTextSizePreference.allCases) { size in
                                SettingsChoiceChip(
                                    label: "Aa",
                                    fontSize: size == .standard ? 11 : 14,
                                    selected: viewModel.textSize == size
                                ) {
                                    viewModel.setTextSize(size)
                                }
                                .accessibilityLabel(size.title)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        HStack(spacing: Spacing.sm.rawValue) {
                            settingsGlyph("circle.lefthalf.filled")
                            Text("Appearance")
                                .commandlyFont(size: 12.5, weight: .medium)
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            ForEach(AppAppearancePreference.allCases) { mode in
                                SettingsChoiceChip(
                                    label: mode.title,
                                    fontSize: 11,
                                    selected: viewModel.appearance == mode,
                                    accessory: { appearanceGlyph(mode) }
                                ) {
                                    viewModel.setAppearance(mode)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                SettingsCard {
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
                    Text(message)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: message)
                }
            }
            .padding(.horizontal, Spacing.md.rawValue)
            .padding(.vertical, Spacing.md.rawValue)
        }
    }
}

@ViewBuilder
private func appearanceGlyph(_ mode: AppAppearancePreference) -> some View {
    switch mode {
    case .light:
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
    case .dark:
        Circle()
            .fill(Color.black)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
    case .system:
        Circle()
            .fill(
                AngularGradient(
                    colors: [.white, .black, .white],
                    center: .center
                )
            )
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

private struct HotkeySettingsRow: View {
    let hotkeyDisplay: String
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
            settingsGlyph("keyboard", emphasized: isHovered)

            VStack(alignment: .leading, spacing: 1) {
                Text("Hotkey")
                    .commandlyFont(size: 12.5, weight: .medium)
                Text("Opens Commandly from anywhere.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: Spacing.xs.rawValue)

            Text(hotkeyDisplay)
                .commandlyFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0.05))
                )
                .scaleEffect(isHovered ? 1.03 : 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.045 : 0))
        )
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
