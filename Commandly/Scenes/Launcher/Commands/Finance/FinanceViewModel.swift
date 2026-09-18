import CommandKit
import Foundation
import Observation

enum FinanceActionID {
    static let newSubscription = CommandActionID(rawValue: "finance.new-subscription")
    static let editSelected = CommandActionID(rawValue: "finance.edit-selected")
    static let archiveSelected = CommandActionID(rawValue: "finance.archive-selected")
    static let restoreSelected = CommandActionID(rawValue: "finance.restore-selected")
    static let deleteSelected = CommandActionID(rawValue: "finance.delete-selected")
}

enum FinanceSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case subscriptions
    case calendar
    case categories
    case budgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .subscriptions: return "Subscriptions"
        case .calendar: return "Calendar"
        case .categories: return "Categories"
        case .budgets: return "Budgets"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .subscriptions: return "rectangle.stack"
        case .calendar: return "calendar"
        case .categories: return "square.grid.2x2"
        case .budgets: return "gauge.with.dots.needle.50percent"
        }
    }
}

enum FinanceSubscriptionFilter: String, CaseIterable, Identifiable, Sendable {
    case active
    case all
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .all: return "All Plans"
        case .archived: return "Archived"
        }
    }

    func matches(_ subscription: FinanceSubscription) -> Bool {
        switch self {
        case .active: return subscription.isActive
        case .all: return true
        case .archived: return subscription.isActive == false
        }
    }
}

struct FinanceSubscriptionDraft: Equatable, Identifiable, Sendable {
    let subscriptionID: UUID?
    var name: String
    var amountText: String
    var billingCycle: SubscriptionBillingCycle
    var category: FinanceCategory
    var nextBillingDate: Date
    var notes: String
    var isActive: Bool

    var id: String { subscriptionID?.uuidString ?? "new-subscription" }

    static func empty(relativeTo date: Date, calendar: Calendar) -> FinanceSubscriptionDraft {
        FinanceSubscriptionDraft(
            subscriptionID: nil,
            name: "",
            amountText: "",
            billingCycle: .monthly,
            category: .productivity,
            nextBillingDate: calendar.startOfDay(for: date),
            notes: "",
            isActive: true
        )
    }

    init(
        subscriptionID: UUID?,
        name: String,
        amountText: String,
        billingCycle: SubscriptionBillingCycle,
        category: FinanceCategory,
        nextBillingDate: Date,
        notes: String,
        isActive: Bool
    ) {
        self.subscriptionID = subscriptionID
        self.name = name
        self.amountText = amountText
        self.billingCycle = billingCycle
        self.category = category
        self.nextBillingDate = nextBillingDate
        self.notes = notes
        self.isActive = isActive
    }

    init(subscription: FinanceSubscription) {
        self.init(
            subscriptionID: subscription.id,
            name: subscription.name,
            amountText: NSDecimalNumber(decimal: subscription.amount).stringValue,
            billingCycle: subscription.billingCycle,
            category: subscription.category,
            nextBillingDate: subscription.nextBillingDate,
            notes: subscription.notes,
            isActive: subscription.isActive
        )
    }

    func validatedAmount(locale: Locale = .current) throws -> Decimal {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed, locale: locale), value > 0 else {
            throw FinanceValidationError.invalidAmount
        }
        return value
    }
}

struct FinanceBudgetDraft: Equatable, Identifiable, Sendable {
    let category: FinanceCategory
    var amountText: String

    var id: FinanceCategory { category }

    func validatedAmount(locale: Locale = .current) throws -> Decimal {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed, locale: locale), value > 0 else {
            throw FinanceValidationError.invalidBudget
        }
        return value
    }
}

enum FinancePresentation: Identifiable, Sendable {
    case subscription(FinanceSubscriptionDraft)
    case budget(FinanceBudgetDraft)

    var id: String {
        switch self {
        case .subscription(let draft): return "subscription-\(draft.id)"
        case .budget(let draft): return "budget-\(draft.category.rawValue)"
        }
    }
}

