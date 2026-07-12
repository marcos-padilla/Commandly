import SwiftUI
import DesignSystem

struct GeneralSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                SettingsPageHeader(title: viewModel.selectedPane.title, subtitle: viewModel.selectedPane.subtitle)

                SettingsCard {
                    SettingsToggleRow(
                        icon: "power.circle.fill",
                        iconColor: .green,
                        title: "Open at Login",
                        subtitle: "Launch Commandly automatically when you sign in to your Mac.",
                        isOn: Binding(
                            get: { viewModel.opensAtLogin },
                            set: { viewModel.setOpensAtLogin($0) }
                        ),
                        isDisabled: viewModel.isUpdatingLoginItem
                    )
                }

                SettingsCard {
                    HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
                        settingsIcon("keyboard.fill", color: BrandPalette.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Commandly Hotkey")
                                .font(.system(size: 13, weight: .semibold))
                            Text(
                                viewModel.hasConfirmedOptionSpaceHotkey
                                    ? "Press this shortcut to open Commandly from anywhere."
                                    : "Default launcher shortcut. Global registration comes next."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: Spacing.sm.rawValue)

                        Text(viewModel.hotkeyDisplay)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }

                SettingsCard {
                    SettingsToggleRow(
                        icon: "menubar.rectangle",
                        iconColor: .purple,
                        title: "Show Menu Bar Icon",
                        subtitle: "Keep Commandly available from the menu bar for Settings and Quit.",
                        isOn: Binding(
                            get: { viewModel.showMenuBarIcon },
                            set: { viewModel.setShowMenuBarIcon($0) }
                        )
                    )
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                        HStack(spacing: Spacing.sm.rawValue) {
                            settingsIcon("textformat.size", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Text Size")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Affects upcoming launcher surfaces.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: Spacing.xs.rawValue) {
                            ForEach(AppTextSizePreference.allCases) { size in
                                Button {
                                    viewModel.setTextSize(size)
                                } label: {
                                    Text("Aa")
                                        .font(.system(size: size == .standard ? 13 : 17, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                                .fill(
                                                    viewModel.textSize == size
                                                        ? BrandPalette.accent.opacity(0.28)
                                                        : Color.primary.opacity(0.05)
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                                .strokeBorder(
                                                    viewModel.textSize == size
                                                        ? BrandPalette.accent.opacity(0.55)
                                                        : Color.primary.opacity(0.08),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(size.title)
                            }
                        }
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                        HStack(spacing: Spacing.sm.rawValue) {
                            settingsIcon("circle.lefthalf.filled", color: .cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Match your Mac or lock Commandly to light or dark.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: Spacing.xs.rawValue) {
                            ForEach(AppAppearancePreference.allCases) { mode in
                                Button {
                                    viewModel.setAppearance(mode)
                                } label: {
                                    VStack(spacing: 6) {
                                        appearanceGlyph(mode)
                                        Text(mode.title)
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                            .fill(
                                                viewModel.appearance == mode
                                                    ? BrandPalette.accent.opacity(0.28)
                                                    : Color.primary.opacity(0.05)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                            .strokeBorder(
                                                viewModel.appearance == mode
                                                    ? BrandPalette.accent.opacity(0.55)
                                                    : Color.primary.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SettingsCard {
                    SettingsToggleRow(
                        icon: "face.smiling.inverse",
                        iconColor: .pink,
                        title: "Commandly Emoji Picker",
                        subtitle: "Remember this preference for when the emoji picker ships.",
                        isOn: Binding(
                            get: { viewModel.prefersCommandlyEmojiPicker },
                            set: { viewModel.setPrefersCommandlyEmojiPicker($0) }
                        )
                    )
                }

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, Spacing.xxs.rawValue)
                }
            }
            .padding(Spacing.lg.rawValue)
        }
    }

    @ViewBuilder
    private func appearanceGlyph(_ mode: AppAppearancePreference) -> some View {
        switch mode {
        case .light:
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
        case .dark:
            Circle()
                .fill(Color.black)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        case .system:
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.white, .black, .white],
                        center: .center
                    )
                )
                .frame(width: 18, height: 18)
        }
    }
}
