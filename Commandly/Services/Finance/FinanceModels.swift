import Foundation

/// A broad spending category used by subscriptions and monthly budget targets.
nonisolated enum FinanceCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case entertainment
    case productivity
    case cloudStorage
    case aiTools
    case utilities
    case healthFitness
    case education
    case financialServices
    case news
    case shopping
    case travel
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entertainment: return "Entertainment"
        case .productivity: return "Productivity"
        case .cloudStorage: return "Cloud Storage"
        case .aiTools: return "AI Tools"
        case .utilities: return "Utilities"
        case .healthFitness: return "Health & Fitness"
        case .education: return "Education"
        case .financialServices: return "Financial Services"
        case .news: return "News"
        case .shopping: return "Shopping"
        case .travel: return "Travel"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .entertainment: return "play.tv"
        case .productivity: return "checkmark.circle"
        case .cloudStorage: return "externaldrive.badge.icloud"
        case .aiTools: return "sparkles"
        case .utilities: return "bolt"
        case .healthFitness: return "heart"
        case .education: return "graduationcap"
        case .financialServices: return "building.columns"
        case .news: return "newspaper"
        case .shopping: return "bag"
        case .travel: return "airplane"
        case .other: return "square.grid.2x2"
        }
    }
}

nonisolated enum SubscriptionBillingCycle: String, CaseIterable, Codable, Identifiable, Sendable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Every 3 Months"
        case .yearly: return "Yearly"
        }
    }

    var shortTitle: String {
        switch self {
        case .weekly: return "week"
        case .monthly: return "month"
        case .quarterly: return "3 months"
        case .yearly: return "year"
        }
    }

    func monthlyEquivalent(of amount: Decimal) -> Decimal {
        switch self {
        case .weekly: return amount * 52 / 12
        case .monthly: return amount
        case .quarterly: return amount / 3
        case .yearly: return amount / 12
        }
    }

    func date(after date: Date, occurrenceCount: Int = 1, calendar: Calendar) -> Date? {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * occurrenceCount, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: occurrenceCount, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3 * occurrenceCount, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: occurrenceCount, to: date)
        }
    }
}

/// A recurring commitment entered by the user. Amounts use Decimal to avoid binary rounding.
nonisolated struct FinanceSubscription: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var amount: Decimal
    var billingCycle: SubscriptionBillingCycle
    var category: FinanceCategory
    var nextBillingDate: Date
    var notes: String
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date

    var monthlyAmount: Decimal {
        billingCycle.monthlyEquivalent(of: amount)
    }

    var yearlyAmount: Decimal {
        monthlyAmount * 12
    }
}

nonisolated struct FinanceCategoryBudget: Codable, Equatable, Identifiable, Sendable {
    var category: FinanceCategory
    var monthlyLimit: Decimal

    var id: FinanceCategory { category }
}

/// Versioned finance payload persisted as one atomic local document.
nonisolated struct FinanceLedger: Codable, Equatable, Sendable {
    var subscriptions: [FinanceSubscription]
    var budgets: [FinanceCategoryBudget]

    static let empty = FinanceLedger(subscriptions: [], budgets: [])
}

nonisolated struct FinanceCategorySummary: Equatable, Identifiable, Sendable {
    let category: FinanceCategory
    let monthlyAmount: Decimal
    let activePlanCount: Int

    var id: FinanceCategory { category }
}

nonisolated struct FinanceRenewal: Equatable, Identifiable, Sendable {
    let subscription: FinanceSubscription
    let date: Date

    var id: UUID { subscription.id }
}

nonisolated struct FinanceDashboardSnapshot: Equatable, Sendable {
    let monthlySpend: Decimal
    let yearlySpend: Decimal
    let activePlanCount: Int
    let renewingSoonCount: Int
    let categorySummaries: [FinanceCategorySummary]
    let upcomingRenewals: [FinanceRenewal]
}

nonisolated enum FinanceValidationError: Error, Equatable, Sendable {
    case missingName
    case invalidAmount
    case invalidBudget

    var message: String {
        switch self {
        case .missingName: return "Add a subscription name before saving."
        case .invalidAmount: return "Enter an amount greater than zero."
        case .invalidBudget: return "Enter a monthly budget greater than zero."
        }
    }
}
