import CommandKit
import Foundation
import Infrastructure
import Observation
import SecurityKit

enum ScheduleRange: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String {
        switch self { case .today: "Today"; case .week: "Next 7 Days"; case .month: "Next 30 Days" }
    }
    var days: Int { switch self { case .today: 1; case .week: 7; case .month: 30 } }
}

enum ScheduleActionID {
    static let review = CommandActionID(rawValue: "schedule.review-meeting")
    static let refresh = CommandActionID(rawValue: "schedule.refresh")
    static let access = CommandActionID(rawValue: "schedule.access")
    static let confirm = CommandActionID(rawValue: "schedule.confirm-meeting")
    static let cancelReview = CommandActionID(rawValue: "schedule.cancel-review")
    static let prepareAutoJoin = CommandActionID(rawValue: "schedule.prepare-autojoin")
    static let cancelAutoJoin = CommandActionID(rawValue: "schedule.cancel-autojoin")
}

enum ScheduleLoadPhase: Equatable { case idle, loading, ready, accessRequired, failed }
enum ScheduleJoinMode: Equatable { case manual, automatic }

@Observable
@MainActor
final class ScheduleViewModel: LauncherApplicationModel {
    var query = "" { didSet { refreshSelection() } }
    var range: ScheduleRange = .week { didSet { refresh() } }
    var selectedCalendarID: String? { didSet { refreshSelection() } }
    var selectedID: ScheduleOccurrenceID?
    var selectedLinkID: String?
    var showsActionsMenu = false
    private(set) var phase: ScheduleLoadPhase = .idle
    private(set) var accessState: PermissionState = .notDetermined
    private(set) var events: [ScheduleEvent] = []
    private(set) var isTruncated = false
    private(set) var isPerforming = false
    private(set) var reviewEvent: ScheduleEvent?
    private(set) var joinMode: ScheduleJoinMode = .manual
    private(set) var errorMessage: String?
    private var message: String?
    @ObservationIgnored private let services: ScheduleApplicationServices
    @ObservationIgnored private let monitor: any ScheduleChangeObserving
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var shouldReviewNextMeeting: Bool

    init(services: ScheduleApplicationServices, reviewNextMeeting: Bool = false, onGoBack: @escaping () -> Void) {
        self.services = services
        self.monitor = services.makeChangeMonitor()
        self.onGoBack = onGoBack
        self.shouldReviewNextMeeting = reviewNextMeeting
    }

