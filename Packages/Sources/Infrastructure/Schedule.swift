import Foundation

/// Identifies one occurrence within a calendar; recurring instances are distinct.
public struct ScheduleOccurrenceID: Hashable, Sendable {
    /// Opaque local calendar identity, never logged.
    public let calendarID: String
    /// Opaque event/series identity, never logged.
    public let itemID: String
    /// Original occurrence date, retained when a recurring instance is moved.
    public let occurrenceDate: Date

    /// Creates an occurrence identity without accessing Calendar.
    public init(calendarID: String, itemID: String, occurrenceDate: Date) {
        self.calendarID = calendarID
        self.itemID = itemID
        self.occurrenceDate = occurrenceDate
    }
}

/// One locally validated HTTPS destination extracted from an event.
public struct ScheduleMeetingLink: Hashable, Sendable, Identifiable {
    /// Exact destination, potentially containing a private meeting token. Never logged.
    public let url: URL
    /// Human-readable service name or host.
    public let provider: String
    /// Whether this destination is recognized as a meeting service for explicit autojoin.
    public let supportsAutoJoin: Bool
    /// Stable identity within an ephemeral event snapshot.
    public var id: String { url.absoluteString }

    /// Creates an already-validated meeting destination.
    public init(url: URL, provider: String, supportsAutoJoin: Bool) {
        self.url = url
        self.provider = provider
        self.supportsAutoJoin = supportsAutoJoin
    }
}

/// A value snapshot of one Calendar occurrence. Never persisted or logged by Schedule.
public struct ScheduleEvent: Equatable, Sendable, Identifiable {
    /// Occurrence identity.
    public let id: ScheduleOccurrenceID
    /// Event title for local display.
    public let title: String
    /// Calendar title for local display.
    public let calendarTitle: String
    /// Scheduled start instant.
    public let startDate: Date
    /// Scheduled end instant.
    public let endDate: Date
    /// Whether the occurrence spans a calendar day without a fixed meeting time.
    public let isAllDay: Bool
    /// Whether the event has been canceled.
    public let isCancelled: Bool
    /// Whether the current participant declined the event.
    public let isDeclined: Bool
    /// Optional local display location; no address lookup is performed.
    public let location: String?
    /// Validated link choices; no link is opened while fetching events.
    public let meetingLinks: [ScheduleMeetingLink]

    /// Creates a detached value snapshot suitable for actor boundaries and tests.
    public init(
        id: ScheduleOccurrenceID, title: String, calendarTitle: String,
        startDate: Date, endDate: Date, isAllDay: Bool = false,
        isCancelled: Bool = false, isDeclined: Bool = false,
        location: String? = nil, meetingLinks: [ScheduleMeetingLink] = []
    ) {
        self.id = id
        self.title = title
        self.calendarTitle = calendarTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.location = location
        self.meetingLinks = meetingLinks
    }
}

/// Bounded request for event snapshots. Queries do not imply permission to open a meeting.
public struct ScheduleQuery: Equatable, Sendable {
    /// Beginning of the requested interval.
    public let startDate: Date
    /// End of the requested interval, at most 31 days after its beginning.
    public let endDate: Date
    /// Maximum returned occurrences, clamped to 1...500.
    public let limit: Int

    /// Creates a bounded query without touching the Calendar database.
    public init(startDate: Date, endDate: Date, limit: Int = 200) {
        self.startDate = startDate
        self.endDate = min(max(endDate, startDate), startDate.addingTimeInterval(31 * 86_400))
        self.limit = min(500, max(1, limit))
    }
}

/// Result of a local Calendar query.
public struct ScheduleSnapshot: Equatable, Sendable {
    /// Occurrences sorted by start date, then title.
    public let events: [ScheduleEvent]
    /// True when the scan reached its bound; the result must not be described as complete.
    public let isTruncated: Bool

    /// Creates a snapshot, preserving supplied value data only.
    public init(events: [ScheduleEvent], isTruncated: Bool = false) {
        self.events = events.sorted {
            $0.startDate == $1.startDate ? $0.title < $1.title : $0.startDate < $1.startDate
        }
        self.isTruncated = isTruncated
    }
}

/// Read-only Calendar boundary. Implementations must not prompt, mutate events, or open links.
public protocol ScheduleReading: Sendable {
    /// Fetches bounded snapshots or throws when full Calendar access is unavailable.
    func snapshot(for query: ScheduleQuery) async throws -> ScheduleSnapshot
}

/// Fixed user-facing failures that contain no event metadata or meeting tokens.
public enum ScheduleError: Error, LocalizedError, Sendable {
    /// The user must explicitly grant full Calendar access.
    case calendarAccessRequired
    /// Event data could not be read.
    case unavailable
    /// A chosen event was changed, removed, or became ineligible.
    case eventChanged
    /// The requested link is not a validated destination of the current event.
    case invalidMeetingLink
    /// An opening handoff for this occurrence is already in progress.
    case meetingAlreadyOpening

    /// Privacy-safe error description.
    public var errorDescription: String? {
        switch self {
        case .calendarAccessRequired: return "Full Calendar access is required to read your schedule."
        case .unavailable: return "Your schedule could not be loaded. Try refreshing."
        case .eventChanged: return "This event changed or is no longer available. Refresh before joining."
        case .invalidMeetingLink: return "Choose a valid HTTPS meeting link from this event."
        case .meetingAlreadyOpening: return "This meeting is already being opened."
        }
    }
}

/// Deterministic schedule provider for tests and previews; never accesses Calendar.
public actor InMemoryScheduleReader: ScheduleReading {
    private var value: ScheduleSnapshot

    /// Creates an isolated reader with explicit fixture events.
    public init(events: [ScheduleEvent] = []) {
        value = ScheduleSnapshot(events: events)
    }

    /// Replaces the fixture data.
    public func replace(_ snapshot: ScheduleSnapshot) { value = snapshot }

    /// Returns intersecting fixture occurrences within the query's bound.
    public func snapshot(for query: ScheduleQuery) async throws -> ScheduleSnapshot {
        try Task.checkCancellation()
        let matching = value.events.filter { $0.endDate > query.startDate && $0.startDate < query.endDate }
        return ScheduleSnapshot(
            events: Array(matching.prefix(query.limit)),
            isTruncated: value.isTruncated || matching.count > query.limit
        )
    }
}
