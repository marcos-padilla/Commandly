import CryptoKit
import Foundation

nonisolated protocol MarkdownPreviewScrollStateStoring: Sendable {
    func scrollPosition(for sourceURL: URL) async -> Double?
    func setScrollPosition(_ position: Double, for sourceURL: URL) async
}

actor InMemoryMarkdownPreviewScrollStore: MarkdownPreviewScrollStateStoring {
    private var positions: [String: Double] = [:]

    func scrollPosition(for sourceURL: URL) -> Double? {
        positions[Self.documentIdentifier(for: sourceURL)]
    }

    func setScrollPosition(_ position: Double, for sourceURL: URL) {
        guard position.isFinite, position >= 0 else { return }
        positions[Self.documentIdentifier(for: sourceURL)] = position
    }

    private static func documentIdentifier(for sourceURL: URL) -> String {
        MarkdownPreviewScrollIdentifier.make(for: sourceURL)
    }
}

/// Persists only bounded scroll offsets keyed by a one-way digest, never a filename or path.
actor UserDefaultsMarkdownPreviewScrollStore: MarkdownPreviewScrollStateStoring {
    private struct Record {
        let identifier: String
        let position: Double
        let updatedAt: Date
    }

    private let suiteName: String?
    private let key: String
    private let maximumRecordCount: Int

    init(
        suiteName: String? = nil,
        key: String = "markdownPreview.scrollPositions.v1",
        maximumRecordCount: Int = 24
    ) {
        self.suiteName = suiteName
        self.key = key
        self.maximumRecordCount = max(1, maximumRecordCount)
    }

    func scrollPosition(for sourceURL: URL) -> Double? {
        let identifier = MarkdownPreviewScrollIdentifier.make(for: sourceURL)
        return loadRecords().first(where: { $0.identifier == identifier })?.position
    }

    func setScrollPosition(_ position: Double, for sourceURL: URL) {
        guard position.isFinite, position >= 0 else { return }
        let identifier = MarkdownPreviewScrollIdentifier.make(for: sourceURL)
        var records = loadRecords().filter { $0.identifier != identifier }
        records.insert(
            Record(identifier: identifier, position: position, updatedAt: Date()),
            at: 0
        )
        if records.count > maximumRecordCount {
            records.removeLast(records.count - maximumRecordCount)
        }
        saveRecords(records)
    }

    private func loadRecords() -> [Record] {
        defaults().array(forKey: key)?.compactMap { value in
            guard let dictionary = value as? [String: Any],
                  let identifier = dictionary["identifier"] as? String,
                  let position = dictionary["position"] as? Double,
                  let updatedAt = dictionary["updatedAt"] as? Date,
                  position.isFinite,
                  position >= 0 else {
                return nil
            }
            return Record(identifier: identifier, position: position, updatedAt: updatedAt)
        } ?? []
    }

    private func saveRecords(_ records: [Record]) {
        let payload: [[String: Any]] = records.map { record in
            [
                "identifier": record.identifier,
                "position": record.position,
                "updatedAt": record.updatedAt,
            ]
        }
        defaults().set(payload, forKey: key)
    }

    private func defaults() -> UserDefaults {
        if let suiteName, let suiteDefaults = UserDefaults(suiteName: suiteName) {
            return suiteDefaults
        }
        return .standard
    }
}

nonisolated private enum MarkdownPreviewScrollIdentifier {
    static func make(for sourceURL: URL) -> String {
        let canonicalPath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
