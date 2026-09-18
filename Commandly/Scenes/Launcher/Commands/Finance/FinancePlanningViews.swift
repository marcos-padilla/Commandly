import DesignSystem
import SwiftUI

struct FinanceCategoriesView: View {
    @Bindable var viewModel: FinanceViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155), spacing: density.spacing(.xs))],
                spacing: density.spacing(.xs)
            ) {
                ForEach(viewModel.categorySummaries) { summary in
                    categoryCard(summary)
                }
            }
            .padding(density.spacing(.md))
        }
    }

    private func categoryCard(_ summary: FinanceCategorySummary) -> some View {
        Button {
            viewModel.query = summary.category.title
            viewModel.subscriptionFilter = .active
            viewModel.selectSection(.subscriptions)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: summary.category.systemImage)
                        .commandlyFont(size: 12, weight: .semibold)
                        .foregroundStyle(BrandPalette.accentSoft)
                        .frame(width: 29, height: 29)
                        .background(BrandPalette.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Text("\(summary.activePlanCount)")
                        .commandlyFont(size: 9, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
                Text(summary.category.title)
                    .commandlyFont(size: 10.5, weight: .semibold)
                    .lineLimit(1)
                Text(viewModel.formattedCurrency(summary.monthlyAmount) + " / month")
                    .commandlyFont(size: 9)
                    .foregroundStyle(
                        summary.monthlyAmount > 0
                            ? Color.secondary
                            : Color.secondary.opacity(0.65)
                    )
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(LauncherPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(summary.category.title), \(summary.activePlanCount) active plans, \(viewModel.formattedCurrency(summary.monthlyAmount)) monthly"
        )
    }
}

struct FinanceBudgetsView: View {
    @Bindable var viewModel: FinanceViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Subscription budgets")
                        .commandlyFont(size: 14, weight: .semibold)
                    Text("Set monthly limits against recurring plan commitments. Transaction budgets will build on this local ledger later.")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                }

                ForEach(FinanceCategory.allCases) { category in
                    budgetRow(category)
                }
            }
            .padding(density.spacing(.md))
        }
    }

    private func budgetRow(_ category: FinanceCategory) -> some View {
        let spend = viewModel.monthlySpend(for: category)
        let budget = viewModel.budget(for: category)
        let ratio = progress(spend: spend, budget: budget)
        return Button {
            viewModel.beginBudget(for: category)
        } label: {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: category.systemImage)
                    .commandlyFont(size: 11, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .frame(width: 30, height: 30)
                    .background(BrandPalette.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(category.title)
                            .commandlyFont(size: 10.5, weight: .semibold)
                        Spacer()
                        Text(budgetText(spend: spend, budget: budget))
                            .commandlyFont(size: 9, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(ratio > 1 ? Color.orange : BrandPalette.accent)
                                    .frame(width: proxy.size.width * min(ratio, 1))
                            }
                    }
                    .frame(height: 5)
                }
                Image(systemName: "chevron.right")
                    .commandlyFont(size: 8, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(LauncherPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title), \(budgetText(spend: spend, budget: budget))")
        .accessibilityHint("Edits the monthly budget")
    }

    private func budgetText(spend: Decimal, budget: Decimal?) -> String {
        guard let budget else {
            return "\(viewModel.formattedCurrency(spend)) · Set limit"
        }
        return "\(viewModel.formattedCurrency(spend)) of \(viewModel.formattedCurrency(budget))"
    }

    private func progress(spend: Decimal, budget: Decimal?) -> Double {
        guard let budget, budget > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: spend / budget).doubleValue
        return max(value, 0)
    }
}
