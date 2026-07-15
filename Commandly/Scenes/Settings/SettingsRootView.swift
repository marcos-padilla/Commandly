import AppCore
import DesignSystem
import Infrastructure
import SecurityKit
import SwiftUI

struct SettingsRootView: View {
    @State private var viewModel: SettingsViewModel
    @State private var isSidebarVisible = true
    @Namespace private var sidebarNamespace

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SettingsSidebar(
                    selection: $viewModel.selectedPane,
                    versionLabel: versionLabel,
                    namespace: sidebarNamespace
                )
                .frame(width: LayoutConstants.settingsSidebarWidth)
                .transition(
                    .move(edge: .leading)
                        .combined(with: .opacity)
                )
            }

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: SettingsTopBar.titlebarInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                SettingsTopBar(
                    selectedPane: viewModel.selectedPane,
                    isSidebarVisible: isSidebarVisible,
                    onToggleSidebar: toggleSidebar
                )

                ZStack {
                    pageContent
                        .id(viewModel.selectedPane)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .frame(
            minWidth: LayoutConstants.settingsApplicationsMinWidth,
            minHeight: LayoutConstants.settingsApplicationsMinHeight
        )
        .background {
            ZStack {
                CommandlyWindowVisualEffectBackground()
                SettingsPalette.canvas
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear,
                        BrandPalette.accent.opacity(0.045),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .compactWindowChrome(hidesZoomButton: true)
        .commandlyWindowMaterial()
        .bringHostingWindowToFront(identifier: CommandlyWindowIdentifier.settings)
        .commandlyContentSize(viewModel.textSize)
        .commandlyViewMode(viewModel.viewMode)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.selectedPane)
        .onAppear {
            viewModel.onAppear()
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: 10))
                .combined(with: .scale(scale: 0.992, anchor: .leading)),
            removal: .opacity
                .combined(with: .offset(x: -6))
        )
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isSidebarVisible.toggle()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch viewModel.selectedPane {
        case .general:
            GeneralSettingsPage(viewModel: viewModel)
        case .ai:
            AISettingsPage(model: viewModel.ai)
        case .applications:
            ApplicationsSettingsPage(model: viewModel.applications)
        case .permissions:
            PermissionsSettingsPage(viewModel: viewModel)
        case .about:
            AboutSettingsPage(viewModel: viewModel)
        }
    }

    private var versionLabel: String {
        "\(viewModel.metadata.version) (\(viewModel.metadata.build))"
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    let versionLabel: String
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CommandlyApplicationIcon(size: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Commandly")
                        .commandlyFont(size: 13, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text("Settings")
                        .commandlyFont(size: 10, weight: .medium)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 42)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarItem(
                        pane: pane,
                        isSelected: selection == pane,
                        namespace: namespace
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            selection = pane
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: Spacing.md.rawValue)

            Text(versionLabel)
                .commandlyFont(size: 10)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.bottom, Spacing.md.rawValue)
                .contentTransition(.numericText())
        }
        .background(SettingsPalette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsPalette.border)
                .frame(width: 1)
        }
    }
}

private struct SettingsSidebarItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.systemImage)
                    .symbolVariant(.fill)
                    .commandlyFont(size: 11, weight: .semibold)
                    .foregroundStyle(
                        isSelected
                            ? BrandPalette.accentSoft
                            : Color.secondary.opacity(isHovered ? 0.85 : 0.6)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isSelected
                                    ? BrandPalette.accent.opacity(0.16)
                                    : Color.primary.opacity(0.045))
                    )
                    .symbolEffect(.bounce, value: isSelected)

                Text(pane.title)
                    .commandlyFont(size: 12, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : (isHovered ? Color.primary.opacity(0.8) : Color.secondary))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.085))
                            .matchedGeometryEffect(id: "settings-sidebar-selection", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? SettingsPalette.border : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.01 : 1)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    SettingsRootView(
        viewModel: SettingsViewModel(
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .development
            )
        )
    )
}
