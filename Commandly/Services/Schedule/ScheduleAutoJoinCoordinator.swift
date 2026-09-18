import Foundation
import Infrastructure
import Observation

/// Exact, user-reviewed occurrence and destination. Never persisted or logged.
nonisolated struct ScheduleAutoJoinPlan: Equatable {
    let event: ScheduleEvent
    let link: ScheduleMeetingLink
}

/// Runs only an explicitly armed occurrence. It survives launcher dismissal, not app termination.
@Observable
@MainActor
final class ScheduleAutoJoinCoordinator {
    private(set) var plan: ScheduleAutoJoinPlan?
    private(set) var statusMessage: String?
    private(set) var isChecking = false
    @ObservationIgnored private let reader: any ScheduleReading
    @ObservationIgnored private let opener: any URLOpening
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let scheduler: any ScheduleDeadlineScheduling
    @ObservationIgnored private let monitor: any ScheduleChangeObserving
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var joinedOccurrences: [ScheduleOccurrenceID: Date] = [:]
    @ObservationIgnored private var openingOccurrences: Set<ScheduleOccurrenceID> = []

    init(
        reader: any ScheduleReading,
        opener: any URLOpening,
        now: @escaping @MainActor () -> Date = Date.init,
        scheduler: any ScheduleDeadlineScheduling = NativeScheduleDeadlineScheduler(),
        monitor: any ScheduleChangeObserving = NativeScheduleChangeMonitor()
    ) {
        self.reader = reader
        self.opener = opener
        self.now = now
        self.scheduler = scheduler
        self.monitor = monitor
    }

    func canArm(_ event: ScheduleEvent, link: ScheduleMeetingLink) -> Bool {
        discardEndedOccurrences()
        return event.isAllDay == false && event.isCancelled == false && event.isDeclined == false
            && event.startDate > now()
            && event.startDate.timeIntervalSince(now()) <= 31 * 86_400
            && joinedOccurrences[event.id] == nil
            && event.meetingLinks.contains(link)
            && ScheduleMeetingLinkExtractor.validated(link.url)?.supportsAutoJoin == true
    }

    @discardableResult
    func arm(_ event: ScheduleEvent, link: ScheduleMeetingLink) -> Bool {
        guard canArm(event, link: link) else {
            statusMessage = "Choose an upcoming timed meeting with a supported meeting link."
            return false
        }
        cancel()
        plan = ScheduleAutoJoinPlan(event: event, link: link)
        statusMessage = "Automatic joining is armed for this occurrence while Commandly stays open."
        monitor.start { [weak self] in self?.checkNow() }
        checkNow()
        return true
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        scheduler.cancel()
        monitor.stop()
        plan = nil
        isChecking = false
        statusMessage = nil
    }

    /// Revalidates the exact occurrence/link before either waiting again or opening it once.
    func checkNow() {
        guard let expected = plan else { return }
        generation += 1
        let capturedGeneration = generation
        task?.cancel()
        scheduler.cancel()
        isChecking = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await currentEvent(matching: expected.event, link: expected.link)
                guard Task.isCancelled == false, generation == capturedGeneration, plan == expected else { return }
                isChecking = false
                let currentDate = now()
                if currentDate < expected.event.startDate {
                    scheduler.schedule(at: min(expected.event.startDate, currentDate.addingTimeInterval(30))) {
                        [weak self] in self?.checkNow()
                    }
                    return
                }
                guard currentDate.timeIntervalSince(expected.event.startDate) <= 60,
                      expected.event.endDate > currentDate else {
                    cancel()
                    statusMessage = "Automatic joining was skipped because the start window passed."
                    return
                }
                // Claim the occurrence before the asynchronous workspace handoff. Retries never
                // open a second meeting after an uncertain result or a concurrent notification.
                rememberJoinedOccurrence(expected.event)
                plan = nil
                monitor.stop()
                try await openMeeting(expected.event, link: expected.link)
                guard generation == capturedGeneration else { return }
                statusMessage = "Meeting opened."
            } catch is CancellationError {
                return
            } catch {
                guard generation == capturedGeneration else { return }
                cancel()
                statusMessage = (error as? ScheduleError)?.errorDescription
                    ?? "Automatic joining stopped. Review the meeting and join manually."
            }
        }
    }

    /// Explicit user join; confirms the latest Calendar data and suppresses scheduled duplicates.
    func joinNow(_ event: ScheduleEvent, link: ScheduleMeetingLink) async throws {
        // The automatic handoff can outlive its claimed plan. Reject a simultaneous manual
        // action while that handoff is in flight, without preventing a later explicit retry.
        guard openingOccurrences.contains(event.id) == false else { throw ScheduleError.meetingAlreadyOpening }
        if plan?.event.id == event.id { cancel() }
        _ = try await currentEvent(matching: event, link: link)
        try Task.checkCancellation()
        rememberJoinedOccurrence(event)
        try await openMeeting(event, link: link)
    }

    func waitForCheckForTesting() async { await task?.value }

    private func openMeeting(_ event: ScheduleEvent, link: ScheduleMeetingLink) async throws {
        guard openingOccurrences.insert(event.id).inserted else { throw ScheduleError.meetingAlreadyOpening }
        defer { openingOccurrences.remove(event.id) }
        try await opener.openURL(link.url)
    }

    private func rememberJoinedOccurrence(_ event: ScheduleEvent) {
        discardEndedOccurrences()
        if event.endDate > now() { joinedOccurrences[event.id] = event.endDate }
    }

    private func discardEndedOccurrences() {
        let currentDate = now()
        joinedOccurrences = joinedOccurrences.filter { $0.value > currentDate }
    }

    private func currentEvent(matching expected: ScheduleEvent, link: ScheduleMeetingLink) async throws -> ScheduleEvent {
        guard expected.meetingLinks.contains(link), ScheduleMeetingLinkExtractor.validated(link.url) != nil else {
            throw ScheduleError.invalidMeetingLink
        }
        let snapshot = try await reader.snapshot(for: ScheduleQuery(
            startDate: expected.startDate.addingTimeInterval(-1),
            endDate: expected.endDate.addingTimeInterval(1), limit: 500
        ))
        try Task.checkCancellation()
        guard let current = snapshot.events.first(where: { $0.id == expected.id }),
              current.startDate == expected.startDate, current.endDate == expected.endDate,
              current.isCancelled == false, current.isDeclined == false,
              current.meetingLinks.contains(where: { $0.url == link.url }) else {
            throw ScheduleError.eventChanged
        }
        return current
    }
}
