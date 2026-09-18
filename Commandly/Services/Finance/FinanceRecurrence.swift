import Foundation

/// Calendar-safe recurrence and aggregation helpers for finance views and tests.
nonisolated enum FinanceRecurrence {
    static func nextRenewal(
        for subscription: FinanceSubscription,
        relativeTo date: Date,
        calendar: Calendar
    ) -> Date? {
        guard subscription.isActive else { return nil }
        let target = calendar.startOfDay(for: date)
        let anchor = calendar.startOfDay(for: subscription.nextBillingDate)
        var candidate = anchor
        var iterationCount = 0
        while candidate < target, iterationCount < 10_000 {
            iterationCount += 1
            guard let next = subscription.billingCycle.date(
                after: anchor,
                occurrenceCount: iterationCount,
                calendar: calendar
            ),
                  next > candidate else {
                return nil
            }
            candidate = next
        }
        return candidate >= target ? candidate : nil
    }

    static func occurrences(
        for subscription: FinanceSubscription,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        guard subscription.isActive else { return [] }
        let anchor = calendar.startOfDay(for: subscription.nextBillingDate)
        var candidate = anchor
        var values: [Date] = []
        var iterationCount = 0
        while candidate < interval.start, iterationCount < 10_000 {
            iterationCount += 1
            guard let next = subscription.billingCycle.date(
                after: anchor,
                occurrenceCount: iterationCount,
                calendar: calendar
            ), next > candidate else {
                return []
            }
            candidate = next
        }
        while candidate < interval.end, iterationCount < 10_000 {
            if candidate >= interval.start {
                values.append(candidate)
            }
            iterationCount += 1
            guard let next = subscription.billingCycle.date(
                after: anchor,
                occurrenceCount: iterationCount,
                calendar: calendar
            ),
                  next > candidate else {
                break
            }
            candidate = next
        }
        return values
    }

    static func dashboard(
        ledger: FinanceLedger,
        relativeTo date: Date,
        calendar: Calendar
    ) -> FinanceDashboardSnapshot {
        let active = ledger.subscriptions.filter(\.isActive)
        let monthlySpend = active.reduce(Decimal.zero) { $0 + $1.monthlyAmount }
        let start = calendar.startOfDay(for: date)
        let soonEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let upcomingEnd = calendar.date(byAdding: .day, value: 30, to: start) ?? soonEnd
        let renewals = active.compactMap { subscription -> FinanceRenewal? in
            guard let renewalDate = nextRenewal(
                for: subscription,
                relativeTo: start,
                calendar: calendar
            ) else {
                return nil
            }
            return FinanceRenewal(subscription: subscription, date: renewalDate)
        }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.subscription.name.localizedCaseInsensitiveCompare($1.subscription.name)
                == .orderedAscending
        }
        let categorySummaries: [FinanceCategorySummary] = FinanceCategory.allCases.compactMap {
            category -> FinanceCategorySummary? in
            let matches = active.filter { $0.category == category }
            guard matches.isEmpty == false else { return nil }
            return FinanceCategorySummary(
                category: category,
                monthlyAmount: matches.reduce(Decimal.zero) { $0 + $1.monthlyAmount },
                activePlanCount: matches.count
            )
        }
        .sorted {
            if $0.monthlyAmount != $1.monthlyAmount {
                return $0.monthlyAmount > $1.monthlyAmount
            }
            return $0.category.title < $1.category.title
        }
        return FinanceDashboardSnapshot(
            monthlySpend: monthlySpend,
            yearlySpend: monthlySpend * 12,
            activePlanCount: active.count,
            renewingSoonCount: renewals.filter { $0.date < soonEnd }.count,
            categorySummaries: categorySummaries,
            upcomingRenewals: renewals.filter { $0.date < upcomingEnd }
        )
    }
}
