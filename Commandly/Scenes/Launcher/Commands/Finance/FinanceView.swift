import DesignSystem
import SwiftUI

struct FinanceView: View {
    @Bindable var viewModel: FinanceViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)

            HStack(spacing: 0) {
                navigation
                    .frame(width: 158)
                    .background(LauncherPalette.sidebar)

                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(width: 1)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LauncherPalette.detail)
            }
        }
        .task {
            viewModel.startLoadingIfNeeded()
        }
        .sheet(item: $viewModel.presentation) { presentation in
            switch presentation {
            case .subscription(let draft):
                FinanceSubscriptionEditor(viewModel: viewModel, initialDraft: draft)
            case .budget(let draft):
                FinanceBudgetEditor(viewModel: viewModel, initialDraft: draft)
            }
        }
        .alert(
            "Delete subscription?",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { isPresented in
                    if isPresented == false { viewModel.pendingDeletion = nil }
                }
            ),
            presenting: viewModel.pendingDeletion
        ) { _ in
            Button("Delete", role: .destructive) {
                viewModel.confirmDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: { subscription in
            Text("\(subscription.name) will be permanently removed from this Mac.")
        }
        .accessibilityLabel("Finance")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: viewModel.section.systemImage)
                    .commandlyFont(size: 14, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .accessibilityHidden(true)

                if viewModel.section == .subscriptions {
                    TextField("Search subscriptions…", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .commandlyFont(size: 15, weight: .medium)
                        .accessibilityLabel("Search subscriptions")
                        .onSubmit {
                            if let selected = viewModel.selectedSubscription {
                                viewModel.beginEditing(selected)
                            }
                        }
                        .onKeyPress(.upArrow) {
                            viewModel.moveSelection(offset: -1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            viewModel.moveSelection(offset: 1)
                            return .handled
                        }
                } else {
                    Text(viewModel.section.title)
                        .commandlyFont(size: 15, weight: .semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving finance data")
            }

            Button {
                viewModel.beginNewSubscription()
            } label: {
                Label("Add", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .commandlyFont(size: 12, weight: .semibold)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add subscription")
            .help("Add Subscription (Command-N)")
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: density.spacing(.xxs)) {
            ForEach(FinanceSection.allCases) { section in
                Button {
                    viewModel.selectSection(section)
                } label: {
                    HStack(spacing: density.spacing(.xs)) {
                        Image(systemName: section.systemImage)
                            .commandlyFont(size: 11, weight: .semibold)
                            .frame(width: 18)
                        Text(section.title)
                            .commandlyFont(size: 10.5, weight: .medium)
                        Spacer(minLength: 0)
                        if section == .subscriptions {
                            Text("\(viewModel.dashboard.activePlanCount)")
                                .commandlyFont(size: 9, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, density.spacing(.xs))
                    .frame(height: 31)
                    .background(
                        section == viewModel.section
                            ? LauncherPalette.selection
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(section == viewModel.section ? .isSelected : [])
            }

            Spacer(minLength: density.spacing(.sm))

            VStack(alignment: .leading, spacing: 3) {
                Label("Local only", systemImage: "lock.fill")
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text("No bank connection")
                    .commandlyFont(size: 8.5)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, density.spacing(.xs))
            .padding(.bottom, density.spacing(.sm))
            .accessibilityElement(children: .combine)
        }
        .padding(density.spacing(.xs))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading finance data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.section {
            case .dashboard:
                FinanceDashboardView(viewModel: viewModel)
            case .subscriptions:
                FinanceSubscriptionsView(viewModel: viewModel)
            case .calendar:
                FinanceCalendarView(viewModel: viewModel)
            case .categories:
                FinanceCategoriesView(viewModel: viewModel)
            case .budgets:
                FinanceBudgetsView(viewModel: viewModel)
            }
        }
    }
}
