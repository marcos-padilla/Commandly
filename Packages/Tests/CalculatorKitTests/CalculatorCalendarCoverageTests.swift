import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator calendar coverage", .serialized)
struct CalculatorCalendarCoverageTests {
    private let service = CalculatorService()

    private func context(
        holidays: Set<Date> = [],
        birthday: DateComponents? = nil
    ) -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return CalculatorEvaluationContext(
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: .gmt,
            now: now,
            weekendWeekdays: [1, 7],
            businessDayHolidays: holidays,
            birthdayMonthDay: birthday
        )
    }

    private func result(_ expression: String, context: CalculatorEvaluationContext? = nil) async throws -> CalculatorResult {
        let outcome = await service.evaluate(expression, context: context ?? self.context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected calendar success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected calendar success")
        }
        #expect(result.kind == .dateCalculation)
        return result
    }

    private func ymd(_ expression: String, context: CalculatorEvaluationContext? = nil) async throws -> String {
        let result = try await result(expression, context: context)
        guard case .date(let date) = result.primaryValue else {
            Issue.record("Expected date for \(expression)")
            throw CalculatorUserFacingError(message: "Expected date")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    private func decimal(_ expression: String, context: CalculatorEvaluationContext? = nil) async throws -> Decimal {
        let result = try await result(expression, context: context)
        guard case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected decimal for \(expression)")
            throw CalculatorUserFacingError(message: "Expected decimal")
        }
        return value
    }

    @Test("Current and relative calendar dates", arguments: [
        ("today", "2026-07-15"),
        ("tomorrow", "2026-07-16"),
        ("yesterday", "2026-07-14"),
        ("day after tomorrow", "2026-07-17"),
        ("day before yesterday", "2026-07-13"),
        ("today's date", "2026-07-15"),
        ("current date", "2026-07-15"),
        ("3 days from now", "2026-07-18"),
        ("3 days from today", "2026-07-18"),
        ("3 days after today", "2026-07-18"),
        ("3 days ago", "2026-07-12"),
        ("10 days before today", "2026-07-05"),
        ("tomorrow plus 5 days", "2026-07-21"),
        ("yesterday minus 2 days", "2026-07-12"),
        ("2 weeks from now", "2026-07-29"),
        ("3 weeks ago", "2026-06-24"),
        ("week after next", "2026-07-29"),
        ("next week", "2026-07-22"),
        ("last week", "2026-07-08"),
        ("2 weeks after Monday", "2026-08-03"),
        ("3 months from now", "2026-10-15"),
        ("2 months ago", "2026-05-15"),
        ("month after next", "2026-09-15"),
        ("next month", "2026-08-15"),
        ("last month", "2026-06-15"),
        ("6 months after July 15", "2027-01-15"),
        ("2 years from now", "2028-07-15"),
        ("5 years ago", "2021-07-15"),
        ("next year", "2027-07-15"),
        ("last year", "2025-07-15"),
        ("1 year 2 months 3 days from now", "2027-09-18"),
        ("2 weeks 4 days after July 1", "2026-07-19"),
        ("3 months and 10 days ago", "2026-04-05"),
    ])
    func relative(expression: String, expected: String) async throws {
        let actual = try await ymd(expression)
        #expect(actual == expected, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Specific arithmetic clamps month ends and leap days", arguments: [
        ("July 15 plus 30 days", "2026-08-14"),
        ("30 days after July 15", "2026-08-14"),
        ("90 days before December 25", "2026-09-26"),
        ("March 1, 2026 plus 6 months", "2026-09-01"),
        ("January 31 plus 1 month", "2026-02-28"),
        ("February 29, 2024 plus 1 year", "2025-02-28"),
        ("10 years after January 1, 2020", "2030-01-01"),
    ])
    func specificArithmetic(expression: String, expected: String) async throws {
        let actual = try await ymd(expression)
        #expect(actual == expected, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Weekdays and period boundaries", arguments: [
        ("next Monday", "2026-07-20"),
        ("last Friday", "2026-07-10"),
        ("this Wednesday", "2026-07-15"),
        ("Monday after next", "2026-07-27"),
        ("previous Tuesday", "2026-07-14"),
        ("third Friday of next month", "2026-08-21"),
        ("first Monday in September", "2026-09-07"),
        ("start of today", "2026-07-15"),
        ("end of today", "2026-07-15"),
        ("start of this week", "2026-07-12"),
        ("end of this week", "2026-07-18"),
        ("start of next month", "2026-08-01"),
        ("end of this month", "2026-07-31"),
        ("first day of next year", "2027-01-01"),
        ("last day of this quarter", "2026-09-30"),
    ])
    func navigation(expression: String, expected: String) async throws {
        let actual = try await ymd(expression)
        #expect(actual == expected, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Date differences and ordinal calendar values")
    func differences() async throws {
        #expect(try await decimal("days until December 25") == 163)
        #expect(try await decimal("days until Christmas") == 163)
        #expect(try await decimal("days until July 4, 2027") == 354)
        #expect(try await decimal("days since January 1") == 195)
        #expect(try await decimal("months since March 2020") == 76)
        #expect(try await decimal("days between January 1 and February 1") == 31)
        #expect(try await decimal("weeks between March 1 and June 1") == 13)
        #expect(try await decimal("months between July 15, 2025 and July 15, 2026") == 12)
        #expect(try await decimal("years since July 4, 1776") == 250)
        #expect(try await decimal("week number for July 15, 2026") == 29)
        #expect(try await decimal("day of year for March 10") == 69)
        #expect(try await ymd("what is the 100th day of 2026") == "2026-04-10")
        #expect(try await result("current quarter").formattedPrimaryValue == "Q3 2026")
        #expect(try await result("next quarter").formattedPrimaryValue == "Q4 2026")
        #expect(try await ymd("start of Q3 2026") == "2026-07-01")
        #expect(try await ymd("end of fourth quarter") == "2026-12-31")
        #expect(try await ymd("90 days after the start of Q1") == "2026-04-01")
    }

    @Test("Business calendar honors configured weekends and holidays")
    func businessCalendar() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let holiday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)) ?? Date(timeIntervalSince1970: 0)
        let configured = context(holidays: [holiday])
        #expect(try await ymd("5 business days from now", context: configured) == "2026-07-23")
        #expect(try await ymd("10 working days after July 1") == "2026-07-15")
        #expect(try await ymd("3 weekdays before December 25") == "2026-12-22")
        #expect(try await decimal("business days between July 1 and July 15") == 10)
        #expect(try await ymd("last business day of this month") == "2026-07-31")
    }

    @Test("Age, consented birthdays, and date formatting")
    func personalAndFormatting() async throws {
        #expect(try await decimal("age if born July 15, 2000") == 26)
        #expect(try await decimal("how old is someone born January 1, 1990") == 36)
        #expect(try await decimal("age on December 25, 2030 if born March 3, 2005") == 25)
        #expect(try await ymd("next birthday if born July 15") == "2027-07-15")
        let birthdayContext = context(birthday: DateComponents(month: 7, day: 20))
        #expect(try await decimal("days until my next birthday", context: birthdayContext) == 5)
        #expect(try await result("what day of the week is my birthday this year", context: birthdayContext).formattedPrimaryValue == "Monday")
        #expect(try await result("format July 15, 2026 as ISO").formattedPrimaryValue == "2026-07-15")
        #expect(try await result("2026-07-15 in US format").formattedPrimaryValue == "7/15/26")
        #expect(try await result("07/15/2026 in long format").formattedPrimaryValue == "July 15, 2026")
        #expect(try await decimal("July 15 2026 as unix timestamp") == 1_784_073_600)
        #expect(try await ymd("timestamp 1784073600 as date") == "2026-07-15")
        #expect(try await ymd("timestamp 1784073600000 milliseconds as date") == "2026-07-15")
    }

    @Test("Birthday context is never inferred")
    func birthdayRequiresConsent() async {
        for expression in ["days until my next birthday", "weeks until my birthday"] {
            let outcome = await service.evaluate(expression, context: context())
            guard case .failure = outcome else {
                Issue.record("Expected a failure without birthday context for \(expression), got \(outcome)")
                continue
            }
        }
    }

    @Test("Date-to-date elapsed time is explicit")
    func elapsedDateTime() async throws {
        #expect(try await decimal("time between December 31, 2025 and January 1, 2026") == 1)
        #expect(try await decimal("what week is December 1") == 49)
    }
}
