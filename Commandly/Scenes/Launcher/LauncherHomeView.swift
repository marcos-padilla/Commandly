import CalculatorKit
import DesignSystem
import SwiftUI

/// Search and result content shown at the launcher root.
struct LauncherHomeView: View {
    @Bindable var viewModel: LauncherViewModel
    let onRequestClose: () -> Void

    @State private var lastPointerLocation: CGPoint?
    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            LauncherSearchField(
                query: $viewModel.query,
                autocompleteSuffix: viewModel.autocompleteSuffix,
                autocompleteActionLabel: viewModel.autocompleteActionLabel,
                focusEpoch: viewModel.searchFocusEpoch,
                onSubmit: viewModel.confirmSelection,
                onMoveSelection: viewModel.moveSelection,
                onAcceptAutocomplete: viewModel.acceptAutocomplete,
                onCancel: handleCancel
            )

            results
        }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.xxxs)) {
                    if viewModel.sections.isEmpty {
                        LauncherHomeEmptyState()
                    } else {
                        calculatorResult
                        resultSections
                    }
                }
                .padding(.top, density.spacing(.xxs))
                .padding(.bottom, density.spacing(.xs))
            }
            .frame(maxHeight: .infinity)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
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
                withAnimation(reduceMotion ? nil : CommandlyMotion.hover) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var calculatorResult: some View {
        if let result = viewModel.activeCalculatorResult,
           let item = viewModel.rootItems.first(where: { $0.section == .calculator }) {
            LauncherSectionHeader(title: LauncherSectionKind.calculator.title)
            CalculatorResultCard(
                result: result,
                isSelected: item.id == viewModel.selectedItem?.id,
                actions: viewModel.menuActions,
                onSelect: { viewModel.select(item.id) },
                onEditQuestion: {
                    viewModel.editCalculatorQuestion(resultID: result.id.rawValue)
                },
                onCopyAnswer: {
                    viewModel.copyCalculatorAnswer(resultID: result.id.rawValue)
                },
                onAction: viewModel.performFooterAction
            )
            .id(item.id)
            .onHover { updateHover(for: item.id, hovering: $0) }
            .padding(.bottom, density.spacing(.xxs))
        }
    }

    private var resultSections: some View {
        ForEach(viewModel.sections.filter { $0.kind != .calculator }, id: \.kind) { section in
            LauncherSectionHeader(title: section.kind.title)

            ForEach(section.items) { item in
                LauncherResultRow(
                    item: item,
                    isSelected: item.id == viewModel.selectedItem?.id,
                    onHoverChange: { updateHover(for: item.id, hovering: $0) },
                    onContextAction: { presentActions(for: item) },
                    action: { activate(item) }
                )
                .id(item.id)
            }
        }
    }

    private func handleCancel() {
        if viewModel.handleEscape() == false {
            onRequestClose()
        }
    }

    private func updateHover(for id: String, hovering: Bool) {
        if hovering {
            viewModel.setHovered(id)
        } else {
            viewModel.clearHovered(id)
        }
    }

    private func presentActions(for item: LauncherItem) {
        viewModel.presentContextActions(for: item)
    }

    private func activate(_ item: LauncherItem) {
        viewModel.select(item.id)
        viewModel.confirmSelection()
    }
}

private struct LauncherHomeEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 22, weight: .medium)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .commandlyFont(size: 13, weight: .semibold)
            Text("Try a different search.")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl.rawValue)
        .accessibilityElement(children: .combine)
    }
}
