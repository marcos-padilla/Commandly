import Foundation
import Infrastructure
import Testing

struct ScheduleTests {
    @Test func queryBoundsDateRangeAndResultCount() {
        let start = Date(timeIntervalSince1970: 100)
        let query = ScheduleQuery(startDate: start, endDate: start.addingTimeInterval(90 * 86_400), limit: 10_000)
        #expect(query.endDate.timeIntervalSince(start) == 31 * 86_400)
        #expect(query.limit == 500)
        let reversed = ScheduleQuery(startDate: start, endDate: .distantPast, limit: -1)
        #expect(reversed.endDate == start)
        #expect(reversed.limit == 1)
    }

    @Test func fixtureReaderSortsFiltersAndReportsTruncation() async throws {
        let first = event(item: "first", start: 20, end: 40)
        let second = event(item: "second", start: 30, end: 60)
        let ended = event(item: "ended", start: 0, end: 10)
        let reader = InMemoryScheduleReader(events: [second, ended, first])
        let snapshot = try await reader.snapshot(for: ScheduleQuery(
            startDate: Date(timeIntervalSince1970: 15), endDate: Date(timeIntervalSince1970: 100), limit: 1
        ))
        #expect(snapshot.events == [first])
        #expect(snapshot.isTruncated)
    }

    @Test func occurrenceIdentitySeparatesCalendarsAndRecurringDates() {
        let first = ScheduleOccurrenceID(calendarID: "a", itemID: "series", occurrenceDate: .distantPast)
        let next = ScheduleOccurrenceID(calendarID: "a", itemID: "series", occurrenceDate: .distantFuture)
        let otherCalendar = ScheduleOccurrenceID(calendarID: "b", itemID: "series", occurrenceDate: .distantPast)
        #expect(Set([first, next, otherCalendar]).count == 3)
    }

    private func event(item: String, start: TimeInterval, end: TimeInterval) -> ScheduleEvent {
        let date = Date(timeIntervalSince1970: start)
        return ScheduleEvent(id: .init(calendarID: "calendar", itemID: item, occurrenceDate: date),
            title: item, calendarTitle: "Calendar", startDate: date, endDate: Date(timeIntervalSince1970: end))
    }
}
