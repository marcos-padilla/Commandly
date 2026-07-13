import AppKit
import DesignSystem
import SwiftUI

/// Behind-window blur for Settings. A tint is layered over this in the root
/// view so text remains readable over varied desktop wallpapers.
struct SettingsVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct SettingsWindowMaterialConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAttached(nsView)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
    }
}

extension View {
    func settingsWindowMaterial() -> some View {
        background(SettingsWindowMaterialConfigurator())
    }
}

/// Quiet grouped section for settings rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Spacing.sm.rawValue + 2)
        .padding(.vertical, Spacing.xs.rawValue + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(SettingsPalette.card)
        )
        .glassEffect(
            .regular.tint(BrandPalette.accent.opacity(0.025)),
            in: .rect(cornerRadius: CornerRadius.lg.rawValue)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(SettingsPalette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
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
            Text("COMMANDLY SETTINGS")
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .tracking(1.1)

            Text(title)
                .commandlyFont(size: 19, weight: .semibold)
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
        .padding(.bottom, Spacing.xs.rawValue)
        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: title)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    @Environment(\.commandlyLayoutDensity) private var density
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: density.spacing(.sm)) {
            settingsGlyph(icon, emphasized: isHovered || isOn)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: density.spacing(.xs))

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, max(4, density.rowVerticalPadding - 2))
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

    @Environment(\.commandlyLayoutDensity) private var density
    @State private var isHovered = false
    @State private var isActionHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: density.spacing(.sm)) {
            settingsGlyph(icon, emphasized: isHovered)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: density.spacing(.xs))

            Button(actionTitle, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(actionDisabled ? Color.secondary : BrandPalette.accent)
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
        .padding(.vertical, max(4, density.rowVerticalPadding - 2))
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
            .overlay(SettingsPalette.border)
            .opacity(0.6)
            .padding(.leading, 36)
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        selected
                            ? BrandPalette.accent.opacity(0.12)
                            : Color.primary.opacity(isHovered ? 0.04 : 0)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected ? BrandPalette.accent.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular
                .tint(selected ? BrandPalette.accent.opacity(0.08) : Color.clear)
                .interactive(),
            in: .rect(cornerRadius: 8)
        )
        .scaleEffect(isHovered && !selected ? 1.015 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

func settingsGlyph(_ systemName: String, emphasized: Bool = false) -> some View {
    Image(systemName: filledSettingsSymbol(for: systemName))
        .symbolRenderingMode(.hierarchical)
        .commandlyFont(size: 11, weight: .semibold)
        .foregroundStyle(emphasized ? BrandPalette.accentSoft : .secondary)
        .frame(width: 24, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(emphasized ? BrandPalette.accent.opacity(0.16) : Color.primary.opacity(0.045))
        )
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: emphasized)
        .accessibilityHidden(true)
}

private func filledSettingsSymbol(for systemName: String) -> String {
    switch systemName {
    case "power": "power.circle.fill"
    case "menubar.rectangle": "menubar.rectangle"
    case "keyboard": "keyboard.fill"
    case "rectangle.split.3x1": "rectangle.split.3x1.fill"
    case "textformat.size": "textformat.size"
    case "circle.lefthalf.filled": "circle.lefthalf.filled"
    case "face.smiling": "face.smiling.inverse"
    case "calendar": "calendar.circle.fill"
    case "person": "person.crop.circle.fill"
    case "folder": "folder.fill"
    case "accessibility": "accessibility.fill"
    default: systemName
    }
}
