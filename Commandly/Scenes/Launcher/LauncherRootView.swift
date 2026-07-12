import SwiftUI
import DesignSystem
import AppKit
import CommandKit
import CalculatorKit

struct LauncherRootView: View {
    @State private var viewModel: LauncherViewModel
    @State private var lastPointerLocation: CGPoint?
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.commandlyLayoutDensity) private var density

    init(viewModel: LauncherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            Group {
                switch viewModel.route {
                case .root:
                    rootContent
                case .command(let id) where id == BuiltInCommandID.clipboardHistory:
                    if let clipboardViewModel = viewModel.clipboardViewModel {
                        ClipboardHistoryView(viewModel: clipboardViewModel)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .command(let id) where id == BuiltInCommandID.searchFiles:
                    if let fileSearchViewModel = viewModel.fileSearchViewModel {
                        FileSearchView(viewModel: fileSearchViewModel)
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
                case .command:
                    Text("This command has no surface yet.")
                        .commandlyFont(size: 13)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            case .command:
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
            LauncherVisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                }
            }
        }
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: viewModel.showsApplicationActionsPanel)
        .launcherWindowChrome(onRequestClose: { closeLauncher() })
        .onKeyPress(.escape) {
            if viewModel.handleEscape() == false {
                closeLauncher()
            }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("k")], phases: .down) { press in
            if press.modifiers.contains(.command) {
                if viewModel.route == .root {
                    viewModel.presentApplicationActionsForSelection()
                } else if case .command = viewModel.route {
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
        viewModel.clipboardViewModel?.statusMessage
            ?? viewModel.fileSearchViewModel?.statusMessage
            ?? viewModel.statusMessage
    }

    private var rootContent: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 0) {
            LauncherSearchField(
                query: $viewModel.query,
                autocompleteSuffix: viewModel.autocompleteSuffix,
                autocompleteActionLabel: viewModel.autocompleteActionLabel,
                focusEpoch: viewModel.searchFocusEpoch,
                onSubmit: { viewModel.confirmSelection() },
                onMoveSelection: { viewModel.moveSelection(offset: $0) },
                onAcceptAutocomplete: { viewModel.acceptAutocomplete() },
                onCancel: {
                    if viewModel.handleEscape() == false {
                        closeLauncher()
                    }
                }
            )

            Divider().opacity(0.22)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: density.spacing(.xxxs)) {
                        if viewModel.sections.isEmpty {
                            emptyState
                        } else {
                            if let calculatorResult = viewModel.activeCalculatorResult,
                               let calculatorItem = viewModel.rootItems.first(where: { $0.section == .calculator }) {
                                LauncherSectionHeader(title: LauncherSectionKind.calculator.title)
                                CalculatorResultCard(
                                    result: calculatorResult,
                                    isSelected: calculatorItem.id == viewModel.selectedItem?.id,
                                    actions: viewModel.menuActions,
                                    onSelect: { viewModel.select(calculatorItem.id) },
                                    onEditQuestion: {
                                        viewModel.editCalculatorQuestion(resultID: calculatorResult.id.rawValue)
                                    },
                                    onCopyAnswer: {
                                        viewModel.copyCalculatorAnswer(resultID: calculatorResult.id.rawValue)
                                    },
                                    onAction: { viewModel.performFooterAction($0) }
                                )
                                .id(calculatorItem.id)
                                .onHover { hovering in
                                    if hovering {
                                        viewModel.setHovered(calculatorItem.id)
                                    } else {
                                        viewModel.clearHovered(calculatorItem.id)
                                    }
                                }
                                .padding(.bottom, density.spacing(.xxs))
                            }

                            ForEach(viewModel.sections.filter { $0.kind != .calculator }, id: \.kind) { section in
                                LauncherSectionHeader(title: section.kind.title)

                                ForEach(section.items) { item in
                                    LauncherResultRow(
                                        item: item,
                                        isSelected: item.id == viewModel.selectedItem?.id,
                                        onHoverChange: { hovering in
                                            if hovering {
                                                viewModel.setHovered(item.id)
                                            } else {
                                                viewModel.clearHovered(item.id)
                                            }
                                        },
                                        onContextAction: {
                                            guard case .openApplication(let bundleID) = item.action else {
                                                return
                                            }
                                            viewModel.select(item.id)
                                            viewModel.presentApplicationActions(forBundleID: bundleID)
                                        }
                                    ) {
                                        viewModel.select(item.id)
                                        viewModel.confirmSelection()
                                    }
                                    .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, density.spacing(.xxs))
                    .padding(.bottom, density.spacing(.xs))
                }
                .frame(maxHeight: .infinity)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { oldOffset, newOffset in
                    guard oldOffset != newOffset else { return }
                    viewModel.beginResultsScrolling()
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if lastPointerLocation != location {
                            lastPointerLocation = location
                            viewModel.beginPointerInput()
                        }
                    case .ended:
                        lastPointerLocation = nil
                    }
                }
                .onChange(of: viewModel.selectedID) { _, newValue in
                    guard let newValue, viewModel.shouldScrollToSelection else { return }
                    withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 22, weight: .medium)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .commandlyFont(size: 13, weight: .semibold)
            Text("Try a different search.")
                .commandlyFont(size: 11, weight: .regular)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl.rawValue)
        .accessibilityElement(children: .combine)
    }

    private func closeLauncher() {
        viewModel.dismiss()
        dismissWindow(id: AppWindowID.launcher)
    }
}

#Preview {
    LauncherRootView(viewModel: LauncherViewModel())
}
