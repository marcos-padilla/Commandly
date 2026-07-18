import Foundation

/// Aggregate successful usage for one command.
public struct CommandUsageSummary: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity used by list presentation.
    public var id: CommandID { commandID }
    /// Command summarized by this value.
    public let commandID: CommandID
    /// Number of unique successful execution records.
    public let successfulExecutionCount: Int
    /// Most recent successful completion.
    public let lastSuccessfulExecutionAt: Date

    /// Creates a successful-usage summary.
    public init(
        commandID: CommandID,
        successfulExecutionCount: Int,
        lastSuccessfulExecutionAt: Date
    ) {
        self.commandID = commandID
        self.successfulExecutionCount = successfulExecutionCount
        self.lastSuccessfulExecutionAt = lastSuccessfulExecutionAt
    }
}

/// Stores privacy-safe execution records and successful usage aggregates.
public protocol CommandUsageHistoryStoring: Sendable {
    /// Records a privacy-safe execution once by its identifier.
    func record(_ record: CommandExecutionRecord) async
    /// Returns all recorded outcomes for one command in chronological order.
    func records(for commandID: CommandID) async -> [CommandExecutionRecord]
    /// Returns successful aggregate usage, or `nil` when the command has never succeeded.
    func summary(for commandID: CommandID) async -> CommandUsageSummary?
    /// Returns successful summaries ordered by frequency, recency, and command identifier.
    func allSummaries() async -> [CommandUsageSummary]
}

/// Deterministic in-memory usage history for composition, tests, and early runtime integration.
public actor InMemoryCommandUsageHistory: CommandUsageHistoryStoring {
    private var recordsByID: [UUID: CommandExecutionRecord] = [:]

    public init() {}

    /// Records an execution once by record identifier.
    public func record(_ record: CommandExecutionRecord) {
        recordsByID[record.id] = recordsByID[record.id] ?? record
    }

    /// Returns all recorded outcomes for one command in chronological order.
    public func records(for commandID: CommandID) -> [CommandExecutionRecord] {
        recordsByID.values
            .filter { $0.commandID == commandID }
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Returns aggregate successful usage. Failures and cancellations never affect the count or recency.
    public func summary(for commandID: CommandID) -> CommandUsageSummary? {
        let successes = recordsByID.values.filter {
            $0.commandID == commandID && $0.outcome == .succeeded
        }
        guard let mostRecent = successes.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        return CommandUsageSummary(
            commandID: commandID,
            successfulExecutionCount: successes.count,
            lastSuccessfulExecutionAt: mostRecent.timestamp
        )
    }

    /// Returns all successful summaries in deterministic ranking order.
    public func allSummaries() -> [CommandUsageSummary] {
        Set(recordsByID.values.map(\.commandID))
            .compactMap(summary(for:))
            .sorted {
                if $0.successfulExecutionCount != $1.successfulExecutionCount {
                    return $0.successfulExecutionCount > $1.successfulExecutionCount
                }
                if $0.lastSuccessfulExecutionAt != $1.lastSuccessfulExecutionAt {
                    return $0.lastSuccessfulExecutionAt > $1.lastSuccessfulExecutionAt
                }
                return $0.commandID.rawValue < $1.commandID.rawValue
            }
    }
}
