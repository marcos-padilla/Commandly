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
