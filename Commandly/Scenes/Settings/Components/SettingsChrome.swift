import SwiftUI
import DesignSystem

/// Quiet grouped section for settings rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Spacing.sm.rawValue + 2)
        .padding(.vertical, Spacing.xs.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .commandlyFont(size: 16, weight: .semibold)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .commandlyFont(size: 11)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.sm.rawValue)
        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: title)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
            settingsGlyph(icon, emphasized: isHovered || isOn)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs.rawValue)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.045 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String
    var actionDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isActionHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm.rawValue) {
            settingsGlyph(icon, emphasized: isHovered)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs.rawValue)

            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(actionDisabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(BrandPalette.accent))
                .opacity(isActionHovered && !actionDisabled ? 0.75 : 1)
                .scaleEffect(isActionHovered && !actionDisabled ? 0.98 : 1)
                .disabled(actionDisabled)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                        isActionHovered = hovering
                    }
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.045 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                isHovered = hovering
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, 28)
    }
}

struct SettingsChoiceChip<Accessory: View>: View {
    let label: String
    let fontSize: CGFloat
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @State private var isHovered = false

    init(
        label: String,
        fontSize: CGFloat,
        selected: Bool,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.label = label
        self.fontSize = fontSize
        self.selected = selected
        self.accessory = accessory
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                accessory()
                Text(label)
                    .commandlyFont(size: fontSize, weight: .medium)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        selected
                            ? Color.primary.opacity(0.08)
                            : Color.primary.opacity(isHovered ? 0.04 : 0)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(selected ? 0.10 : 0),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !selected ? 1.015 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

func settingsGlyph(_ systemName: String, emphasized: Bool = false) -> some View {
    Image(systemName: systemName)
        .commandlyFont(size: 11, weight: .regular)
        .foregroundStyle(emphasized ? .primary : .secondary)
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: emphasized)
        .accessibilityHidden(true)
}
