import SwiftUI
import DesignSystem
import AppCore
import Infrastructure
import SecurityKit

struct SettingsRootView: View {
    @State private var viewModel: SettingsViewModel
    @Namespace private var sidebarNamespace

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $viewModel.selectedPane,
                versionLabel: versionLabel,
                namespace: sidebarNamespace
            )
            .frame(width: LayoutConstants.settingsSidebarWidth)

            ZStack {
                pageContent
                    .id(viewModel.selectedPane)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
        }
        .frame(
            minWidth: LayoutConstants.settingsMinWidth,
            minHeight: LayoutConstants.settingsMinHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .compactWindowChrome(hidesZoomButton: true)
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

    @ViewBuilder
    private var pageContent: some View {
        switch viewModel.selectedPane {
        case .general:
            GeneralSettingsPage(viewModel: viewModel)
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
            .padding(.top, Spacing.lg.rawValue)

            Spacer(minLength: Spacing.md.rawValue)

            Text(versionLabel)
                .commandlyFont(size: 10)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.bottom, Spacing.md.rawValue)
                .contentTransition(.numericText())
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
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
                    .commandlyFont(size: 11, weight: isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? .primary : (isHovered ? .secondary : .tertiary))
                    .frame(width: 14)
                    .symbolEffect(.bounce, value: isSelected)

                    Text(pane.title)
                    .commandlyFont(size: 12, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.8) : Color.secondary))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .matchedGeometryEffect(id: "settings-sidebar-selection", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
