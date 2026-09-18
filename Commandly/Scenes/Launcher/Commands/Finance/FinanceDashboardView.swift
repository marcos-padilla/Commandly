import DesignSystem
import SwiftUI

struct FinanceDashboardView: View {
    @Bindable var viewModel: FinanceViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                metricGrid

                HStack(alignment: .top, spacing: density.spacing(.md)) {
                    categoryCard
                        .frame(maxWidth: .infinity)
                    renewalCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(density.spacing(.md))
        }
        .overlay {
            if viewModel.ledger.subscriptions.isEmpty {
                FinanceEmptyOverlay(
                    systemImage: "creditcard.and.123",
                    title: "Your finances, one command away",
                    message: "Add a subscription to see spending, renewals, categories, and budgets.",
                    actionTitle: "Add Subscription",
                    action: viewModel.beginNewSubscription
                )
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: density.spacing(.xs)), count: 4),
            spacing: density.spacing(.xs)
        ) {
            FinanceMetricCard(
                title: "Monthly",
                value: viewModel.formattedCurrency(viewModel.dashboard.monthlySpend),
                systemImage: "calendar.badge.clock",
                tint: .blue
            )
            FinanceMetricCard(
                title: "Yearly",
                value: viewModel.formattedCurrency(viewModel.dashboard.yearlySpend),
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .indigo
            )
            FinanceMetricCard(
                title: "Active Plans",
                value: "\(viewModel.dashboard.activePlanCount)",
                systemImage: "checkmark.circle",
                tint: .green
            )
            FinanceMetricCard(
                title: "Next 7 Days",
                value: "\(viewModel.dashboard.renewingSoonCount)",
                systemImage: "bell.badge",
                tint: .orange
            )
        }
    }

    private var categoryCard: some View {
        FinanceCard(title: "Spending by Category", systemImage: "chart.bar") {
            if viewModel.dashboard.categorySummaries.isEmpty {
                compactEmpty("No active category spending")
            } else {
                let maximum = viewModel.dashboard.categorySummaries
                    .map(\.monthlyAmount)
                    .max() ?? 1
                VStack(spacing: density.spacing(.xs)) {
                    ForEach(viewModel.dashboard.categorySummaries.prefix(5)) { summary in
                        FinanceCategoryBar(
                            summary: summary,
                            maximum: maximum,
                            valueText: viewModel.formattedCurrency(summary.monthlyAmount)
                        )
                    }
                }
            }
        }
    }

    private var renewalCard: some View {
        FinanceCard(title: "Upcoming Renewals", systemImage: "calendar.badge.exclamationmark") {
            if viewModel.dashboard.upcomingRenewals.isEmpty {
                compactEmpty("Nothing due in the next 30 days")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.dashboard.upcomingRenewals.prefix(5)) { renewal in
                        Button {
                            viewModel.selectSection(.subscriptions)
                            viewModel.select(renewal.subscription)
                        } label: {
                            HStack(spacing: density.spacing(.xs)) {
                                Image(systemName: renewal.subscription.category.systemImage)
                                    .commandlyFont(size: 10, weight: .semibold)
                                    .foregroundStyle(BrandPalette.accentSoft)
                                    .frame(width: 25, height: 25)
                                    .background(BrandPalette.accent.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(renewal.subscription.name)
                                        .commandlyFont(size: 10.5, weight: .semibold)
                                        .lineLimit(1)
                                    Text(renewal.date.formatted(.dateTime.month(.abbreviated).day()))
                                        .commandlyFont(size: 8.5)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 2)
                                Text(viewModel.formattedCurrency(renewal.subscription.amount))
                                    .commandlyFont(size: 9.5, weight: .semibold)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func compactEmpty(_ message: String) -> some View {
        Text(message)
            .commandlyFont(size: 9.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}

struct FinanceMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: CommandlyTint

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title.uppercased())
                    .commandlyFont(size: 8, weight: .bold)
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(tint.color)
            }
            Text(value)
                .commandlyFont(size: 16, weight: .semibold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
        .background(LauncherPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct FinanceCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .commandlyFont(size: 10.5, weight: .semibold)
            content
        }
        .padding(12)
        .background(LauncherPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
    }
}

struct FinanceCategoryBar: View {
    let summary: FinanceCategorySummary
    let maximum: Decimal
    let valueText: String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(summary.category.title, systemImage: summary.category.systemImage)
                    .commandlyFont(size: 9, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(valueText)
                    .commandlyFont(size: 9, weight: .semibold)
            }
            GeometryReader { proxy in
                let value = Double(truncating: NSDecimalNumber(decimal: summary.monthlyAmount))
                let maximumValue = max(
                    Double(truncating: NSDecimalNumber(decimal: maximum)),
                    0.01
                )
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(BrandPalette.accent)
                            .frame(width: proxy.size.width * min(max(value / maximumValue, 0), 1))
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.category.title), \(valueText) monthly")
    }
}

struct FinanceEmptyOverlay: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .commandlyFont(size: 29, weight: .medium)
                .foregroundStyle(BrandPalette.accentSoft)
            Text(title)
                .commandlyFont(size: 15, weight: .semibold)
            Text(message)
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
