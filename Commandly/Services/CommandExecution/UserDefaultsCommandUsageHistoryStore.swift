import CommandKit
import Foundation

/// Bounded durable storage for privacy-safe shared command execution metadata.
///
/// The payload contains only command identifiers, invocation sources, outcome categories, UUIDs,
/// and timestamps. Command arguments, search queries, paths, clipboard contents, and result messages
/// are never accepted by this contract or written to UserDefaults.
actor UserDefaultsCommandUsageHistoryStore: CommandUsageHistoryStoring {
    private struct Envelope: Codable {
        let version: Int
        let records: [CommandExecutionRecord]
    }

    private static let currentVersion = 1

    private let defaults: UserDefaults
    private let key: String
    private let maximumRecordCount: Int
    private var recordsByID: [UUID: CommandExecutionRecord]

    init(
        suiteName: String? = nil,
        key: String = "commands.usage-history.v1",
        maximumRecordCount: Int = 1_000
    ) {
        let boundedMaximumRecordCount = max(1, maximumRecordCount)
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        self.key = key
        self.maximumRecordCount = boundedMaximumRecordCount
        self.recordsByID = Self.boundedRecords(
            Self.load(defaults: defaults, key: key),
            maximumRecordCount: boundedMaximumRecordCount
        )
    }

    func record(_ record: CommandExecutionRecord) {
        guard recordsByID[record.id] == nil else { return }
        recordsByID[record.id] = record
        trimToBound()
        persist()
    }

    func records(for commandID: CommandID) -> [CommandExecutionRecord] {
        recordsByID.values
            .filter { $0.commandID == commandID }
            .sorted(by: Self.sortRecords)
    }

    func summary(for commandID: CommandID) -> CommandUsageSummary? {
        let successes = recordsByID.values.filter {
            $0.commandID == commandID && $0.outcome == .succeeded
        }
        guard let latest = successes.max(by: { left, right in
            if left.timestamp != right.timestamp { return left.timestamp < right.timestamp }
            return left.id.uuidString < right.id.uuidString
        }) else {
            return nil
        }
        return CommandUsageSummary(
            commandID: commandID,
            successfulExecutionCount: successes.count,
            lastSuccessfulExecutionAt: latest.timestamp
        )
    }

    func allSummaries() -> [CommandUsageSummary] {
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

    private func trimToBound() {
        recordsByID = Self.boundedRecords(
            recordsByID,
            maximumRecordCount: maximumRecordCount
        )
    }

    private func persist() {
        let envelope = Envelope(
            version: Self.currentVersion,
            records: recordsByID.values.sorted(by: Self.sortRecords)
        )
        do {
            defaults.set(try JSONEncoder().encode(envelope), forKey: key)
        } catch {
            assertionFailure("Privacy-safe command usage history could not be encoded.")
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [UUID: CommandExecutionRecord] {
        guard let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == currentVersion else {
            return [:]
        }
        return Dictionary(
            envelope.records.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    private static func boundedRecords(
        _ recordsByID: [UUID: CommandExecutionRecord],
        maximumRecordCount: Int
    ) -> [UUID: CommandExecutionRecord] {
        guard recordsByID.count > maximumRecordCount else { return recordsByID }
        let retained = recordsByID.values
            .sorted(by: sortRecords)
            .suffix(maximumRecordCount)
        return Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }

    private static func sortRecords(
        _ left: CommandExecutionRecord,
        _ right: CommandExecutionRecord
    ) -> Bool {
        if left.timestamp != right.timestamp { return left.timestamp < right.timestamp }
        return left.id.uuidString < right.id.uuidString
    }
}
