import DesignSystem
import CommandKit
import SwiftUI

struct CalculatorHistoryView: View {
    @Bindable var viewModel: CalculatorHistoryViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search calculations…",
            searchAccessibilityIdentifier: "calculator-history-query",
            onBack: viewModel.goBack,
            onSubmit: { viewModel.perform(BuiltInCommandActionID.copy) },
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false { viewModel.goBack() }
            }
        ) {
            EmptyView()
        } sidebar: {
            historyList
        } detail: {
            historyDetail
        }
        .accessibilityLabel("Calculation History")
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: density.spacing(.xxs)) {
                    if viewModel.filteredEntries.isEmpty {
                        LauncherApplicationEmptyState(
                            systemImage: "clock.arrow.circlepath",
                            title: "No calculations yet",
                            message: "Copy a calculator answer to add it to this session history."
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(viewModel.filteredEntries) { entry in
                            LauncherApplicationRow(
                                isSelected: entry.id == viewModel.selectedEntry?.id,
                                onSelect: { viewModel.select(entry.id) },
                                onOpen: { viewModel.perform(BuiltInCommandActionID.copy) },
                                onHoverChange: { hovering in
                                    if hovering { viewModel.select(entry.id) }
                                }
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.formattedValue)
                                        .commandlyFont(size: 13, weight: .semibold)
                                        .lineLimit(1)
                                    Text(entry.expression)
                                        .commandlyFont(size: 10)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } accessory: {
                                Text(entry.createdAt, style: .time)
                                    .commandlyFont(size: 9)
                                    .foregroundStyle(.tertiary)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                guard let id, viewModel.shouldScrollToSelection else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var historyDetail: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    Text("Expression")
                        .commandlyFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Text(entry.expression)
                        .commandlyFont(size: 17, weight: .medium, design: .monospaced)
                        .textSelection(.enabled)
                    Divider().opacity(0.35)
                    Text("Result")
                        .commandlyFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Text(entry.formattedValue)
                        .commandlyFont(size: 28, weight: .semibold)
                        .textSelection(.enabled)
                    Spacer()
                    LauncherApplicationMetadataRow(
                        label: "Recorded",
                        value: entry.createdAt.formatted(date: .abbreviated, time: .standard),
                        labelWidth: 72,
                        fontSize: 11,
                        truncatesValue: false
                    )
                }
                .padding(density.spacing(.lg))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                LauncherApplicationEmptyState(
                    systemImage: "function",
                    title: "Select a calculation",
                    message: "Results stay local to the current Commandly session."
                )
            }
        }
    }
}