@Observable
@MainActor
final class FinanceViewModel: LauncherApplicationModel {
    private let services: FinanceApplicationServices
    private let onGoBack: () -> Void
    private var loadTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    private var hasLoaded = false

    let currencyCode: String
    private(set) var ledger: FinanceLedger = .empty
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var statusMessage: String?
    var section: FinanceSection = .dashboard
    var query = "" {
        didSet { refreshSelection() }
    }
    var subscriptionFilter: FinanceSubscriptionFilter = .active {
        didSet { refreshSelection() }
    }
    var selectedSubscriptionID: UUID?
    var displayedMonth: Date
    var presentation: FinancePresentation?
    var pendingDeletion: FinanceSubscription?
    var showsActionsMenu = false

    init(
        services: FinanceApplicationServices,
        currencyCode: String,
        onGoBack: @escaping () -> Void
    ) {
        self.services = services
        self.currencyCode = currencyCode
        self.onGoBack = onGoBack
        self.displayedMonth = services.calendar.dateInterval(
            of: .month,
            for: services.now()
        )?.start ?? services.now()
    }

    var dashboard: FinanceDashboardSnapshot {
        FinanceRecurrence.dashboard(
            ledger: ledger,
            relativeTo: services.now(),
            calendar: services.calendar
        )
    }

