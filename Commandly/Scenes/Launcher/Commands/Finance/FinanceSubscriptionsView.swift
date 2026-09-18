import DesignSystem
import SwiftUI

struct FinanceSubscriptionsView: View {
    @Bindable var viewModel: FinanceViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: 0) {
            subscriptionList
                .frame(width: 270)
                .background(LauncherPalette.sidebar.opacity(0.48))

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var subscriptionList: some View {
        VStack(spacing: 0) {
            Picker("Plan status", selection: $viewModel.subscriptionFilter) {
                ForEach(FinanceSubscriptionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(density.spacing(.xs))
            .accessibilityLabel("Subscription status filter")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: density.spacing(.xxs)) {
                        if viewModel.subscriptions.isEmpty {
                            Text(viewModel.query.isEmpty ? "No plans here yet." : "No matching plans.")
                                .commandlyFont(size: 10)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            ForEach(viewModel.subscriptions) { subscription in
                                row(subscription)
                                    .id(subscription.id)
                            }
                        }
                    }
                    .padding(.horizontal, density.spacing(.xs))
                    .padding(.bottom, density.spacing(.xs))
                }
                .onChange(of: viewModel.selectedSubscriptionID) { _, selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ subscription: FinanceSubscription) -> some View {
        LauncherApplicationRow(
            isSelected: viewModel.selectedSubscription?.id == subscription.id,
            onSelect: { viewModel.select(subscription) },
            onOpen: { viewModel.beginEditing(subscription) },
            onContextAction: {
                viewModel.select(subscription)
                viewModel.showsActionsMenu = true
            },
            onHoverChange: { hovering in
                if hovering { viewModel.select(subscription) }
            }
        ) {
            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: subscription.category.systemImage)
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(subscription.isActive ? BrandPalette.accentSoft : Color.secondary)
                    .frame(width: 27, height: 27)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.name)
                        .commandlyFont(size: 10.5, weight: .semibold)
                        .lineLimit(1)
                    Text(renewalText(subscription))
                        .commandlyFont(size: 8.5)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
            }
        } accessory: {
            Text(viewModel.formattedCurrency(subscription.amount))
                .commandlyFont(size: 9, weight: .semibold)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let subscription = viewModel.selectedSubscription {
            FinanceSubscriptionDetail(viewModel: viewModel, subscription: subscription)
        } else {
            FinanceEmptyOverlay(
                systemImage: "rectangle.stack.badge.plus",
                title: "No subscription selected",
                message: "Add a plan or change the filter to review archived subscriptions.",
                actionTitle: "Add Subscription",
                action: viewModel.beginNewSubscription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func renewalText(_ subscription: FinanceSubscription) -> String {
        guard let date = viewModel.nextRenewal(for: subscription) else { return "Archived" }
        return "Renews \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct FinanceSubscriptionDetail: View {
    @Bindable var viewModel: FinanceViewModel
    let subscription: FinanceSubscription
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                HStack(alignment: .top, spacing: density.spacing(.sm)) {
                    Image(systemName: subscription.category.systemImage)
                        .commandlyFont(size: 18, weight: .semibold)
                        .foregroundStyle(BrandPalette.accentSoft)
                        .frame(width: 42, height: 42)
                        .background(BrandPalette.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.name)
                            .commandlyFont(size: 16, weight: .semibold)
                            .textSelection(.enabled)
                        Text(subscription.isActive ? "ACTIVE" : "ARCHIVED")
                            .commandlyFont(size: 8, weight: .bold)
                            .tracking(0.6)
                            .foregroundStyle(subscription.isActive ? Color.green : Color.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(viewModel.formattedCurrency(subscription.amount))
                        .commandlyFont(size: 18, weight: .semibold, design: .rounded)
                        .lineLimit(1)
                }

                HStack(spacing: density.spacing(.xs)) {
                    Button("Edit") { viewModel.beginEditing(subscription) }
                        .buttonStyle(.borderedProminent)
                    Button(subscription.isActive ? "Archive" : "Restore") {
                        viewModel.toggleArchive(subscription)
                    }
                    .buttonStyle(.bordered)
                    Button("Delete", role: .destructive) {
                        viewModel.requestDelete(subscription)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: density.spacing(.sm)) {
                    detailRow("Billing", "\(viewModel.formattedCurrency(subscription.amount)) / \(subscription.billingCycle.shortTitle)")
                    detailRow("Monthly value", viewModel.formattedCurrency(subscription.monthlyAmount))
                    detailRow("Category", subscription.category.title)
                    if let renewal = viewModel.nextRenewal(for: subscription) {
                        detailRow("Next renewal", renewal.formatted(date: .long, time: .omitted))
                    }
                }
                .padding(density.spacing(.sm))
                .background(LauncherPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                        .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }

                if subscription.notes.isEmpty == false {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NOTES")
                            .commandlyFont(size: 8, weight: .bold)
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                        Text(subscription.notes)
                            .commandlyFont(size: 10)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(density.spacing(.md))
        }
        .id(subscription.id)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .commandlyFont(size: 9.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .commandlyFont(size: 9.5, weight: .semibold)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
