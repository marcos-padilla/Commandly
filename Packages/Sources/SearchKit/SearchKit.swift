import Foundation

/// A user-authored search query.
public struct SearchQuery: Sendable, Equatable, Hashable {
    /// Raw query text.
    public let text: String
    /// Optional limit on the number of results.
    public let limit: Int?

    /// Creates a search query after normalizing surrounding whitespace.
    public init(text: String, limit: Int? = nil) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.limit = limit
    }

    /// Whether the query has no meaningful text.
    public var isEmpty: Bool {
        text.isEmpty
    }
}

/// Identifier for a search provider.
public struct SearchProviderID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a search provider identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A single search hit.
public struct SearchItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let providerID: SearchProviderID
    public let score: Double

    /// Creates a search item.
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        providerID: SearchProviderID,
        score: Double
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.providerID = providerID
        self.score = score
    }
}

/// Aggregated search response.
public struct SearchResult: Sendable, Equatable {
    public let query: SearchQuery
    public let items: [SearchItem]
    public let isComplete: Bool

    /// Creates a search result.
    public init(query: SearchQuery, items: [SearchItem], isComplete: Bool = true) {
        self.query = query
        self.items = items
        self.isComplete = isComplete
    }
}

/// Contract for asynchronous, cancellable search providers.
///
/// Implementations must respect task cancellation and avoid blocking the main actor.
public protocol SearchProviding: Sendable {
    /// Stable provider identifier.
    var id: SearchProviderID { get }

    /// Performs a search for the given query.
    func search(_ query: SearchQuery) async throws -> SearchResult
}

/// Built-in provider identifiers used by Commandly composition.
public enum BuiltInSearchProviderID: Sendable {
    public static let commands = SearchProviderID(rawValue: "commands")
    public static let applications = SearchProviderID(rawValue: "applications")
    public static let placeholders = SearchProviderID(rawValue: "placeholders")
}

/// Scores title / subtitle / keyword haystacks for ranked launcher search.
///
/// Higher is better. Returns `nil` when `query` is non-empty and nothing matches.
public enum SearchMatchScorer: Sendable {
    /// Exact title match.
    public static let exactTitle: Double = 1.0
    /// Title has the query as a prefix.
    public static let titlePrefix: Double = 0.9
    /// A keyword has the query as a prefix.
    public static let keywordPrefix: Double = 0.75
    /// Title contains the query.
    public static let titleContains: Double = 0.55
    /// Subtitle contains the query.
    public static let subtitleContains: Double = 0.4
    /// A keyword contains the query.
    public static let keywordContains: Double = 0.3
    /// Baseline score when the query is empty (listing mode).
    public static let emptyQueryBaseline: Double = 0.1

    /// Returns a relevance score, or `nil` if the record should be excluded.
    public static func score(
        query: String,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = []
    ) -> Double? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.isEmpty == false else {
            return emptyQueryBaseline
        }

        let titleLower = title.lowercased()
        if titleLower == needle { return exactTitle }
        if titleLower.hasPrefix(needle) { return titlePrefix }

        let keywordLowers = keywords.map { $0.lowercased() }
        if keywordLowers.contains(where: { $0.hasPrefix(needle) }) {
            return keywordPrefix
        }
        if titleLower.contains(needle) { return titleContains }

        if let subtitle, subtitle.lowercased().contains(needle) {
            return subtitleContains
        }
        if keywordLowers.contains(where: { $0.contains(needle) }) {
            return keywordContains
        }
        return nil
    }
}
