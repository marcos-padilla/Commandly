import SwiftUI
import DesignSystem
import AppCore
import Infrastructure
import SecurityKit

struct SettingsRootView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $viewModel.selectedPane, versionLabel: versionLabel)
                .frame(width: LayoutConstants.settingsSidebarWidth)

            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                pageContent
                    .id(viewModel.selectedPane)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: LayoutConstants.settingsMinWidth,
            minHeight: LayoutConstants.settingsMinHeight
        )
        .background(settingsBackground)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.selectedPane)
        .onAppear {
            viewModel.onAppear()
        }
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
        "\(viewModel.metadata.name) \(viewModel.metadata.version)"
    }

    private var settingsBackground: some View {
        ZStack {
            Color.black.opacity(0.35)
            Rectangle()
                .fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    let versionLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.top, Spacing.lg.rawValue)
                .padding(.bottom, Spacing.sm.rawValue)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selection = pane
                    } label: {
                        HStack(spacing: Spacing.sm.rawValue) {
                            Image(systemName: pane.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(sidebarIconColor(for: pane).gradient)
                                )

                            Text(pane.title)
                                .font(.system(size: 12, weight: selection == pane ? .semibold : .medium))
                                .foregroundStyle(selection == pane ? .primary : .secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            if selection == pane {
                                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                    .fill(Color.primary.opacity(0.10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                    }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pane.title)
                    .accessibilityAddTraits(selection == pane ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)

            Spacer(minLength: Spacing.md.rawValue)

            Divider()
                .opacity(0.35)
                .padding(.horizontal, Spacing.md.rawValue)

            VStack(spacing: 6) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(BrandPalette.accent)
                    .symbolRenderingMode(.hierarchical)

                Text(versionLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md.rawValue)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func sidebarIconColor(for pane: SettingsPane) -> Color {
        switch pane {
        case .general: return BrandPalette.accent
        case .permissions: return .indigo
        case .about: return .teal
        }
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
