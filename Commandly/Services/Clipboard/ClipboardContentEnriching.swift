import Foundation

/// Outcome of capture-time clipboard content indexing.
///
/// Enriched strings must never be logged.
enum ClipboardEnrichmentStatus: String, Sendable, Equatable {
    /// Plain text entries already searchable via `text`.
    case notNeeded
    /// Queued or running Vision / file extraction.
    case pending
    /// Searchable metadata is ready (may still be empty).
    case ready
    /// Extraction failed (sandbox, corrupt file, Vision error).
    case failed
    /// Unsupported type or intentionally not indexed.
    case skipped
}

/// Result of enriching one clipboard entry. Contents must never be logged.
struct ClipboardEnrichment: Sendable, Equatable {
    var searchableText: String?
    var classificationLabels: [String]
    var status: ClipboardEnrichmentStatus

    static func skipped() -> ClipboardEnrichment {
        ClipboardEnrichment(searchableText: nil, classificationLabels: [], status: .skipped)
    }

    static func failed() -> ClipboardEnrichment {
        ClipboardEnrichment(searchableText: nil, classificationLabels: [], status: .failed)
    }

    static func ready(searchableText: String?, labels: [String]) -> ClipboardEnrichment {
        ClipboardEnrichment(
            searchableText: Self.normalizedSearchableText(searchableText),
            classificationLabels: Self.normalizedLabels(labels),
            status: .ready
        )
    }

    private static func normalizedSearchableText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for label in labels {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

/// Capture-time indexer for clipboard images and files.
///
/// Implementations must run off the main actor, respect cancellation, and never log contents.
protocol ClipboardContentEnriching: Sendable {
    func enrich(_ entry: ClipboardHistoryEntry) async -> ClipboardEnrichment
}

/// Test / CI enricher that performs no Vision or filesystem work.
struct NoOpClipboardContentEnricher: ClipboardContentEnriching {
    func enrich(_ entry: ClipboardHistoryEntry) async -> ClipboardEnrichment {
        switch entry.contentType {
        case .text:
            return ClipboardEnrichment(
                searchableText: nil,
                classificationLabels: [],
                status: .notNeeded
            )
        case .image, .fileURL:
            return .skipped()
        }
    }
}

/// Deterministic enricher for unit tests.
struct StubClipboardContentEnricher: ClipboardContentEnriching {
    var result: ClipboardEnrichment
    var delayNanoseconds: UInt64 = 0

    func enrich(_ entry: ClipboardHistoryEntry) async -> ClipboardEnrichment {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if Task.isCancelled {
            return .skipped()
        }
        switch entry.contentType {
        case .text:
            return ClipboardEnrichment(
                searchableText: nil,
                classificationLabels: [],
                status: .notNeeded
            )
        case .image, .fileURL:
            return result
        }
    }
}