    var statusMessage: String? { message ?? services.autoJoin.statusMessage }
    var autoJoinPlan: ScheduleAutoJoinPlan? { services.autoJoin.plan }
    var filteredEvents: [ScheduleEvent] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { event in
            (selectedCalendarID == nil || selectedCalendarID == event.id.calendarID)
                && (needle.isEmpty || [event.title, event.calendarTitle, event.location ?? ""]
                    .contains { $0.localizedStandardContains(needle) })
        }
    }
    var selectedEvent: ScheduleEvent? {
        filteredEvents.first { $0.id == selectedID } ?? filteredEvents.first
    }
    var calendarOptions: [(id: String, title: String)] {
        var seen: Set<String> = []
        return events.compactMap {
            seen.insert($0.id.calendarID).inserted ? ($0.id.calendarID, $0.calendarTitle) : nil
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var reviewedLink: ScheduleMeetingLink? {
        reviewEvent?.meetingLinks.first { $0.id == selectedLinkID } ?? reviewEvent?.meetingLinks.first
    }
    var canJoinSelection: Bool {
        guard let event = selectedEvent else { return false }
        return event.isCancelled == false && event.isDeclined == false && event.meetingLinks.isEmpty == false
    }
    var canConfirm: Bool {
        guard isPerforming == false, let event = reviewEvent, let link = reviewedLink else { return false }
        return joinMode == .manual || services.autoJoin.canArm(event, link: link)
    }
    var accessActionTitle: String {
        accessState == .notDetermined ? "Grant Calendar Access" : "Open Calendar Settings"
    }

    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if reviewEvent != nil {
            primary = .init(id: ScheduleActionID.confirm, title: joinMode == .manual ? "Join Meeting" : "Enable Autojoin",
                            isPrimary: true, keyHint: .return, isEnabled: canConfirm)
        } else if phase == .accessRequired {
            primary = .init(id: ScheduleActionID.access, title: accessActionTitle,
                            isPrimary: true, keyHint: .return, isEnabled: isPerforming == false)
        } else {
            primary = .init(id: canJoinSelection ? ScheduleActionID.review : ScheduleActionID.refresh,
                            title: canJoinSelection ? "Review Meeting Link" : "Refresh",
                            isPrimary: true, keyHint: .return, isEnabled: phase != .loading && isPerforming == false)
        }
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            .init(id: ScheduleActionID.refresh, title: "Refresh Schedule", isEnabled: isPerforming == false),
            .init(id: ScheduleActionID.review, title: "Review Meeting Link", isEnabled: canJoinSelection),
            .init(id: ScheduleActionID.prepareAutoJoin, title: "Automatically Join This Occurrence…", isEnabled: canJoinSelection),
            .init(id: ScheduleActionID.cancelAutoJoin, title: "Cancel Automatic Joining", isEnabled: autoJoinPlan != nil)
        ]
    }

    func start() {
        guard isStarted == false else { return }
        isStarted = true
        monitor.start { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        generation += 1
        let expectedGeneration = generation
        refreshTask?.cancel()
        phase = .loading
        errorMessage = nil
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let access = await services.permissions.state(for: .calendar)
            guard Task.isCancelled == false, generation == expectedGeneration else { return }
            accessState = access
            guard access == .authorized else {
                events = []
                reviewEvent = nil
                phase = .accessRequired
                services.autoJoin.cancel()
                return
            }
            let start = services.calendar.startOfDay(for: services.now())
            let end = services.calendar.date(byAdding: .day, value: range.days, to: start) ?? start
            do {
                let snapshot = try await services.reader.snapshot(for: ScheduleQuery(startDate: start, endDate: end))
                guard Task.isCancelled == false, generation == expectedGeneration else { return }
                events = snapshot.events.filter { $0.endDate > services.now() }
                isTruncated = snapshot.isTruncated
                phase = .ready
                if let reviewEvent, events.first(where: { $0.id == reviewEvent.id }) != reviewEvent {
                    cancelReview()
                    message = "The reviewed event changed. Select it again to review its latest link."
                }
                if let selectedCalendarID, calendarOptions.contains(where: { $0.id == selectedCalendarID }) == false {
                    self.selectedCalendarID = nil
                }
                refreshSelection()
                if shouldReviewNextMeeting {
                    shouldReviewNextMeeting = false
                    selectedID = filteredEvents.first {
                        $0.meetingLinks.isEmpty == false && $0.isCancelled == false && $0.isDeclined == false
                    }?.id
                    prepareReview(mode: .manual)
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == expectedGeneration else { return }
                events = []
                reviewEvent = nil
                if case ScheduleError.calendarAccessRequired = error {
                    let currentAccess = await services.permissions.state(for: .calendar)
                    guard Task.isCancelled == false, generation == expectedGeneration else { return }
                    accessState = currentAccess
                    phase = .accessRequired
                    services.autoJoin.cancel()
                } else {
                    phase = .failed
                    errorMessage = "Your schedule could not be loaded. Try refreshing."
                }
            }
        }
    }

    func requestAccess() {
        guard isPerforming == false else { return }
        isPerforming = true
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if accessState == .notDetermined {
                _ = await services.permissions.request(.calendar)
            } else {
                await services.privacySettings.open(.calendars)
            }
            guard Task.isCancelled == false else { return }
            isPerforming = false
            refresh()
        }
    }

    func prepareReview(mode: ScheduleJoinMode) {
        guard canJoinSelection, let event = selectedEvent else { return }
        reviewEvent = event
        selectedLinkID = event.meetingLinks.first?.id
        joinMode = mode
        message = nil
        showsActionsMenu = false
    }

    func confirmReview() {
        guard canConfirm, let event = reviewEvent, let link = reviewedLink else { return }
        if joinMode == .automatic {
            if services.autoJoin.arm(event, link: link) { reviewEvent = nil; message = nil }
            return
        }
        isPerforming = true
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await services.autoJoin.joinNow(event, link: link)
                guard Task.isCancelled == false else { return }
                reviewEvent = nil
                message = "Meeting opened."
            } catch is CancellationError {
                return
            } catch {
                message = (error as? ScheduleError)?.errorDescription ?? "The meeting could not be opened. Try again."
            }
            isPerforming = false
        }
    }

    func cancelReview() { reviewEvent = nil; selectedLinkID = nil; message = nil }
    func cancelAutoJoin() { services.autoJoin.cancel(); message = "Automatic joining canceled." }
    func select(_ id: ScheduleOccurrenceID) { selectedID = id; cancelReview() }
    func moveSelection(offset: Int) {
        guard reviewEvent == nil else { return }
        selectedID = LauncherListSelection.nextID(in: filteredEvents, selectedID: selectedID, offset: offset, id: \.id)
    }
    func refreshSelection() {
        selectedID = LauncherListSelection.resolvedID(in: filteredEvents, selectedID: selectedID, id: \.id)
    }
    func performPrimary() {
        guard let action = footerActions.first(where: { $0.isPrimary && $0.isEnabled }) else { return }
        perform(action.id)
    }
    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        switch actionID {
        case ScheduleActionID.refresh: refresh()
        case ScheduleActionID.access: requestAccess()
        case ScheduleActionID.review: prepareReview(mode: .manual)
        case ScheduleActionID.prepareAutoJoin: prepareReview(mode: .automatic)
        case ScheduleActionID.confirm: confirmReview()
        case ScheduleActionID.cancelReview: cancelReview()
        case ScheduleActionID.cancelAutoJoin: cancelAutoJoin()
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }
    func goBack() { onGoBack() }
    func handleEscape() -> Bool {
        if reviewEvent != nil { cancelReview(); return true }
        if query.isEmpty == false { query = ""; return true }
        return false
    }
    func stop() {
        generation += 1
        refreshTask?.cancel()
        operationTask?.cancel()
        monitor.stop()
        isStarted = false
        isPerforming = false
        events = []
        reviewEvent = nil
        // The explicitly armed occurrence is owned by AppRuntime and deliberately survives.
    }
    func waitForRefreshForTesting() async { await refreshTask?.value }
    func waitForOperationForTesting() async { await operationTask?.value }
}
