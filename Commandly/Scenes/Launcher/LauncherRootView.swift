import CommandKit
import DesignSystem
import SwiftUI

struct LauncherRootView: View {
    @State private var viewModel: LauncherViewModel
    private let presentationRequest: WindowPresentationRequest
    @Environment(\.commandlyLayoutDensity) private var density

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
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                    showsActionsMenu: Binding(
                        get: { viewModel.showsActionsMenu },
                        set: { viewModel.showsActionsMenu = $0 }
                    ),
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
                LauncherVisualEffectBackground(material: .hudWindow)
                LauncherPalette.canvas
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.055),
                        Color.clear,
                        BrandPalette.accent.opacity(0.035),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 32, y: 16)
        .ignoresSafeArea()
        .overlay {
            if viewModel.showsApplicationActionsPanel {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.dismissApplicationActionsPanel()
                        }

                    LauncherActionPanel(
                        title: viewModel.applicationActionsPanelTitle,
                        actions: viewModel.filteredApplicationActions.map(\.panelItem),
                        query: $viewModel.applicationActionsQuery,
                        onSelect: { viewModel.performApplicationAction($0) },
                        onDismiss: { viewModel.dismissApplicationActionsPanel() },
                        onBack: nil
                    )
                    .padding(.trailing, density.spacing(.md))
                    .padding(.bottom, 52)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                }
            }
        }
        .animation(
            .easeInOut(duration: MotionDuration.fast.rawValue),
            value: viewModel.showsApplicationActionsPanel
        )
        .launcherWindowChrome(
            presentationRequest: presentationRequest,
            onRequestClose: { closeLauncher() },
            onEscape: {
                if viewModel.handleEscape() == false {
                    closeLauncher()
                }
                // Always consume Escape while the launcher is key so AppKit
                // TextField editors cannot swallow it without navigating.
                return true
            }
        )
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
            guard viewModel.showsApplicationActionsPanel else { return .ignored }
            let handled = viewModel.handleApplicationActionsKeyPress(
                characters: press.characters,
                modifiers: press.modifiers
            )
            return handled ? .handled : .ignored
        }
        .onAppear {
            viewModel.prepareForPresentation()
        }
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: viewModel.route)
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: activeStatusMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commandly launcher")
    }

    private var activeStatusMessage: String? {
        viewModel.activeApplication?.statusMessage ?? viewModel.statusMessage
    }

    private func closeLauncher() {
        viewModel.dismiss()
    }
}

#Preview {
    LauncherRootView(viewModel: LauncherViewModel())
}
