import CommandKit
import DesignSystem
import SwiftUI

struct LauncherRootView: View {
    @State private var viewModel: LauncherViewModel
    @State private var transientMenuState = LauncherTransientMenuState()
    private let presentationRequest: WindowPresentationRequest
    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        viewModel: LauncherViewModel,
        presentationRequest: WindowPresentationRequest = .initial
    ) {
        _viewModel = State(initialValue: viewModel)
        self.presentationRequest = presentationRequest
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            Group {
                switch viewModel.route {
                case .root:
                    LauncherHomeView(viewModel: viewModel, onRequestClose: closeLauncher)
                case .application:
                    if let application = viewModel.activeApplication {
                        application.makeSurface()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .uninstallReview:
                    if let uninstallViewModel = viewModel.uninstallViewModel {
                        ApplicationUninstallView(viewModel: uninstallViewModel)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if case .uninstallReview = viewModel.route {
                EmptyView()
            } else if let statusMessage = activeStatusMessage {
                Text(statusMessage)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, density.spacing(.md))
                    .padding(.bottom, density.spacing(.xs))
                    .transition(statusTransition)
            }

            switch viewModel.route {
            case .root:
                LauncherRootFooterBar(
                    appMenuActions: viewModel.appMenuActions,
                    actions: viewModel.footerActions,
                    menuActions: viewModel.rootActionsMenuItems,
                    onAction: { viewModel.performFooterAction($0) }
                )
            case .application:
                LauncherFooterBar(
                    contextTitle: viewModel.contextTitle,
                    contextSystemImage: viewModel.contextSystemImage,
                    actions: viewModel.footerActions,
                    menuActions: viewModel.menuActions,
                    onAction: { viewModel.performFooterAction($0) }
                )
            case .uninstallReview:
                EmptyView()
            }
        }
        .frame(
            width: LayoutConstants.launcherIdealWidth,
            height: density.launcherHeight
        )
        .background {
            ZStack {
                if reduceTransparency == false {
                    LauncherVisualEffectBackground(material: .underWindowBackground)
                }
                SemanticColors.color(for: .background)
                    .opacity(reduceTransparency ? 1 : 0.66)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(reduceTransparency ? 0.16 : 0.11), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        .ignoresSafeArea()
        .overlay {
            if case .application = viewModel.route,
               let session = viewModel.activeApplication,
               session.usesSharedActionsMenu, session.showsActionsMenu {
                LauncherSessionActionsPanel(session: session)
                    .id(ObjectIdentifier(session))
            }
        }
        .overlay {
            if showsContextActionsPanel {
                ZStack(alignment: .bottomLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissContextActionsPanel()
                        }

                    Group {
                        if viewModel.colorSearch.showsActions, let result = viewModel.colorSearch.result {
                            LauncherActionPanel(
                                title: "Copy Color",
                                actions: viewModel.colorSearch.filteredPanelActions,
                                query: Binding(get: { viewModel.colorSearch.actionsQuery }, set: { viewModel.colorSearch.actionsQuery = $0 }),
                                onSelect: { viewModel.colorSearch.perform($0, resultID: result.id) },
                                onDismiss: {
                                    viewModel.colorSearch.dismissActions()
                                    viewModel.requestSearchFocus()
                                },
                                onBack: nil
                            )
                        } else if viewModel.showsApplicationActionsPanel {
                            LauncherActionPanel(
                                title: viewModel.applicationActionsPanelTitle,
                                actions: viewModel.filteredApplicationActions.map(\.panelItem),
                                query: $viewModel.applicationActionsQuery,
                                onSelect: { viewModel.performApplicationAction($0) },
                                onDismiss: { viewModel.dismissApplicationActionsPanel() },
                                onBack: nil
                            )
                        } else {
                            LauncherActionPanel(
                                title: viewModel.registeredCommandActionsPanelTitle,
                                actions: viewModel.filteredRegisteredCommandActions,
                                query: $viewModel.registeredCommandActionsQuery,
                                onSelect: { viewModel.performRegisteredCommandAction($0) },
                                onDismiss: { viewModel.dismissRegisteredCommandActionsPanel() },
                                onBack: nil
                            )
                        }
                    }
                    .padding(.leading, density.spacing(.md))
                    .padding(.bottom, LauncherChromeMetrics.actionPanelBottomInset)
                    .transition(actionPanelTransition)
                }
            }
        }
        .animation(
            reduceMotion ? nil : CommandlyMotion.control,
            value: showsContextActionsPanel
        )
        .sheet(item: $viewModel.commandWheelAssignmentModel) { model in
            CommandWheelAssignmentSheet(model: model)
        }
        .sheet(item: $viewModel.installedApplicationShortcutEditor, onDismiss: {
            viewModel.onInstalledShortcutRecordingChange(false)
            viewModel.requestSearchFocus()
        }) { model in
            InstalledApplicationShortcutEditor(model: model)
        }
        .sheet(item: $viewModel.applicationAliasEditor, onDismiss: {
            viewModel.requestSearchFocus()
        }) { model in
            ApplicationAliasEditor(model: model)
        }
        .launcherWindowChrome(
            presentationRequest: presentationRequest,
            onRequestClose: { closeLauncher() },
            onEscape: {
                if transientMenuState.dismiss() { return true }
                if viewModel.handleEscape() == false {
                    closeLauncher()
                }
                // Always consume Escape while the launcher is key so AppKit
                // TextField editors cannot swallow it without navigating.
                return true
            }
        )
        .onKeyPress(keys: Set(["1", "2", "3", "4", "5", "6"].map { KeyEquivalent(Character($0)) }), phases: .down) { press in
            guard press.modifiers == .command, viewModel.route == .root,
                  case .colorPrimary = viewModel.selectedItem?.action,
                  let format = CommandlyColorFormat.allCases.first(where: { $0.shortcutNumber == String(press.key.character) }) else { return .ignored }
            viewModel.performFooterAction(format.copyActionID)
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("k")], phases: .down) { press in
            if press.modifiers.contains(.command) {
                if viewModel.route == .root {
                    viewModel.presentApplicationActionsForSelection()
                } else if case .application = viewModel.route {
                    viewModel.performFooterAction(BuiltInCommandActionID.openActions)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(phases: .down) { press in
            // Searchable panels own Return for their visible keyboard selection, including
            // empty results. The shell handles only explicit modified application shortcuts.
            guard viewModel.showsApplicationActionsPanel,
                  press.modifiers.intersection([.command, .control, .option]).isEmpty == false
            else { return .ignored }
            let handled = viewModel.handleApplicationActionsKeyPress(
                characters: press.characters,
                modifiers: press.modifiers
            )
            return handled ? .handled : .ignored
        }
        .onAppear {
            viewModel.prepareForPresentation()
        }
        .onChange(of: showsContextActionsPanel) { _, isPresented in
            if isPresented == false, viewModel.route == .root {
                viewModel.requestSearchFocus()
            }
        }
        .onChange(of: viewModel.colorSearch.showsActions) { _, visible in
            if !visible { viewModel.requestSearchFocus() }
        }
        .environment(\.launcherTransientMenuState, transientMenuState)
        .animation(reduceMotion ? nil : CommandlyMotion.navigation, value: viewModel.route)
        .animation(reduceMotion ? nil : CommandlyMotion.hover, value: activeStatusMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commandly launcher")
    }

    private var statusTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var actionPanelTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading))
    }

    private var activeStatusMessage: String? {
        viewModel.activeApplication?.statusMessage ?? (viewModel.route == .root ? viewModel.colorSearch.statusMessage : nil) ?? viewModel.statusMessage
    }

    private var showsContextActionsPanel: Bool {
        viewModel.colorSearch.showsActions || viewModel.showsApplicationActionsPanel || viewModel.showsRegisteredCommandActionsPanel
    }

    private func dismissContextActionsPanel() {
        viewModel.colorSearch.dismissActions()
        viewModel.dismissApplicationActionsPanel()
        viewModel.dismissRegisteredCommandActionsPanel()
    }

    private func closeLauncher() {
        viewModel.dismiss()
    }
}

#Preview {
    LauncherRootView(viewModel: LauncherViewModel())
}
