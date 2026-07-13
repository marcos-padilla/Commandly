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
                Color.clear
                    .frame(height: DocumentationTopBar.titlebarInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                DocumentationTopBar(
                    article: viewModel.selectedArticle,
                    isSidebarVisible: isSidebarVisible,
                    onToggleSidebar: toggleSidebar,
                    onFocusSearch: focusSearch
                )

                Group {
                    if let article = viewModel.selectedArticle {
                        DocumentationArticleView(article: article)
                            .id(article.id)
                            .transition(.opacity.combined(with: .offset(x: 8)))
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
        }
        .frame(
            minWidth: LayoutConstants.documentationMinWidth,
            minHeight: LayoutConstants.documentationMinHeight
        )
        .background {
            ZStack {
                CommandlyWindowVisualEffectBackground()
                SettingsPalette.canvas
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.055),
                        Color.clear,
                        BrandPalette.accent.opacity(0.055),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .compactWindowChrome(hidesZoomButton: false)
        .commandlyWindowMaterial()
        .bringHostingWindowToFront(identifier: CommandlyWindowIdentifier.documentation)
        .background {
            DocumentationEscapeKeyInterceptor(onEscape: clearSearchForEscape)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88), value: isSidebarVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.selectedArticleID)
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
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) {
            isSidebarVisible.toggle()
        }
    }

    private func focusSearch() {
        if isSidebarVisible == false {
            withAnimation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)
            ) {
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
                .buttonStyle(.glassProminent)
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
