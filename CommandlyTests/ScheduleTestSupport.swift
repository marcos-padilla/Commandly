import Foundation
import Infrastructure
import SecurityKit
@testable import Commandly

@MainActor
final class ScheduleTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

actor RecordingScheduleReader: ScheduleReading {
    var events: [ScheduleEvent]
    var failure: ScheduleError?
    private(set) var requests: [ScheduleQuery] = []
    init(events: [ScheduleEvent] = []) { self.events = events }
    func replace(_ events: [ScheduleEvent]) { self.events = events }
    func setFailure(_ error: ScheduleError?) { failure = error }
    func snapshot(for query: ScheduleQuery) async throws -> ScheduleSnapshot {
        requests.append(query)
        if let failure { throw failure }
        try Task.checkCancellation()
        return ScheduleSnapshot(events: events.filter { $0.endDate > query.startDate && $0.startDate < query.endDate })
    }
}

actor RecordingScheduleOpener: URLOpening {
    private(set) var urls: [URL] = []
    func openURL(_ url: URL) async throws { urls.append(url) }
}

actor RecordingSchedulePermissions: PermissionServicing {
    var value: PermissionState
    private(set) var requestCount = 0
    init(_ value: PermissionState = .notDetermined) { self.value = value }
    func state(for kind: PermissionKind) async -> PermissionState { value }
    func request(_ kind: PermissionKind) async -> PermissionState {
        requestCount += 1
        value = .authorized
        return value
    }
    func set(_ value: PermissionState) { self.value = value }
}

actor RecordingSchedulePrivacyOpener: PrivacySettingsOpening {
    private(set) var panes: [PrivacySettingsPane] = []
    func open(_ pane: PrivacySettingsPane) async { panes.append(pane) }
}

@MainActor
struct ScheduleTestFixture {
    let clock: ScheduleTestClock
    let reader: RecordingScheduleReader
    let opener: RecordingScheduleOpener
    let permissions: RecordingSchedulePermissions
    let privacy: RecordingSchedulePrivacyOpener
    let scheduler: InMemoryScheduleDeadlineScheduler
    let autoMonitor: InMemoryScheduleChangeMonitor
    let viewMonitor: InMemoryScheduleChangeMonitor
    let coordinator: ScheduleAutoJoinCoordinator

    init(access: PermissionState = .authorized) {
        let clock = ScheduleTestClock()
        let reader = RecordingScheduleReader()
        let opener = RecordingScheduleOpener()
        let scheduler = InMemoryScheduleDeadlineScheduler()
        let autoMonitor = InMemoryScheduleChangeMonitor()
        self.clock = clock
        self.reader = reader
        self.opener = opener
        self.permissions = RecordingSchedulePermissions(access)
        self.privacy = RecordingSchedulePrivacyOpener()
        self.scheduler = scheduler
        self.autoMonitor = autoMonitor
        self.viewMonitor = InMemoryScheduleChangeMonitor()
        self.coordinator = ScheduleAutoJoinCoordinator(reader: reader, opener: opener,
            now: { clock.date }, scheduler: scheduler, monitor: autoMonitor)
    }

    var services: ScheduleApplicationServices {
        ScheduleApplicationServices(reader: reader, permissions: permissions, privacySettings: privacy,
            autoJoin: coordinator, now: { clock.date }, makeChangeMonitor: { viewMonitor })
    }

    func event(
        itemID: String = "event", offset: TimeInterval = 120,
        title: String = "Team Meeting", calendarID: String = "work", calendarTitle: String = "Work",
        cancelled: Bool = false, declined: Bool = false, allDay: Bool = false,
        link: ScheduleMeetingLink
    ) -> ScheduleEvent {
        let start = clock.date.addingTimeInterval(offset)
        return ScheduleEvent(id: .init(calendarID: calendarID, itemID: itemID, occurrenceDate: start),
            title: title, calendarTitle: calendarTitle, startDate: start, endDate: start.addingTimeInterval(1_800),
            isAllDay: allDay, isCancelled: cancelled, isDeclined: declined, meetingLinks: [link])
    }
}
