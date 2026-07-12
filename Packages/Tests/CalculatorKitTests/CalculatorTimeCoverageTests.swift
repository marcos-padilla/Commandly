import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator time and scheduling coverage", .serialized)
struct CalculatorTimeCoverageTests {
    private let service = CalculatorService()

    private func context() -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return CalculatorEvaluationContext(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: .gmt, now: now)
    }

    private func result(_ expression: String) async throws -> CalculatorResult {
        let outcome = await service.evaluate(expression, context: context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected time success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected time success")
        }
        return result
    }

    private func decimal(_ expression: String) async throws -> Decimal {
        let result = try await result(expression)
        guard case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected decimal for \(expression)")
            throw CalculatorUserFacingError(message: "Expected decimal")
        }
        return value
    }

    private func clock(_ expression: String, zone identifier: String = "GMT") async throws -> String {
        let result = try await result(expression)
        guard case .timeZoneInstant(let value) = result.primaryValue,
              let zone = TimeZone(identifier: identifier) ?? (identifier == "GMT" ? TimeZone.gmt : nil) else {
            Issue.record("Expected instant for \(expression)")
            throw CalculatorUserFacingError(message: "Expected instant")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let values = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: value.instant)
        return String(format: "%04d-%02d-%02d %02d:%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0, values.hour ?? 0, values.minute ?? 0)
    }

    private func ymd(_ expression: String) async throws -> String {
        let result = try await result(expression)
        guard case .date(let date) = result.primaryValue else {
            Issue.record("Expected date for \(expression)")
            throw CalculatorUserFacingError(message: "Expected date")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    @Test("Basic and multi-unit clock arithmetic", arguments: [
        ("3 hours after 2pm", "2026-07-15 17:00"),
        ("2 hours before 10:30 AM", "2026-07-15 08:30"),
        ("5pm plus 90 minutes", "2026-07-15 18:30"),
        ("midnight plus 8 hours", "2026-07-15 08:00"),
        ("noon minus 45 minutes", "2026-07-15 11:15"),
        ("18:30 + 2:15", "2026-07-15 20:45"),
        ("2 hours 30 minutes after 5pm", "2026-07-15 19:30"),
        ("1 day 3 hours from now", "2026-07-16 15:00"),
        ("90 minutes before tomorrow at noon", "2026-07-16 10:30"),
    ])
    func clockMath(expression: String, expected: String) async throws {
        let actual = try await clock(expression)
        #expect(actual == expected, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Clock differences use explicit next-day behavior")
    func differences() async throws {
        #expect(try await decimal("time between 9am and 5pm") == 28_800)
        #expect(try await decimal("hours between 8:30 and 17:15") == 31_500)
        #expect(try await decimal("difference between 11pm and 2am") == 10_800)
        #expect(try await decimal("how long from 10:45 AM to 3:20 PM") == 16_500)
        let result = try await result("difference between 11pm and 2am")
        #expect(result.metadata.notes.contains { $0.contains("next day") })
    }

    @Test("Duration and clock formatting")
    func formatting() async throws {
        #expect(try await result("150 minutes as hours and minutes").formattedPrimaryValue == "2 h 30 min")
        #expect(try await decimal("9000 seconds as hours") == Decimal(string: "2.5"))
        #expect(try await result("2.5 hours in hours and minutes").formattedPrimaryValue == "2 h 30 min")
        #expect(try await decimal("01:30:00 in seconds") == 5_400)
        #expect(try await result("5pm in 24-hour time").formattedPrimaryValue == "17:00")
        #expect(try await result("17:30 in 12-hour time").formattedPrimaryValue == "5:30 PM")
        #expect(try await result("midnight in military time").formattedPrimaryValue == "00:00")
        #expect(try await result("noon in 24-hour format").formattedPrimaryValue == "12:00")
    }

    @Test("Current time and IANA-backed zone conversion")
    func zones() async throws {
        #expect(try await clock("current time") == "2026-07-15 12:00")
        #expect(try await clock("time now") == "2026-07-15 12:00")
        #expect(try await clock("what time is it") == "2026-07-15 12:00")
        #expect(try await clock("current time in Tokyo", zone: "Asia/Tokyo") == "2026-07-15 21:00")
        #expect(try await clock("time in London", zone: "Europe/London") == "2026-07-15 13:00")
        #expect(try await clock("local time in Miami", zone: "America/New_York") == "2026-07-15 08:00")
        #expect(try await clock("5pm New York in Tokyo", zone: "Asia/Tokyo") == "2026-07-16 06:00")
        #expect(try await clock("9:30 AM Miami to London", zone: "Europe/London") == "2026-07-15 14:30")
        #expect(try await clock("18:00 UTC in Sydney", zone: "Australia/Sydney") == "2026-07-16 04:00")
        #expect(try await clock("7pm Los Angeles time in Madrid", zone: "Europe/Madrid") == "2026-07-16 04:00")
        #expect(try await clock("11pm New York in Tokyo", zone: "Asia/Tokyo") == "2026-07-16 12:00")
        #expect(try await clock("1am Tokyo in Los Angeles", zone: "America/Los_Angeles") == "2026-07-14 09:00")
        #expect(try await clock("Friday at 10pm Miami in London", zone: "Europe/London") == "2026-07-18 03:00")
        #expect(try await clock("July 15 at 5pm New York in Paris", zone: "Europe/Paris") == "2026-07-15 23:00")
        #expect(try await clock("5pm New York in London on March 10, 2026", zone: "Europe/London") == "2026-03-10 21:00")
    }

    @Test("Time-zone offsets are date-aware")
    func zoneDifferences() async throws {
        #expect(try await decimal("time difference between Miami and London") == 5)
        #expect(try await decimal("how many hours ahead is Tokyo from New York") == 13)
        #expect(try await decimal("UTC offset for Madrid") == 2)
        #expect(try await decimal("time difference between Miami and Madrid on November 1") == 6)
        #expect(try await clock("5pm UTC+3 in UTC-5", zone: "GMT-0500") == "2026-07-15 09:00")
        #expect(try await clock("18:00 GMT+2 to UTC", zone: "GMT") == "2026-07-15 16:00")
        #expect(try await clock("time in UTC+5:45", zone: "GMT+0545") == "2026-07-15 17:45")
        #expect(try await clock("time in UTC+9", zone: "GMT+0900") == "2026-07-15 21:00")
        #expect(try await clock("UTC+5:30", zone: "GMT+0530") == "2026-07-15 17:30")
        #expect(try await clock("UTC+5:45", zone: "GMT+0545") == "2026-07-15 17:45")
        #expect(try await clock("UTC-3:30", zone: "GMT-0330") == "2026-07-15 08:30")
    }

    @Test("Timestamps and ISO date-times")
    func timestamps() async throws {
        #expect(try await decimal("unix time now") == 1_784_116_800)
        #expect(try await decimal("timestamp for July 15, 2026 at noon") == 1_784_116_800)
        #expect(try await clock("1784073600 as local time") == "2026-07-15 00:00")
        #expect(try await clock("1784073600000 milliseconds as date") == "2026-07-15 00:00")
        #expect(try await decimal("July 15, 2026 as epoch") == 1_784_073_600)
        #expect(try await clock("2026-07-15T14:30:00Z in local time") == "2026-07-15 14:30")
        #expect(try await clock("2026-07-15T14:30:00-04:00 in UTC") == "2026-07-15 18:30")
    }

    @Test("Scheduling arithmetic")
    func schedules() async throws {
        #expect(try await decimal("meeting from 9:30 to 11") == 5_400)
        #expect(try await decimal("duration from 2pm to 3:45pm") == 6_300)
        #expect(try await decimal("split 8 hours into 30-minute blocks") == 16)
        #expect(try await decimal("how many 45-minute meetings fit between 9 and 5") == 10)
        #expect(try await clock("8-hour shift starting at 9 with a 30-minute break") == "2026-07-15 17:30")
        #expect(try await clock("end time for a 7.5-hour workday starting at 8:30") == "2026-07-15 16:00")
    }

    @Test("Recurrence and cron")
    func recurrenceAndCron() async throws {
        #expect(try await ymd("every 15 days starting July 2") == "2026-07-17")
        #expect(try await ymd("next date in a biweekly schedule starting July 2") == "2026-07-16")
        #expect(try await ymd("10 occurrences every 2 weeks from January 1") == "2026-05-07")
        #expect(try await result("0 9 * * 1-5").formattedPrimaryValue == "At 09:00 Monday through Friday")
        #expect(try await result("what does 0 0 * * * mean").formattedPrimaryValue == "At 00:00 every day")
        #expect(try await clock("next run for 0 9 * * MON") == "2026-07-20 09:00")
    }

    @Test("Ambiguous zones and astronomy without location fail")
    func safeFailures() async {
        for expression in ["noon PST in EST", "difference between PST and CET", "9am EST in CET on July 1", "sunrise today", "sunset in Miami", "daylight duration today", "golden hour tomorrow"] {
            let outcome = await service.evaluate(expression, context: context())
            guard case .failure = outcome else {
                Issue.record("Expected safe failure for \(expression), got \(outcome)")
                continue
            }
        }
    }
}
