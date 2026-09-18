import Foundation

/// The provider's maximum content rating, applied by its API without locally filtering results.
public enum GIFContentRating: String, CaseIterable, Sendable, Identifiable { case g, pg, pg13 = "pg-13", r; public var id: Self { self } }
/// Explicit search text is preserved exactly. Trending is a separate explicit operation.
public enum GIFCatalogQuery: Sendable, Equatable { case search(String), trending }
/// Nonsecret identity of one configured GIF provider connection.
public struct GIFConnectionState: Sendable, Equatable {
    public let revision: UUID
    public let isConfigured: Bool
    public init(revision: UUID, isConfigured: Bool) { self.revision = revision; self.isConfigured = isConfigured }
}
/// Returned provider metadata; source URLs and media URLs are validated before use and never logged.
public struct GIFCatalogItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let accessibilityText: String
    public let creator: String?
    public let sourceName: String?
    public let pageURL: URL?
    public let sourceURL: URL?
    public let previewURL: URL?
    public let originalURL: URL?
    public init(id: String, title: String, accessibilityText: String, creator: String?, sourceName: String?, pageURL: URL?, sourceURL: URL?, previewURL: URL?, originalURL: URL?) {
        self.id = id; self.title = title; self.accessibilityText = accessibilityText; self.creator = creator; self.sourceName = sourceName
        self.pageURL = pageURL; self.sourceURL = sourceURL; self.previewURL = previewURL; self.originalURL = originalURL
    }
}
/// One provider-ordered result page; no mixed providers or retained local search index.
public struct GIFCatalogPage: Sendable, Equatable {
    public let items: [GIFCatalogItem]
    public let nextOffset: Int?
    public init(items: [GIFCatalogItem], nextOffset: Int?) { self.items = items; self.nextOffset = nextOffset }
}
/// Remote GIF catalog and credential boundary; implementations must reject stale connection revisions.
public protocol GIFCatalogServing: Sendable {
    /// Reads configured status without making a provider request or exposing its key.
    func connection() async throws -> GIFConnectionState
    /// Stores a user-supplied key securely; does not validate it by an implicit remote query.
    func configure(key: String) async throws -> GIFConnectionState
    /// Invalidates in-flight requests, removes the key, and disconnects.
    func disconnect() async throws -> GIFConnectionState
    /// Searches only after explicit user submission; offsets are provider pagination positions.
    func search(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, connection: UUID) async throws -> GIFCatalogPage
    /// Downloads one validated provider rendition directly into bounded ephemeral memory.
    func media(_ item: GIFCatalogItem, original: Bool, connection: UUID) async throws -> Data
}
/// Copying preserves the animated GIF data. Save writes only to a user-selected destination.
public protocol GIFExporting: Sendable {
    /// Copies validated animation bytes, not a static preview or URL masquerading as a GIF.
    func copy(_ data: Data) async throws
    /// Presents native Save UI and returns false when cancelled, true only after successful output.
    func save(_ data: Data, suggestedName: String) async throws -> Bool
}
/// Sanitized failures never contain API keys, request URLs, queries, or response bodies.
public enum GIFSearchError: Error, Equatable, Sendable, LocalizedError {
    case setupRequired, invalidKey, credentialsUnavailable, changedConnection, queryTooLong, invalidRequest
    case unauthorized, rateLimited, unavailable, invalidResponse, responseTooLarge, unsafeURL
    case invalidGIF, notAnimated, previewTooLarge, copyFailed, exportFailed, exportCleanupFailed
    public var errorDescription: String? {
        switch self {
        case .setupRequired: "Add your GIPHY API key to search animated GIFs."
        case .invalidKey: "Enter a valid GIPHY API key without spaces, up to 256 characters."
        case .credentialsUnavailable: "The GIF API key could not be accessed in Keychain. Unlock your Mac and try again."
        case .changedConnection: "The GIF connection changed. Search again with the current key."
        case .queryTooLong: "GIPHY searches support up to 50 characters. Shorten the search and try again."
        case .invalidRequest: "Enter a search phrase or choose Trending."
        case .unauthorized: "GIPHY rejected this API key. Check its setup and access, then replace it if needed."
        case .rateLimited: "GIPHY's request limit was reached. Beta keys allow 100 API calls per hour. Wait before searching again."
        case .unavailable: "GIPHY is unavailable. Check your connection and try again."
        case .invalidResponse: "GIPHY returned an unsupported response. Try the search again."
        case .responseTooLarge: "This GIF or response exceeds Commandly's download limit. Choose another result or open its source."
        case .unsafeURL: "This result uses an unsupported media address. Open its GIPHY page instead."
        case .invalidGIF: "This response is not a supported GIF file. No static image was substituted."
        case .notAnimated: "This GIF contains only one frame. Choose an animated result."
        case .previewTooLarge: "This animation is too large to preview safely. You can still try copying or saving its original GIF."
        case .copyFailed: "The animated GIF could not be copied. Try again or save it as a file."
        case .exportCleanupFailed: "The GIF was saved, but temporary export cleanup failed. The saved file is available at your chosen destination."
        case .exportFailed: "The GIF could not be saved. Choose a writable destination and try again."
        }
    }
}
