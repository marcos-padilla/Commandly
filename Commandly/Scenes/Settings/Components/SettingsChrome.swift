import SwiftUI
import DesignSystem

/// Shared glass card chrome for settings rows/groups.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.md.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .background {
                    RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                        .fill(.thinMaterial)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.md.rawValue)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
            settingsIcon(icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm.rawValue)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
                .tint(BrandPalette.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let actionTitle: String
    var actionDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
            settingsIcon(icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm.rawValue)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actionDisabled)
        }
    }
}

func settingsIcon(_ systemName: String, color: Color) -> some View {
    Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.gradient)
        )
        .accessibilityHidden(true)
}
