import DesignSystem
import SwiftUI

struct DocumentationRootView: View {
    @State private var viewModel: DocumentationViewModel
    @State private var isSidebarVisible = true
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: DocumentationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            CommandlyWindowVisualEffectBackground()
                .ignoresSafeArea()
            DocumentationVisualStyle.canvas
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if isSidebarVisible {
                    DocumentationSidebar(
                        viewModel: viewModel,
                        isSearchFocused: $isSearchFocused
                    )
                    .frame(width: LayoutConstants.documentationSidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    DocumentationTopBar()

                    Group {
                        if let article = viewModel.selectedArticle {
                            DocumentationArticleView(article: article)
                                .id(article.id)
                                .transition(.opacity.combined(with: .offset(x: 4)))
                        } else {
                            DocumentationEmptyState(query: viewModel.query) {
                                viewModel.clearSearch()
                                isSearchFocused = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DocumentationVisualStyle.detail)
            }
        }
        .frame(
            minWidth: LayoutConstants.documentationMinWidth,
            minHeight: LayoutConstants.documentationMinHeight
        )
        .background(
            CommandlySidebarTitlebarAccessory(
                isSidebarVisible: isSidebarVisible,
                accessibilityIdentifier: "documentation.sidebar.toggle",
                navigationName: "Documentation",
                supplementaryAction: .init(
                    title: "Find in Documentation",
                    systemImage: "magnifyingglass",
                    accessibilityIdentifier: "documentation.find",
                    accessibilityHelp: "Focuses Documentation search",
                    onPerform: focusSearch
                ),
                onToggleSidebar: toggleSidebar
            )
        )
        .compactWindowChrome(
            hidesZoomButton: false,
            accessibilityLabel: "Commandly Documentation"
        )
        .commandlyWindowMaterial()
        .bringHostingWindowToFront(identifier: CommandlyWindowIdentifier.documentation)
        .background {
            DocumentationEscapeKeyInterceptor(onEscape: clearSearchForEscape)
        }
        .animation(
            reduceMotion ? nil : CommandlyMotion.navigation,
            value: isSidebarVisible
        )
        .animation(
            reduceMotion ? nil : CommandlyMotion.navigation,
            value: viewModel.selectedArticleID
        )
        .onAppear { viewModel.refresh() }
        .onKeyPress(keys: [KeyEquivalent("f")], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            focusSearch()
            return .handled
        }
        .onKeyPress(.escape) {
            clearSearchForEscape() ? .handled : .ignored
        }
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
            isSidebarVisible.toggle()
        }
    }

    private func focusSearch() {
        if isSidebarVisible == false {
            withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
                isSidebarVisible = true
            }
        }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func clearSearchForEscape() -> Bool {
        guard viewModel.query.isEmpty == false else { return false }
        viewModel.clearSearch()
        return true
    }
}

private struct DocumentationEmptyState: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No documentation found", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("No article contains “\(query)”. Try a feature name, shortcut, or example.")
        } actions: {
            Button("Clear Search", action: onClear)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .accessibilityIdentifier("documentation.empty-state")
    }
}

#Preview {
    DocumentationRootView(
        viewModel: DocumentationViewModel(registry: LauncherApplicationRegistry())
    )
    .frame(
        width: LayoutConstants.documentationIdealWidth,
        height: LayoutConstants.documentationIdealHeight
    )
}
