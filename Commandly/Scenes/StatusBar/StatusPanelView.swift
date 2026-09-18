import AppKit
import DesignSystem
import SwiftUI

/// Menu bar panel for the always-on Commandly status item.
///
/// A navigation strip of section tabs sits under the brand row; the selected section fills a
/// scrolling body, and Settings / Quit stay pinned to the footer.
struct StatusPanelView: View {
    @Bindable var runtime: AppRuntime
    @AppStorage("statusPanel.selectedSection") private var selectedSectionID = StatusPanelSection
        .keepAwake.rawValue
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var selectedSection: StatusPanelSection {
        StatusPanelSection(rawValue: selectedSectionID) ?? .keepAwake
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
            brandRow
            navigationStrip
            StatusPanelSectionHeader(selectedSection.title)

            MeasuredScrollView(
                width: StatusPanelChrome.contentWidth,
                maximumHeight: maximumBodyHeight,
                estimatedHeight: selectedSection.estimatedHeight
            ) {
                sectionBody
                    .padding(.bottom, 2)
            }

            footer
        }
        .padding(Spacing.sm.rawValue)
        .frame(width: StatusPanelChrome.contentWidth + Spacing.sm.rawValue * 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commandly menu bar panel")
    }

    /// Caps the body against the screen the menu bar is on, so a long section scrolls instead of
    /// running off the bottom of the display.
    private var maximumBodyHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(240, min(620, visibleHeight - 180))
    }

    private var brandRow: some View {
        HStack(spacing: Spacing.xs.rawValue - 2) {
            Image(systemName: "command")
                .commandlyFont(size: 14, weight: .semibold)
                .accessibilityHidden(true)
            Text("Commandly")
                .commandlyFont(size: 13, weight: .semibold)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .accessibilityAddTraits(.isHeader)
    }

    private var navigationStrip: some View {
        HStack(spacing: 2) {
            ForEach(StatusPanelSection.allCases) { section in
                navigationTab(section)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: StatusPanelChrome.cardCornerRadius, style: .continuous)
                .fill(LauncherPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StatusPanelChrome.cardCornerRadius, style: .continuous)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel sections")
    }

    private func navigationTab(_ section: StatusPanelSection) -> some View {
        let isActive = section == selectedSection
        return Button {
            withAnimation(CommandlyMotion.control) {
                selectedSectionID = section.rawValue
            }
        } label: {
            Image(systemName: section.symbolName)
                .commandlyFont(size: 13, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(height: StatusPanelChrome.navigationTabHeight)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: StatusPanelChrome.controlCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: StatusPanelChrome.controlCornerRadius, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch selectedSection {
        case .keepAwake:
            KeepAwakePanelSection(coordinator: runtime.keepAwake)
        case .volumeMixer:
            VolumeMixerPanelSection(model: runtime.volumeMixer)
        case .system:
            SystemPanelSection(monitor: runtime.systemMetrics)
        case .network:
            NetworkPanelSection(monitor: runtime.networkMetrics)
        case .disk:
            DiskPanelSection(monitor: runtime.diskMetrics)
        case .power:
            PowerPanelSection(monitor: runtime.powerMetrics)
        case .fans:
            FanControlPanelSection(monitor: runtime.fanControl)
        case .quickToggles:
            QuickTogglesPanelSection(model: runtime.quickToggles)
        case .controls:
            ControlsPanelSection(model: runtime.controls)
        case .utilities:
            StatusPanelUtilitiesSection(
                runtime: runtime,
                onOpenSettings: presentSettings,
                onOpenDocumentation: presentDocumentation,
                onRestartOnboarding: restartOnboarding
            )
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            StatusPanelFooterButton(title: "Settings", symbolName: "gearshape", action: presentSettings)
            StatusPanelFooterButton(title: "Quit", symbolName: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .padding(.top, 2)
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.settings)
    }

    private func presentDocumentation() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppWindowID.documentation)
        DispatchQueue.main.async {
            BringHostingWindowToFront.raiseWindows(
                with: CommandlyWindowIdentifier.documentation
            )
        }
    }

    private func restartOnboarding() {
        runtime.restartOnboarding()
        openWindow(id: AppWindowID.onboarding)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#Preview {
    StatusPanelView(runtime: AppRuntime())
}
