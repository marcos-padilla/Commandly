import Foundation

/// Local persistence boundary for finance records. Callers must never log payloads or paths.
nonisolated protocol FinancePersisting: Sendable {
    func loadLedger() async throws -> FinanceLedger
    func saveLedger(_ ledger: FinanceLedger) async throws
}

nonisolated enum FinancePersistenceError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case unsupportedVersion
    case readFailed
    case writeFailed
}

actor JSONFinanceStore: FinancePersisting {
    private struct Envelope: Codable {
        let version: Int
        let ledger: FinanceLedger
    }

    private nonisolated static let currentVersion = 1
    private let explicitFileURL: URL?

    init(fileURL: URL? = nil) {
        self.explicitFileURL = fileURL
    }

    func loadLedger() async throws -> FinanceLedger {
        try Task.checkCancellation()
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try Task.checkCancellation()
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == Self.currentVersion else {
                throw FinancePersistenceError.unsupportedVersion
            }
            return envelope.ledger
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FinancePersistenceError {
            throw error
        } catch {
            throw FinancePersistenceError.readFailed
        }
    }

    func saveLedger(_ ledger: FinanceLedger) async throws {
        try Task.checkCancellation()
        let fileURL = try resolvedFileURL()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                Envelope(version: Self.currentVersion, ledger: ledger)
            )
            try Task.checkCancellation()
            try data.write(to: fileURL, options: [.atomic])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FinancePersistenceError.writeFailed
        }
    }

    private func resolvedFileURL() throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw FinancePersistenceError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Commandly", isDirectory: true)
            .appendingPathComponent("FinanceLedger.json", isDirectory: false)
    }
}

actor InMemoryFinanceStore: FinancePersisting {
    private var ledger: FinanceLedger
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    init(ledger: FinanceLedger = .empty) {
        self.ledger = ledger
    }

    func loadLedger() async throws -> FinanceLedger {
        try Task.checkCancellation()
        loadCount += 1
        return ledger
    }

    func saveLedger(_ ledger: FinanceLedger) async throws {
        try Task.checkCancellation()
        self.ledger = ledger
        saveCount += 1
    }

    func snapshot() -> FinanceLedger {
        ledger
    }
}