    var subscriptions: [FinanceSubscription] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ledger.subscriptions
            .filter(subscriptionFilter.matches)
            .filter { subscription in
                needle.isEmpty
                    || subscription.name.lowercased().contains(needle)
                    || subscription.category.title.lowercased().contains(needle)
                    || subscription.notes.lowercased().contains(needle)
            }
            .sorted { left, right in
                let leftDate = nextRenewal(for: left) ?? .distantFuture
                let rightDate = nextRenewal(for: right) ?? .distantFuture
                if leftDate != rightDate { return leftDate < rightDate }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    var selectedSubscription: FinanceSubscription? {
        subscriptions.first { $0.id == selectedSubscriptionID } ?? subscriptions.first
    }

    var categorySummaries: [FinanceCategorySummary] {
        let active = ledger.subscriptions.filter(\.isActive)
        return FinanceCategory.allCases.map { category in
            let matches = active.filter { $0.category == category }
            return FinanceCategorySummary(
                category: category,
                monthlyAmount: matches.reduce(Decimal.zero) { $0 + $1.monthlyAmount },
                activePlanCount: matches.count
            )
        }
    }

    var footerActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(
                id: FinanceActionID.newSubscription,
                title: "New Subscription",
                isPrimary: true,
                keyHint: .return
            )
        ]
        if selectedSubscription != nil, section == .subscriptions {
            actions.append(
                CommandActionDescriptor(
                    id: FinanceActionID.editSelected,
                    title: "Edit"
                )
            )
        }
        actions.append(
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        )
        return actions
    }

    var menuActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(
                id: FinanceActionID.newSubscription,
                title: "New Subscription",
                isPrimary: true,
                keyHint: .return
            )
        ]
        if let selectedSubscription {
            actions.append(
                CommandActionDescriptor(
                    id: FinanceActionID.editSelected,
                    title: "Edit \(selectedSubscription.name)"
                )
            )
            actions.append(
                CommandActionDescriptor(
                    id: selectedSubscription.isActive
                        ? FinanceActionID.archiveSelected
                        : FinanceActionID.restoreSelected,
                    title: selectedSubscription.isActive ? "Archive Plan" : "Restore Plan"
                )
            )
            actions.append(
                CommandActionDescriptor(
                    id: FinanceActionID.deleteSelected,
                    title: "Delete Plan"
                )
            )
        }
        return actions
    }

    func load() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        do {
            ledger = try await services.persistence.loadLedger()
            refreshSelection()
            statusMessage = nil
        } catch is CancellationError {
            return
        } catch {
            statusMessage = "Finance data could not be loaded."
        }
    }

    func beginNewSubscription() {
        presentation = .subscription(
            .empty(relativeTo: services.now(), calendar: services.calendar)
        )
    }

    func beginEditing(_ subscription: FinanceSubscription) {
        selectedSubscriptionID = subscription.id
        presentation = .subscription(FinanceSubscriptionDraft(subscription: subscription))
    }

    func beginEditingSelected() {
        guard let selectedSubscription else { return }
        beginEditing(selectedSubscription)
    }

    func beginBudget(for category: FinanceCategory) {
        let current = budget(for: category)
        presentation = .budget(
            FinanceBudgetDraft(
                category: category,
                amountText: current.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            )
        )
    }

    @discardableResult
    func saveSubscription(_ draft: FinanceSubscriptionDraft) async -> Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            statusMessage = FinanceValidationError.missingName.message
            return false
        }
        let amount: Decimal
        do {
            amount = try draft.validatedAmount()
        } catch let error as FinanceValidationError {
            statusMessage = error.message
            return false
        } catch {
            statusMessage = FinanceValidationError.invalidAmount.message
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let now = services.now()
        var candidate = ledger
        let savedID: UUID
        if let subscriptionID = draft.subscriptionID,
           let index = candidate.subscriptions.firstIndex(where: { $0.id == subscriptionID }) {
            savedID = subscriptionID
            candidate.subscriptions[index].name = name
            candidate.subscriptions[index].amount = amount
            candidate.subscriptions[index].billingCycle = draft.billingCycle
            candidate.subscriptions[index].category = draft.category
            candidate.subscriptions[index].nextBillingDate = draft.nextBillingDate
            candidate.subscriptions[index].notes = draft.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            candidate.subscriptions[index].isActive = draft.isActive
            candidate.subscriptions[index].updatedAt = now
        } else {
            savedID = services.makeID()
            candidate.subscriptions.append(
                FinanceSubscription(
                    id: savedID,
                    name: name,
                    amount: amount,
                    billingCycle: draft.billingCycle,
                    category: draft.category,
                    nextBillingDate: draft.nextBillingDate,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    isActive: draft.isActive,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        do {
            try await services.persistence.saveLedger(candidate)
            ledger = candidate
            selectedSubscriptionID = savedID
            subscriptionFilter = draft.isActive ? .active : .all
            section = .subscriptions
            statusMessage = draft.subscriptionID == nil
                ? "Subscription added."
                : "Subscription updated."
            return true
        } catch is CancellationError {
            return false
        } catch {
            statusMessage = "The subscription could not be saved."
            return false
        }
    }

    @discardableResult
    func saveBudget(_ draft: FinanceBudgetDraft) async -> Bool {
        let amount: Decimal
        do {
            amount = try draft.validatedAmount()
        } catch let error as FinanceValidationError {
            statusMessage = error.message
            return false
        } catch {
            statusMessage = FinanceValidationError.invalidBudget.message
            return false
        }
        isSaving = true
        defer { isSaving = false }
        var candidate = ledger
        if let index = candidate.budgets.firstIndex(where: { $0.category == draft.category }) {
            candidate.budgets[index].monthlyLimit = amount
        } else {
            candidate.budgets.append(
                FinanceCategoryBudget(category: draft.category, monthlyLimit: amount)
            )
        }
        do {
            try await services.persistence.saveLedger(candidate)
            ledger = candidate
            statusMessage = "Monthly budget updated."
            return true
        } catch is CancellationError {
            return false
        } catch {
            statusMessage = "The budget could not be saved."
            return false
        }
    }

    func requestDelete(_ subscription: FinanceSubscription) {
        selectedSubscriptionID = subscription.id
        pendingDeletion = subscription
    }

    func confirmDeletion() {
        guard let subscription = pendingDeletion else { return }
        pendingDeletion = nil
        mutateLedger(successMessage: "Subscription deleted.") { ledger in
            ledger.subscriptions.removeAll { $0.id == subscription.id }
        }
    }

    func toggleArchive(_ subscription: FinanceSubscription) {
        selectedSubscriptionID = subscription.id
        mutateLedger(
            successMessage: subscription.isActive
                ? "Subscription archived."
                : "Subscription restored."
        ) { ledger in
            guard let index = ledger.subscriptions.firstIndex(where: { $0.id == subscription.id })
            else { return }
            ledger.subscriptions[index].isActive.toggle()
            ledger.subscriptions[index].updatedAt = self.services.now()
        }
    }

    func select(_ subscription: FinanceSubscription) {
        selectedSubscriptionID = subscription.id
    }

    func selectSection(_ section: FinanceSection) {
        self.section = section
    }

    func moveMonth(offset: Int) {
        guard let next = services.calendar.date(
            byAdding: .month,
            value: offset,
            to: displayedMonth
        ) else { return }
        displayedMonth = next
    }

    func resetMonth() {
        displayedMonth = services.calendar.dateInterval(
            of: .month,
            for: services.now()
        )?.start ?? services.now()
    }

    func renewals(on date: Date) -> [FinanceSubscription] {
        let start = services.calendar.startOfDay(for: date)
        let end = services.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        return ledger.subscriptions.filter { subscription in
            FinanceRecurrence.occurrences(
                for: subscription,
                in: interval,
                calendar: services.calendar
            ).isEmpty == false
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func nextRenewal(for subscription: FinanceSubscription) -> Date? {
        FinanceRecurrence.nextRenewal(
            for: subscription,
            relativeTo: services.now(),
            calendar: services.calendar
        )
    }

    func budget(for category: FinanceCategory) -> Decimal? {
        ledger.budgets.first { $0.category == category }?.monthlyLimit
    }

    func monthlySpend(for category: FinanceCategory) -> Decimal {
        categorySummaries.first { $0.category == category }?.monthlyAmount ?? 0
    }

    func formattedCurrency(_ value: Decimal) -> String {
        Double(truncating: NSDecimalNumber(decimal: value)).formatted(
            .currency(code: currencyCode)
        )
    }

    func goBack() {
        onGoBack()
    }

    func moveSelection(offset: Int) {
        guard section == .subscriptions else { return }
        selectedSubscriptionID = LauncherListSelection.nextID(
            in: subscriptions,
            selectedID: selectedSubscriptionID,
            offset: offset,
            id: \.id
        )
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case FinanceActionID.newSubscription:
            beginNewSubscription()
        case FinanceActionID.editSelected:
            beginEditingSelected()
        case FinanceActionID.archiveSelected, FinanceActionID.restoreSelected:
            if let selectedSubscription { toggleArchive(selectedSubscription) }
        case FinanceActionID.deleteSelected:
            if let selectedSubscription { requestDelete(selectedSubscription) }
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        default:
            break
        }
    }

    func handleEscape() -> Bool {
        if query.isEmpty == false {
            query = ""
            return true
        }
        if section != .dashboard {
            section = .dashboard
            return true
        }
        return false
    }

    func stop() {
        loadTask?.cancel()
        mutationTask?.cancel()
    }

    func startLoadingIfNeeded() {
        guard loadTask == nil, hasLoaded == false else { return }
        loadTask = Task { [weak self] in
            await self?.load()
        }
    }

    func flushPersistenceForTesting() async {
        await mutationTask?.value
    }

    private func refreshSelection() {
        selectedSubscriptionID = LauncherListSelection.resolvedID(
            in: subscriptions,
            selectedID: selectedSubscriptionID,
            id: \.id
        )
    }

    private func mutateLedger(
        successMessage: String,
        mutation: @escaping @MainActor (inout FinanceLedger) -> Void
    ) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            var candidate = ledger
            mutation(&candidate)
            isSaving = true
            defer { isSaving = false }
            do {
                try await services.persistence.saveLedger(candidate)
                try Task.checkCancellation()
                ledger = candidate
                refreshSelection()
                statusMessage = successMessage
            } catch is CancellationError {
                return
            } catch {
                statusMessage = "The finance change could not be saved."
            }
        }
    }
}
