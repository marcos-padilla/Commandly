import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
struct ScheduleApplicationTests {
    @Test func openingWaitsForExplicitPermissionActionBeforeReading() async throws {
        let fixture = ScheduleTestFixture(access: .notDetermined)
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        #expect(model.phase == .accessRequired)
        #expect(await fixture.permissions.requestCount == 0)
        #expect(await fixture.reader.requests.isEmpty)
        #expect(await fixture.opener.urls.isEmpty)

        model.requestAccess()
        await model.waitForOperationForTesting()
        await model.waitForRefreshForTesting()
        #expect(await fixture.permissions.requestCount == 1)
        #expect(model.phase == .ready)
        #expect(await fixture.reader.requests.count == 1)
        model.stop()
    }

    @Test func deniedAccessUsesCalendarSettingsWithoutAnotherPrompt() async {
        let fixture = ScheduleTestFixture(access: .denied)
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        #expect(model.accessActionTitle == "Open Calendar Settings")
        model.performPrimary()
        await model.waitForOperationForTesting()
        await model.waitForRefreshForTesting()
        #expect(await fixture.permissions.requestCount == 0)
        #expect(await fixture.privacy.panes == [.calendars])
        #expect(await fixture.reader.requests.isEmpty)
        model.stop()
    }

    @Test func filtersResolveSelectionAndRangeRefreshesWithoutOpeningLinks() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let work = fixture.event(itemID: "work-event", title: "Design Review", link: link)
        let personal = fixture.event(itemID: "personal-event", offset: 600, title: "Coffee",
                                     calendarID: "personal", calendarTitle: "Personal", link: link)
        let ended = fixture.event(itemID: "ended", offset: -3_600, link: link)
        await fixture.reader.replace([personal, ended, work])
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        #expect(model.events.map(\.id) == [work.id, personal.id])
        #expect(model.calendarOptions.map(\.title) == ["Personal", "Work"])
        model.selectedCalendarID = "personal"
        #expect(model.selectedEvent?.id == personal.id)
        model.query = "no matches"
        #expect(model.selectedEvent == nil)
        #expect(model.handleEscape())
        #expect(model.selectedEvent?.id == personal.id)
        model.selectedCalendarID = nil
        model.query = "design"
        #expect(model.filteredEvents.map(\.id) == [work.id])
        model.range = .month
        await model.waitForRefreshForTesting()
        let request = try #require(await fixture.reader.requests.last)
        let expectedEnd = fixture.services.calendar.date(byAdding: .day, value: 30, to: request.startDate)
        #expect(request.endDate == expectedEnd)
        #expect(await fixture.opener.urls.isEmpty)
        model.stop()
    }

    @Test func joinNextOnlyReviewsAndConfirmationRevalidatesExactDestination() async throws {
        let fixture = ScheduleTestFixture()
        let first = try meetingLink()
        let second = try meetingLink("https://example.com/private-meeting?token=fixture")
        let source = fixture.event(link: first)
        let event = ScheduleEvent(id: source.id, title: source.title, calendarTitle: source.calendarTitle,
            startDate: source.startDate, endDate: source.endDate, meetingLinks: [first, second])
        await fixture.reader.replace([event])
        let model = ScheduleViewModel(services: fixture.services, reviewNextMeeting: true, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        #expect(model.reviewEvent == event)
        #expect(model.joinMode == .manual)
        #expect(await fixture.opener.urls.isEmpty)
        #expect(fixture.coordinator.plan == nil)
        model.selectedLinkID = second.id
        model.confirmReview()
        await model.waitForOperationForTesting()
        #expect(await fixture.opener.urls == [second.url])
        #expect(await fixture.reader.requests.count == 2)
        #expect(model.reviewEvent == nil)
        model.stop()
    }

    @Test func changedOrRemovedEventCannotOpenAnOldReviewedLink() async throws {
        let fixture = ScheduleTestFixture()
        let event = fixture.event(link: try meetingLink())
        await fixture.reader.replace([event])
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        model.prepareReview(mode: .manual)
        await fixture.reader.replace([])
        model.confirmReview()
        await model.waitForOperationForTesting()
        #expect(await fixture.opener.urls.isEmpty)
        #expect(model.statusMessage == ScheduleError.eventChanged.errorDescription)
        fixture.viewMonitor.notifyChange()
        await model.waitForRefreshForTesting()
        #expect(model.reviewEvent == nil)
        #expect(model.events.isEmpty)
        model.stop()
    }

    @Test func calendarRevocationClearsVisibleDataAndArmedOccurrence() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        model.prepareReview(mode: .automatic)
        #expect(fixture.coordinator.plan == nil)
        model.confirmReview()
        await fixture.coordinator.waitForCheckForTesting()
        #expect(fixture.coordinator.plan?.event == event)
        await fixture.permissions.set(.denied)
        fixture.viewMonitor.notifyChange()
        await model.waitForRefreshForTesting()
        #expect(model.phase == .accessRequired)
        #expect(model.events.isEmpty)
        #expect(model.reviewEvent == nil)
        #expect(fixture.coordinator.plan == nil)
        #expect(fixture.scheduler.scheduledDate == nil)
        #expect(await fixture.opener.urls.isEmpty)
        model.stop()
    }

    @Test func readFailureShowsRecoveryAndStoppingSessionKeepsExplicitAutojoin() async throws {
        let fixture = ScheduleTestFixture()
        let link = try meetingLink()
        let event = fixture.event(link: link)
        await fixture.reader.replace([event])
        let model = ScheduleViewModel(services: fixture.services, onGoBack: {})
        model.start()
        await model.waitForRefreshForTesting()
        #expect(fixture.coordinator.arm(event, link: link))
        await fixture.coordinator.waitForCheckForTesting()
        await fixture.reader.setFailure(.unavailable)
        model.refresh()
        await model.waitForRefreshForTesting()
        #expect(model.phase == .failed)
        #expect(model.events.isEmpty)
        #expect(model.errorMessage != nil)
        model.stop()
        #expect(fixture.coordinator.plan?.event == event)
        fixture.coordinator.cancel()
    }

    @Test func scheduleAndReviewToolAreRegisteredWithoutBackgroundExecution() async throws {
        let fixture = ScheduleTestFixture()
        let registry = LauncherApplicationRegistry.makeBuiltIn(scheduleServices: fixture.services)
        let children = registry.children(of: ScheduleApplication.id)
        #expect(children.map(\.id) == [ScheduleApplication.openToolID, ScheduleApplication.joinNextToolID])
        #expect(children.allSatisfy { $0.kind == .tool && $0.parentID == ScheduleApplication.id })
        #expect(registry.owningApplicationID(for: ScheduleApplication.joinNextToolID) == ScheduleApplication.id)
        let application = try #require(registry.application(for: ScheduleApplication.id))
        let settings = try #require(registry.resolvedSettings(for: ScheduleApplication.id))
        let context = LauncherApplicationContext(navigation: .init(dismissLauncher: {}, openSettings: {}, goBack: {}),
                                                 settings: settings)
        guard case .present(let session) = application.launch(toolID: ScheduleApplication.joinNextToolID,
                                                              arguments: CommandArguments(), in: context) else {
            Issue.record("Expected Schedule review session")
            return
        }
        let model = try #require(session.model(as: ScheduleViewModel.self))
        #expect(model.phase == .idle)
        #expect(await fixture.reader.requests.isEmpty)
        #expect(await fixture.opener.urls.isEmpty)
        session.stop()
    }

    private func meetingLink(_ string: String = "https://meet.google.com/abc-defg-hij") throws -> ScheduleMeetingLink {
        let url = try #require(URL(string: string))
        return try #require(ScheduleMeetingLinkExtractor.validated(url))
    }
}
