import AppCore
import DesignSystem
import Infrastructure
import SecurityKit
import SwiftUI

struct SettingsRootView: View {
    @State private var viewModel: SettingsViewModel
    @State private var systemIntegrationModel: SystemIntegrationSettingsModel
    private let keyboardTriggerSettings: KeyboardTriggerSettingsModel?
    @State private var isSidebarVisible = true
    @State private var sidebarQuery = ""
    @State private var sidebarSearchFocusEpoch = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: SettingsViewModel, systemIntegrationModel: SystemIntegrationSettingsModel? = nil, keyboardTriggerSettings: KeyboardTriggerSettingsModel? = nil) {
        self.keyboardTriggerSettings = keyboardTriggerSettings
        _viewModel = State(initialValue: viewModel)
        _systemIntegrationModel = State(initialValue: systemIntegrationModel ?? SystemCompanionApplicationServices.inMemory().settings)
    }

    var body: some View {
        ZStack {
            CommandlyWindowVisualEffectBackground()
                .ignoresSafeArea()
            SettingsVisualStyle.windowBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if isSidebarVisible {
                    SettingsSidebar(
                        selection: $viewModel.selectedPane,
                        query: $sidebarQuery,
                        searchFocusEpoch: sidebarSearchFocusEpoch,
                        versionLabel: versionLabel
                    )
                    .frame(width: LayoutConstants.settingsSidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    SettingsTopBar(selectedPane: viewModel.selectedPane)

                    ZStack {
                        pageContent
                            .id(viewModel.selectedPane)
                            .transition(pageTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsVisualStyle.detailBackground)
            }
        }
        .frame(
            minWidth: LayoutConstants.settingsMinWidth,
            minHeight: LayoutConstants.settingsMinHeight
        )
        .background(
            CommandlySidebarTitlebarAccessory(
                isSidebarVisible: isSidebarVisible,
                accessibilityIdentifier: "settings.sidebar.toggle",
                navigationName: "Settings",
                onToggleSidebar: toggleSidebar
            )
        )
        .compactWindowChrome(
            hidesZoomButton: false,
            accessibilityLabel: "Commandly Settings"
        )
        .commandlyWindowMaterial()
        .bringHostingWindowToFront(identifier: CommandlyWindowIdentifier.settings)
        .commandlyContentSize(viewModel.textSize)
        .commandlyViewMode(viewModel.viewMode)
        .animation(reduceMotion ? nil : CommandlyMotion.navigation, value: viewModel.selectedPane)
        .onAppear {
            viewModel.onAppear()
        }
        .onKeyPress(keys: [KeyEquivalent("f")], phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            isSidebarVisible = true
            sidebarSearchFocusEpoch += 1
            return .handled
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 4)),
            removal: .opacity.combined(with: .offset(x: -3))
        )
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
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
        case .commandWheel:
            CommandWheelSettingsPage(
                model: viewModel.commandWheel,
                permissionState: viewModel.state(for: .accessibility),
                onOpenPermissions: { viewModel.selectedPane = .permissions }
            )
        case .permissions:
            PermissionsSettingsPage(viewModel: viewModel)
        case .systemIntegration:
            SystemIntegrationSettingsPage(model: systemIntegrationModel, keyboardTriggers: keyboardTriggerSettings)
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
    @Binding var query: String
    let searchFocusEpoch: Int
    let versionLabel: String

    private var filteredPanes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matchesSettingsSearch(query) }
    }

    private var listSelection: Binding<SettingsPane?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSidebarSearchField(
                query: $query,
                focusEpoch: searchFocusEpoch,
                onSubmit: {
                    if filteredPanes.contains(selection) == false,
                       let first = filteredPanes.first { selection = first }
                },
                onMoveSelection: moveSelection
            )
                .padding(.horizontal, Spacing.sm.rawValue)
                .frame(height: SettingsTopBar.height)

            List(selection: listSelection) {
                if filteredPanes.isEmpty {
                    VStack(spacing: Spacing.xs.rawValue) {
                        Image(systemName: "magnifyingglass")
                            .commandlyFont(size: 17, weight: .medium)
                            .foregroundStyle(.tertiary)
                        Text("No settings found")
                            .commandlyFont(size: 11.5, weight: .medium)
                        Text("Try a pane name or setting, such as Appearance or Calendar.")
                            .commandlyFont(size: 11)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg.rawValue)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(filteredPanes) { pane in
                        SettingsSidebarItem(
                            pane: pane,
                            isSelected: selection == pane
                        )
                        .tag(pane)
                        .listRowInsets(
                            EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)

            Text("Version \(versionLabel)")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.bottom, Spacing.sm.rawValue)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsVisualStyle.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsVisualStyle.separator)
                .frame(width: 1)
        }
    }

    private func moveSelection(_ direction: Int) {
        var navigation = LauncherMenuSelection<SettingsPane>()
        navigation.select(selection, in: filteredPanes)
        navigation.move(by: direction, in: filteredPanes)
        if let pane = navigation.selectedID { selection = pane }
    }
}

private struct SettingsSidebarSearchField: View {
    @Binding var query: String
    let focusEpoch: Int
    let onSubmit: () -> Void
    let onMoveSelection: (Int) -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 11, weight: .medium)
                .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                .accessibilityHidden(true)

            TextField("Search Settings", text: $query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 11.5)
                .focused($isFocused)
                .accessibilityLabel("Search Settings panes")
                .accessibilityIdentifier("settings.search")
                .onSubmit(onSubmit)
                .onKeyPress(.upArrow) {
                    onMoveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMoveSelection(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard query.isEmpty == false else { return .ignored }
                    query = ""
                    return .handled
                }

            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear Settings search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            SettingsVisualStyle.fieldBackground,
            in: RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .strokeBorder(
                    isFocused ? SettingsVisualStyle.focusRing : .clear,
                    lineWidth: 1
                )
        }
        .animation(reduceMotion ? nil : CommandlyMotion.hover, value: isFocused)
        .onAppear {
            if focusEpoch > 0 { isFocused = true }
        }
        .onChange(of: focusEpoch) { _, _ in isFocused = true }
    }
}

private struct SettingsSidebarItem: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            settingsGlyph(
                pane.filledSystemImage,
                emphasized: isSelected,
                size: 19
            )

            Text(pane.title)
                .commandlyFont(size: 12, weight: isSelected ? .semibold : .regular)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
