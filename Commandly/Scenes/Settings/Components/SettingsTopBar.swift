import DesignSystem
import SwiftUI

/// Persistent Settings chrome that keeps navigation controls available when
/// the sidebar is collapsed.
struct SettingsTopBar: View {
    static let titlebarInset: CGFloat = 28
    static let height: CGFloat = 38

    let selectedPane: SettingsPane
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void

    @State private var isToggleHovered = false

    var body: some View {
        HStack(spacing: 9) {
            sidebarToggle

            Rectangle()
                .fill(SettingsPalette.border)
                .frame(width: 1, height: 16)

            Image(systemName: selectedPane.systemImage)
                .symbolVariant(.fill)
                .commandlyFont(size: 9.5, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 15)

            Text(selectedPane.title)
                .commandlyFont(size: 10.5, weight: .semibold)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background {
            ZStack {
                SettingsPalette.card.opacity(0.72)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.035),
                        BrandPalette.accent.opacity(0.025),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsPalette.border)
                .frame(height: 1)
        }
        .animation(
            .easeInOut(duration: MotionDuration.normal.rawValue),
            value: selectedPane
        )
        .accessibilityElement(children: .contain)
    }

    private var sidebarToggle: some View {
        Button(action: onToggleSidebar) {
            Image(systemName: "sidebar.left")
                .symbolVariant(isSidebarVisible ? .fill : .none)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(
                    isSidebarVisible
                        ? Color.secondary
                        : BrandPalette.accentSoft
                )
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isSidebarVisible
                                ? Color.primary.opacity(isToggleHovered ? 0.085 : 0.045)
                                : BrandPalette.accent.opacity(isToggleHovered ? 0.2 : 0.14)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isSidebarVisible
                                ? SettingsPalette.border
                                : BrandPalette.accent.opacity(0.3),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular
                .tint(BrandPalette.accent.opacity(isSidebarVisible ? 0.015 : 0.06))
                .interactive(),
            in: .rect(cornerRadius: 7)
        )
        .scaleEffect(isToggleHovered ? 1.04 : 1)
        .animation(
            .easeOut(duration: MotionDuration.fast.rawValue),
            value: isToggleHovered
        )
        .onHover { hovering in
            isToggleHovered = hovering
        }
        .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityIdentifier("settings.sidebar.toggle")
        .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
        .accessibilityHint("Toggles the Settings navigation sidebar")
    }
}

#Preview {
    SettingsTopBarPreview()
        .frame(width: 760, height: SettingsTopBar.height)
}

private struct SettingsTopBarPreview: View {
    @State private var isSidebarVisible = true

    var body: some View {
        SettingsTopBar(
            selectedPane: .applications,
            isSidebarVisible: isSidebarVisible,
            onToggleSidebar: { isSidebarVisible.toggle() }
        )
    }
}
