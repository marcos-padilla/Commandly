import DesignSystem
import SwiftUI

struct FinanceSubscriptionEditor: View {
    @Bindable var viewModel: FinanceViewModel
    @State private var draft: FinanceSubscriptionDraft
    @State private var validationMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: FinanceViewModel, initialDraft: FinanceSubscriptionDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.subscriptionID == nil ? "Add Subscription" : "Edit Subscription")
                        .commandlyFont(size: 16, weight: .semibold)
                    Text("Keep the next charge and billing cadence accurate.")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(18)

            Divider()

            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Cloud storage"))
                    .accessibilityLabel("Subscription name")

                HStack {
                    TextField("Amount", text: $draft.amountText, prompt: Text("0.00"))
                        .accessibilityLabel("Subscription amount")
                    Text(viewModel.currencyCode)
                        .foregroundStyle(.secondary)
                }

                Picker("Billing cycle", selection: $draft.billingCycle) {
                    ForEach(SubscriptionBillingCycle.allCases) { cycle in
                        Text(cycle.title).tag(cycle)
                    }
                }

                Picker("Category", selection: $draft.category) {
                    ForEach(FinanceCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }

                DatePicker(
                    "Next billing date",
                    selection: $draft.nextBillingDate,
                    displayedComponents: .date
                )

                Toggle("Active subscription", isOn: $draft.isActive)

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Subscription notes")
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let validationMessage {
                Text(validationMessage)
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error: \(validationMessage)")
            }

            Divider()

            HStack {
                Text("Stored locally on this Mac")
                    .commandlyFont(size: 9)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isSaving)
            }
            .padding(18)
        }
        .frame(width: 470, height: 500)
        .background(LauncherPalette.canvas)
    }

    private func save() {
        validationMessage = nil
        Task {
            if await viewModel.saveSubscription(draft) {
                dismiss()
            } else {
                validationMessage = viewModel.statusMessage
            }
        }
    }
}

struct FinanceBudgetEditor: View {
    @Bindable var viewModel: FinanceViewModel
    @State private var draft: FinanceBudgetDraft
    @State private var validationMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: FinanceViewModel, initialDraft: FinanceBudgetDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: draft.category.systemImage)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.category.title)
                        .commandlyFont(size: 15, weight: .semibold)
                    Text("Monthly subscription budget")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Monthly limit", text: $draft.amountText, prompt: Text("0.00"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Monthly budget limit")
                Text(viewModel.currencyCode)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Text(validationMessage)
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Budget") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.isSaving)
            }
        }
        .padding(20)
        .frame(width: 380, height: 220)
        .background(LauncherPalette.canvas)
    }

    private func save() {
        validationMessage = nil
        Task {
            if await viewModel.saveBudget(draft) {
                dismiss()
            } else {
                validationMessage = viewModel.statusMessage
            }
        }
    }
}
