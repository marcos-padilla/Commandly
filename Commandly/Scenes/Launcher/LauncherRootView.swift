import SwiftUI
import DesignSystem
import AppKit

struct LauncherRootView: View {
    @State private var viewModel: LauncherViewModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.commandlyLayoutDensity) private var density

    init(viewModel: LauncherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            LauncherSearchField(
                query: $viewModel.query,
                onSubmit: { viewModel.confirmSelection() }
            )

            Divider().opacity(0.35)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                        if viewModel.sections.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.sections, id: \.kind) { section in
                                LauncherSectionHeader(title: section.kind.title)

                                ForEach(section.items) { item in
                                    LauncherResultRow(
                                        item: item,
                                        isSelected: item.id == viewModel.selectedItem?.id
                                    ) {
                                        viewModel.select(item.id)
                                        viewModel.confirmSelection()
                                    }
                                    .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, density.spacing(.xs))
                    .padding(.bottom, density.spacing(.sm))
                }
                .frame(maxHeight: .infinity)
                .onChange(of: viewModel.selectedID) { _, newValue in
                    guard let newValue, viewModel.shouldScrollToSelection else { return }
                    withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, density.spacing(.md))
                    .padding(.bottom, density.spacing(.xs))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            LauncherFooterBar(
                primaryActionTitle: viewModel.primaryActionTitle,
                onPrimaryAction: { viewModel.confirmSelection() },
                onOpenSettings: {
                    viewModel.onOpenSettings()
                },
                onClose: { closeLauncher() }
            )
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
        .launcherWindowChrome(onRequestClose: { closeLauncher() })
        .focusable()
        .onKeyPress(.escape) {
            closeLauncher()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveSelection(offset: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelection(offset: 1)
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.confirmSelection()
            return .handled
        }
        .onAppear {
            viewModel.prepareForPresentation()
        }
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: viewModel.statusMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commandly launcher")
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
