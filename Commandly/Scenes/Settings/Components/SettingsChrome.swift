import AppKit
import DesignSystem
import SwiftUI

/// Neutral, system-backed roles used only by the Settings presentation layer.
///
/// Settings intentionally avoids brand color and decorative depth. Accent color is reserved for
/// selection, focus, enabled controls, and primary actions.
enum SettingsVisualStyle {
    static let windowBackground = SettingsPalette.canvas
    static let sidebarBackground = SettingsPalette.sidebar
    static let detailBackground = SettingsPalette.detail
    static let fieldBackground = SettingsPalette.field
    static let separator = SettingsPalette.border
    static let hover = SettingsPalette.hover
    static let selection = Color.accentColor.opacity(0.15)
    static let focusRing = SettingsPalette.focusRing
}

/// Readable scrolling canvas shared by ordinary Settings panes.
struct SettingsPageLayout<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        maxWidth: CGFloat = 720,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, Spacing.lg.rawValue + Spacing.xs.rawValue)
                .padding(.top, Spacing.lg.rawValue)
                .padding(.bottom, Spacing.xl.rawValue)
        }
        .scrollContentBackground(.hidden)
    }
}

/// A flat Settings section. Content hierarchy comes from spacing and hairlines, not nested cards.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            Text(title)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }

            if let footer {
                Text(footer)
                    .commandlyFont(size: 10)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A compact header for Settings content embedded outside the primary window shell.
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .commandlyFont(size: 22, weight: .semibold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .commandlyFont(size: 11.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Toggle(isOn: $isOn) {
            HStack(alignment: .center, spacing: density.spacing(.sm)) {
                settingsGlyph(icon, emphasized: isOn)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .commandlyFont(size: 12.5, weight: .medium)
                    Text(subtitle)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: density.spacing(.xs))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(isDisabled)
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, max(8, density.rowVerticalPadding))
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(isHovered ? SettingsVisualStyle.hover : Color.clear)
        }
        .animation(CommandlyMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityHint(subtitle)
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

    var body: some View {
        HStack(alignment: .center, spacing: density.spacing(.sm)) {
            settingsGlyph(icon, emphasized: isHovered)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: density.spacing(.xs))

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actionDisabled)
                .accessibilityLabel("\(actionTitle) for \(title)")
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

struct SettingsDivider: View {
    var leadingInset: CGFloat = 38

    var body: some View {
        Divider()
            .overlay(SettingsVisualStyle.separator)
            .padding(.leading, leadingInset)
    }
}

struct SettingsStatusBanner: View {
    let message: String
    var tint: CommandlyTint = .blue
    var systemImage = "info.circle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.rawValue) {
            Image(systemName: systemImage)
                .symbolVariant(.fill)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(tint.color)
                .accessibilityHidden(true)

            Text(message)
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

func settingsGlyph(
    _ systemName: String,
    emphasized: Bool = false,
    size: CGFloat = 20
) -> some View {
    Image(systemName: filledSettingsSymbol(for: systemName))
        .symbolVariant(.fill)
        .symbolRenderingMode(.hierarchical)
        .commandlyFont(size: size * 0.62, weight: .medium)
        .foregroundStyle(emphasized ? Color.primary : Color.secondary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
}

func filledSettingsSymbol(for systemName: String) -> String {
    switch systemName {
    case "gearshape": "gearshape.fill"
    case "square.grid.2x2": "square.grid.2x2.fill"
    case "lock.shield": "lock.shield.fill"
    case "info.circle": "info.circle.fill"
    case "power": "power.circle.fill"
    case "keyboard": "keyboard.fill"
    case "rectangle.split.3x1": "rectangle.split.3x1.fill"
    case "face.smiling": "face.smiling.inverse"
    case "calendar": "calendar.circle.fill"
    case "person": "person.crop.circle.fill"
    case "folder": "folder.fill"
    case "accessibility": "accessibility.fill"
    case "brain": "brain.fill"
    case "app": "app.fill"
    case "terminal": "terminal.fill"
    case "puzzlepiece.extension": "puzzlepiece.extension.fill"
    default: systemName
    }
}

extension SettingsPane {
    var filledSystemImage: String {
        filledSettingsSymbol(for: systemImage)
    }

    func matchesSettingsSearch(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return true }
        return settingsSearchText.localizedCaseInsensitiveContains(needle)
    }

    private var settingsSearchText: String {
        let keywords: String
        switch self {
        case .general:
            keywords = "startup open login hotkey shortcut menu bar icon view mode compact comfortable text size larger appearance light dark system emoji picker"
        case .ai:
            keywords = "provider model key credential api endpoint ollama finder artificial intelligence connection"
        case .applications:
            keywords = "apps applications discovery alias shortcut hotkey enabled extension command configuration"
        case .permissions:
            keywords = "privacy calendar contacts files folders accessibility automation access granted denied"
        case .about:
            keywords = "version build bundle identifier information commandly"
        }
        return "\(title) \(subtitle) \(keywords)"
    }
}
