import Foundation

@MainActor
struct FinanceApplicationServices {
    let persistence: any FinancePersisting
    let now: () -> Date
    let makeID: () -> UUID
    let calendar: Calendar

    init(
        persistence: any FinancePersisting,
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> UUID = { UUID() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.persistence = persistence
        self.now = now
        self.makeID = makeID
        self.calendar = calendar
    }

    static var live: FinanceApplicationServices {
        FinanceApplicationServices(persistence: JSONFinanceStore())
    }

    static var inMemory: FinanceApplicationServices {
        FinanceApplicationServices(persistence: InMemoryFinanceStore())
    }
}
