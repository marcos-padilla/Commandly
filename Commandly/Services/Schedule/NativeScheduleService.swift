import EventKit
import Foundation
import Infrastructure
import SecurityKit

/// Confines EventKit objects and synchronous database work to one actor away from the UI.
/// No access request is made here, and only value snapshots cross the actor boundary.
actor NativeScheduleService: ScheduleReading {
    private let permissions: any PermissionChecking
    private var eventStore: EKEventStore?

    init(permissions: any PermissionChecking) { self.permissions = permissions }

    func snapshot(for query: ScheduleQuery) async throws -> ScheduleSnapshot {
        guard await permissions.state(for: .calendar) == .authorized else {
            eventStore = nil
            throw ScheduleError.calendarAccessRequired
        }
        try Task.checkCancellation()
        guard query.endDate > query.startDate else { return ScheduleSnapshot(events: []) }
        let store = eventStore ?? EKEventStore()
        eventStore = store
        let predicate = store.predicateForEvents(
            withStart: query.startDate, end: query.endDate, calendars: nil
        )
        var captured: [ScheduleEvent] = []
        var isTruncated = false
        var mappingFailed = false
        var visited = 0
        // EventKit enumeration is synchronous and unordered. The bounded snapshot explicitly
        // reports truncation instead of claiming its first rows are every upcoming occurrence.
        store.enumerateEvents(matching: predicate) { event, stop in
            if Task.isCancelled { stop.pointee = true; return }
            visited += 1
            if visited > query.limit * 5 {
                isTruncated = true; stop.pointee = true; return
            }
            guard let start = event.startDate, let end = event.endDate,
                  let calendar = event.calendar, let eventID = event.eventIdentifier else { return }
            do {
                let links = try ScheduleMeetingLinkExtractor.links(
                    url: event.url, location: event.location, notes: event.notes
                )
                captured.append(ScheduleEvent(
                    id: ScheduleOccurrenceID(
                        calendarID: calendar.calendarIdentifier,
                        itemID: eventID,
                        occurrenceDate: event.occurrenceDate ?? start
                    ),
                    title: String((event.title ?? "Untitled Event").prefix(512)),
                    calendarTitle: String(calendar.title.prefix(120)),
                    startDate: start, endDate: end,
                    isAllDay: event.isAllDay,
                    isCancelled: event.status == .canceled,
                    isDeclined: event.attendees?.contains {
                        $0.isCurrentUser && $0.participantStatus == .declined
                    } ?? false,
                    location: event.location.map { String($0.prefix(1_024)) },
                    meetingLinks: links
                ))
                if captured.count > query.limit {
                    // Keep the earliest occurrences encountered rather than relying on EventKit's
                    // unspecified enumeration order. A hard scan bound still reports truncation.
                    let latestIndex = captured.indices.max {
                        let left = captured[$0]
                        let right = captured[$1]
                        return left.startDate == right.startDate
                            ? left.title < right.title : left.startDate < right.startDate
                    }
                    if let latestIndex { captured.remove(at: latestIndex) }
                    isTruncated = true
                }
            } catch {
                mappingFailed = true
                stop.pointee = true
            }
        }
        try Task.checkCancellation()
        guard mappingFailed == false else { throw ScheduleError.unavailable }
        guard await permissions.state(for: .calendar) == .authorized else {
            eventStore = nil
            throw ScheduleError.calendarAccessRequired
        }
        return ScheduleSnapshot(events: captured, isTruncated: isTruncated)
    }
}
