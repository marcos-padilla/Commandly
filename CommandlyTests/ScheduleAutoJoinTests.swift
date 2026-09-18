import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct ScheduleAutoJoinTests {
    @Test func optInRevalidatesThenOpensExactlyOnceAtTheAbsoluteDeadline() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.scheduler.scheduledDate == nil)
        #expect(await fixture.reader.requests.isEmpty)
        #expect(fixture.coordinator.arm(event, link: link))
        await fixture.coordinator.waitForCheckForTesting()
        #expect(await fixture.opener.urls.isEmpty)
        #expect(fixture.scheduler.scheduledDate == fixture.clock.date.addingTimeInterval(30))

        fixture.clock.date = event.startDate
        fixture.scheduler.fire()
        await fixture.coordinator.waitForCheckForTesting()
        #expect(await fixture.opener.urls == [link.url])
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.scheduler.scheduledDate == nil)
        fixture.autoMonitor.notifyChange()
        fixture.coordinator.checkNow()
        fixture.scheduler.fire()
        await fixture.coordinator.waitForCheckForTesting()
        #expect(await fixture.opener.urls == [link.url])
    }

    @Test func cancellationAndLateWakeNeverOpenAnExpiredPlan() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        fixture.coordinator.arm(event, link: link)
        await fixture.coordinator.waitForCheckForTesting()
        fixture.coordinator.cancel()
        fixture.clock.date = event.startDate
        fixture.scheduler.fire()
        fixture.autoMonitor.notifyChange()
        #expect(await fixture.opener.urls.isEmpty)

        fixture.clock.date = event.startDate.addingTimeInterval(-10)
        fixture.coordinator.arm(event, link: link)
        await fixture.coordinator.waitForCheckForTesting()
        fixture.clock.date = event.startDate.addingTimeInterval(61)
        fixture.autoMonitor.notifyChange()
        await fixture.coordinator.waitForCheckForTesting()
        #expect(await fixture.opener.urls.isEmpty)
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.coordinator.statusMessage?.contains("start window passed") == true)
    }

    @Test func changedLinkOrTimeOrMissingOccurrenceStopsWithoutFollowingReplacement() async throws {
        let link = try meetingLink()
        let replacementLink = try meetingLink("https://meet.google.com/xyz-abcd-efg")
        for mutation in 0..<3 {
            let fixture = ScheduleTestFixture()
            let event = fixture.event(link: link)
            await fixture.reader.replace([event])
            fixture.coordinator.arm(event, link: link)
            await fixture.coordinator.waitForCheckForTesting()
            let replacement = ScheduleEvent(id: event.id, title: event.title, calendarTitle: event.calendarTitle,
                startDate: mutation == 1 ? event.startDate.addingTimeInterval(300) : event.startDate,
                endDate: event.endDate, meetingLinks: mutation == 0 ? [replacementLink] : [link])
            await fixture.reader.replace(mutation == 2 ? [] : [replacement])
            fixture.clock.date = event.startDate
            fixture.scheduler.fire()
            await fixture.coordinator.waitForCheckForTesting()
            #expect(fixture.coordinator.plan == nil)
            #expect(fixture.coordinator.statusMessage == ScheduleError.eventChanged.errorDescription)
            #expect(await fixture.opener.urls.isEmpty)
        }
    }

    @Test func canceledDeclinedAllDayAndUnrecognizedDestinationsCannotBeArmed() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let unrecognized = try meetingLink("https://example.com/meeting")
        #expect(fixture.coordinator.arm(fixture.event(cancelled: true, link: link), link: link) == false)
        #expect(fixture.coordinator.arm(fixture.event(declined: true, link: link), link: link) == false)
        #expect(fixture.coordinator.arm(fixture.event(allDay: true, link: link), link: link) == false)
        #expect(fixture.coordinator.arm(fixture.event(offset: -1, link: link), link: link) == false)
        #expect(fixture.coordinator.arm(fixture.event(link: unrecognized), link: unrecognized) == false)
        #expect(await fixture.reader.requests.isEmpty)
        #expect(await fixture.opener.urls.isEmpty)
    }

    @Test func accessLossStopsArmedPlanAndDoesNotRetry() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        fixture.coordinator.arm(event, link: link)
        await fixture.coordinator.waitForCheckForTesting()
        await fixture.reader.setFailure(.calendarAccessRequired)
        fixture.autoMonitor.notifyChange()
        await fixture.coordinator.waitForCheckForTesting()
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.coordinator.statusMessage == ScheduleError.calendarAccessRequired.errorDescription)
        #expect(fixture.scheduler.scheduledDate == nil)
        await fixture.reader.setFailure(nil)
        fixture.clock.date = event.startDate
        fixture.scheduler.fire()
        fixture.autoMonitor.notifyChange()
        #expect(await fixture.opener.urls.isEmpty)
    }

    @Test func manualJoinCancelsPendingAutomaticDuplicateAndKeepsRecurrencesDistinct() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        let nextOccurrence = fixture.event(offset: 86_400, link: link)
        await fixture.reader.replace([event, nextOccurrence])
        fixture.coordinator.arm(event, link: link)
        await fixture.coordinator.waitForCheckForTesting()
        try await fixture.coordinator.joinNow(event, link: link)
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.coordinator.canArm(event, link: link) == false)
        fixture.clock.date = event.startDate
        fixture.scheduler.fire()
        #expect(await fixture.opener.urls == [link.url])
        #expect(fixture.coordinator.arm(nextOccurrence, link: link))
        await fixture.coordinator.waitForCheckForTesting()
        #expect(fixture.coordinator.plan?.event.id == nextOccurrence.id)
        fixture.coordinator.cancel()
    }

    @Test func manualJoinCannotDuplicateAnAutomaticHandoffAlreadyInFlight() async throws {
        let fixture = ScheduleTestFixture()
        let opener = SuspendedScheduleOpener()
        let coordinator = ScheduleAutoJoinCoordinator(reader: fixture.reader, opener: opener,
            now: { fixture.clock.date }, scheduler: fixture.scheduler, monitor: fixture.autoMonitor)
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        coordinator.arm(event, link: link)
        await coordinator.waitForCheckForTesting()
        fixture.clock.date = event.startDate
        fixture.scheduler.fire()
        await opener.waitUntilOpened()
        #expect(coordinator.plan == nil)
        await #expect(throws: ScheduleError.self) {
            try await coordinator.joinNow(event, link: link)
        }
        #expect(await opener.urls == [link.url])
        await opener.complete()
        await coordinator.waitForCheckForTesting()
        #expect(coordinator.statusMessage == "Meeting opened.")
    }

    private func meetingLink(_ string: String = "https://meet.google.com/abc-defg-hij") throws -> ScheduleMeetingLink {
        let url = try #require(URL(string: string))
        return try #require(ScheduleMeetingLinkExtractor.validated(url))
    }
}

private actor SuspendedScheduleOpener: URLOpening {
    private(set) var urls: [URL] = []
    private var completion: CheckedContinuation<Void, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func openURL(_ url: URL) async throws {
        urls.append(url)
        await withCheckedContinuation { continuation in
            completion = continuation
            let waiters = startedWaiters
            startedWaiters = []
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilOpened() async {
        guard urls.isEmpty else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func complete() {
        completion?.resume()
        completion = nil
    }
}
