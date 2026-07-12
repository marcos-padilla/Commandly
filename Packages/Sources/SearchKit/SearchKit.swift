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
    public static let calculator = SearchProviderID(rawValue: "calculator")
}

/// Broad file categories exposed by the file-search surface.
public enum FileSearchCategory: String, CaseIterable, Sendable, Codable, Identifiable {
    case all
    case folders
    case documents
    case images
    case audio
    case video
    case archives
    case sourceCode

    public var id: String { rawValue }

    /// Human-readable title for filter controls.
    public var title: String {
        switch self {
        case .all: return "All Files"
        case .folders: return "Folders"
        case .documents: return "Documents"
        case .images: return "Images"
        case .audio: return "Audio"
        case .video: return "Video"
        case .archives: return "Archives"
        case .sourceCode: return "Source Code"
        }
    }
}

/// Whether a file-search hit represents a regular file or a directory.
public enum FileSearchItemKind: String, Sendable, Codable, Equatable {
    case file
    case folder
}

/// The indexed field that produced a file-search hit.
public enum FileSearchMatchKind: String, Sendable, Codable, Equatable {
    case filename
    case contents
    case recent
}

/// A sandbox-safe request for indexed files.
public struct FileSearchRequest: Sendable, Equatable {
    public let query: SearchQuery
    public let category: FileSearchCategory
    public let includesFileNames: Bool
    public let includesFileContents: Bool

    public init(
        query: SearchQuery,
        category: FileSearchCategory = .all,
        includesFileNames: Bool = true,
        includesFileContents: Bool = true
    ) {
        self.query = query
        self.category = category
        self.includesFileNames = includesFileNames
        self.includesFileContents = includesFileContents
    }
}

/// Metadata snapshot displayed by the file-search result and preview panes.
public struct FileSearchItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let url: URL
    public let name: String
    public let parentPath: String
    public let kind: FileSearchItemKind
    public let contentTypeIdentifier: String?
    public let contentTypeDescription: String
    public let byteCount: Int64?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let lastUsedAt: Date?
    public let matchKind: FileSearchMatchKind

    public init(
        id: String? = nil,
        url: URL,
        name: String,
        parentPath: String,
        kind: FileSearchItemKind,
        contentTypeIdentifier: String? = nil,
        contentTypeDescription: String,
        byteCount: Int64? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        matchKind: FileSearchMatchKind = .filename
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.url = url
        self.name = name
        self.parentPath = parentPath
        self.kind = kind
        self.contentTypeIdentifier = contentTypeIdentifier
        self.contentTypeDescription = contentTypeDescription
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastUsedAt = lastUsedAt
        self.matchKind = matchKind
    }
}

/// Asynchronous file search backed by a local, cancellable index.
///
/// Implementations must not read file contents synchronously while the user is typing,
/// and must restrict results to locations the user has authorized.
public protocol FileSearching: Sendable {
    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem]
}

/// Keeps sandbox extensions active while a file-search surface displays previews and performs actions.
@MainActor
public protocol FileSearchSessionManaging: Sendable {
    func beginFileSearchSession()
    func endFileSearchSession()
}

/// Recoverable failures surfaced by file-search adapters.
public enum FileSearchError: Error, Sendable, Equatable {
    case noAuthorizedScopes
    case indexUnavailable
}

/// Deterministic file search used by tests and previews.
public actor InMemoryFileSearchService: FileSearching {
    private var items: [FileSearchItem]
    public private(set) var requests: [FileSearchRequest] = []

    public init(items: [FileSearchItem] = []) {
        self.items = items
    }

    public func replaceItems(_ items: [FileSearchItem]) {
        self.items = items
    }

    public func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        try Task.checkCancellation()
        requests.append(request)
        let limited = request.query.limit.map { Array(items.prefix($0)) } ?? items
        return limited
    }
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
