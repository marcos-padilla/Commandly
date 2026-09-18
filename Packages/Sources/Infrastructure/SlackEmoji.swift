import Foundation

/// Verified identity for one user-owned internal Slack app, without its bot token.
public struct SlackEmojiWorkspace: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let url: URL
    public let botID: String
    public let enterpriseID: String?
    public let revision: UUID
    public init(id: String, name: String, url: URL, botID: String, enterpriseID: String?, revision: UUID) {
        self.id = id; self.name = name; self.url = url; self.botID = botID; self.enterpriseID = enterpriseID; self.revision = revision
    }
}
/// Alias resolution remains explicit when a workspace does not return the target image.
public enum SlackEmojiResolution: Sendable, Equatable {
    case image(url: URL, canonicalName: String, aliasChain: [String])
    case missingAlias, aliasCycle, aliasTooDeep, unsupportedURL
    public var imageURL: URL? { if case .image(let url, _, _) = self { url } else { nil } }
}
/// One custom emoji name, including distinct aliases that copy their own Slack shortcode.
public struct SlackCustomEmoji: Sendable, Equatable, Identifiable {
    public let name: String
    public let resolution: SlackEmojiResolution
    public var id: String { name }
    public var shortcode: String { ":" + name + ":" }
    public init(name: String, resolution: SlackEmojiResolution) { self.name = name; self.resolution = resolution }
}
/// Session-only inventory identity; the adapter owns its bounded name and URL map until release.
public struct SlackEmojiCatalog: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let workspace: SlackEmojiWorkspace
    public let count: Int
    public let refreshedAt: Date
    public init(id: UUID, workspace: SlackEmojiWorkspace, count: Int, refreshedAt: Date) {
        self.id = id; self.workspace = workspace; self.count = count; self.refreshedAt = refreshedAt
    }
}
/// Search is local to the explicitly refreshed inventory, with an honest visible result cap.
public struct SlackEmojiMatches: Sendable, Equatable {
    public let items: [SlackCustomEmoji]
    public let total: Int
    public init(items: [SlackCustomEmoji], total: Int) { self.items = items; self.total = total }
}
/// Workspace credentials, explicit Slack API reads, and validated session-only custom emoji data.
public protocol SlackEmojiServing: Sendable {
    /// Reads connection metadata from secure storage without a Slack request.
    func connections() async throws -> [SlackEmojiWorkspace]
    /// Checks bot identity and exact emoji:read scope remotely before saving to Keychain.
    func connect(token: String, replacing: SlackEmojiWorkspace?) async throws -> SlackEmojiWorkspace
    /// Removes this local connection and cancels its work; never revokes a Slack app remotely.
    func disconnect(_ workspace: SlackEmojiWorkspace) async throws
    /// Explicitly fetches the bounded custom emoji inventory, rechecking workspace identity.
    func refresh(_ workspace: SlackEmojiWorkspace) async throws -> SlackEmojiCatalog
    /// Filters names and resolved alias targets without sending a search phrase to Slack.
    func search(_ query: String, catalog: SlackEmojiCatalog) async throws -> SlackEmojiMatches
    /// Fetches only a result belonging to this current inventory; never forwards a token to media.
    func media(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) async throws -> Data
    /// Releases the exact retired inventory and its in-flight media requests.
    func release(_ catalog: SlackEmojiCatalog) async
}
/// Explicit clipboard or Save actions never send messages to Slack or insert into another app.
public protocol SlackEmojiExporting: Sendable {
    /// Copies one selected custom emoji shortcode, independently of its image availability.
    func copyName(_ name: String) async throws
    /// Copies original validated image bytes, preserving GIF animation.
    func copyImage(_ data: Data) async throws
    /// Saves original validated bytes to a native user-selected destination; false means cancellation.
    func saveImage(_ data: Data, name: String) async throws -> Bool
}
/// Sanitized errors contain no credentials, workspace content, URLs, or response bodies.
public enum SlackEmojiError: Error, Sendable, Equatable, LocalizedError {
    case invalidToken, invalidIdentity, identityChanged, missingScope, excessiveScopes, unverifiedScopes
    case alreadyConnected, tooManyConnections, credentialsUnavailable, changedConnection, setupRequired
    case denied, expired, rateLimited(seconds: Int), unavailable, invalidResponse, catalogTooLarge
    case unsafeURL, responseTooLarge, invalidImage, previewTooLarge, copyFailed, exportFailed, exportCleanupFailed
    public var errorDescription: String? {
        switch self {
        case .invalidToken: "Enter a bot access token from your own internal Slack app. User, browser, and app-level tokens are not supported."
        case .invalidIdentity: "Slack did not return a supported bot and workspace identity. Check the app installation."
        case .identityChanged: "Slack's workspace identity differs from this connection. Use Replace Token to verify it again, or add a different workspace separately."
        case .missingScope: "The internal Slack app needs the emoji:read bot scope. Update its scope and reinstall it in your workspace."
        case .excessiveScopes: "Use a dedicated internal Slack app with only the emoji:read bot scope. This token has additional access."
        case .unverifiedScopes: "Slack did not confirm this token's scopes. Nothing was connected. Try again after checking the app."
        case .alreadyConnected: "This workspace is already connected. Use Replace Token to update its connection."
        case .tooManyConnections: "Commandly supports up to eight Slack emoji workspaces. Remove one before adding another."
        case .credentialsUnavailable: "The Slack connection could not be accessed in Keychain. Unlock your Mac and try again."
        case .changedConnection: "The workspace connection or inventory changed. Refresh it before trying again."
        case .setupRequired: "Connect your own internal Slack app to load its workspace's custom emoji."
        case .denied: "Slack denied access. Check the token, workspace app approval, and any network restrictions."
        case .expired: "This Slack token expired or was revoked. Replace it with a current bot access token."
        case .rateLimited(let seconds): "Slack's request limit was reached. Try again in \(seconds) seconds."
        case .unavailable: "Slack emoji is unavailable. Check your connection and try again."
        case .invalidResponse: "Slack returned an unsupported response. Refresh again after checking the connection."
        case .catalogTooLarge: "This workspace exceeds Commandly's inventory limit of 20,000 names or 4 MiB. No partial inventory was loaded."
        case .unsafeURL: "This emoji uses an unsupported media address. Its Slack name can still be copied."
        case .responseTooLarge: "This emoji exceeds the 8 MiB download limit. Its Slack name can still be copied."
        case .invalidImage: "The downloaded emoji is not a supported PNG, JPEG, or GIF image."
        case .previewTooLarge: "This emoji is too large to preview safely. You can still try saving its original image."
        case .copyFailed: "The emoji could not be copied. Try again."
        case .exportFailed: "The emoji could not be saved. Choose a writable destination and try again."
        case .exportCleanupFailed: "The emoji was saved, but temporary export cleanup failed. The selected file is available."
        }
    }
}
