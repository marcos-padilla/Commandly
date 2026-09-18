import Foundation

/// A locally configured Notion integration. Its token is kept separately in secure storage.
public struct NotionWorkspaceConnection: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let revision: UUID
    public init(id: UUID, name: String, revision: UUID) { self.id = id; self.name = name; self.revision = revision }
}

/// Readable workspace item; child navigation never accepts an arbitrary network address.
public struct NotionWorkspaceItem: Identifiable, Equatable, Sendable {
    /// Supported native navigation targets.
    public enum Kind: String, Sendable { case page, dataSource, database, block }
    public let id: UUID
    public let title: String
    public let kind: Kind
    public let text: String
    public let hasChildren: Bool
    public init(id: UUID, title: String, kind: Kind, text: String = "", hasChildren: Bool = false) {
        self.id = id; self.title = title; self.kind = kind; self.text = text; self.hasChildren = hasChildren
    }
    /// A canonical Notion page address, independent of response-supplied links.
    public var webURL: URL? { URL(string: "https://www.notion.so/" + id.uuidString.replacingOccurrences(of: "-", with: "")) }
}

/// One bounded page of results. More pages require an explicit user action.
public struct NotionWorkspacePage: Sendable {
    public let items: [NotionWorkspaceItem]
    public let nextCursor: String?
    public init(items: [NotionWorkspaceItem], nextCursor: String?) { self.items = items; self.nextCursor = nextCursor }
}

/// A closed, read-only view of the Notion API.
public protocol NotionWorkspaceServing: Sendable {
    func connection() async throws -> NotionWorkspaceConnection?
    func connect(token: String) async throws -> NotionWorkspaceConnection
    func disconnect() async throws
    func search(_ query: String, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage
    func children(of item: NotionWorkspaceItem, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage
}

/// Fixed messages keep private server errors and credentials out of diagnostics.
public enum NotionWorkspaceError: Error, Sendable, LocalizedError {
    case setupRequired, invalidToken, denied, notShared, invalidResponse, tooLarge, unavailable, storage, changed, busy, rateLimited(Int)
    public var errorDescription: String? {
        switch self {
        case .setupRequired: "Connect a Notion workspace first."
        case .invalidToken: "Enter a valid internal integration token."
        case .denied: "Notion rejected this token. Check the integration’s read permissions or replace its token."
        case .notShared: "This page is unavailable. Share it with your Notion integration, then try again."
        case .invalidResponse: "Notion returned an unsupported response. Try refreshing."
        case .tooLarge: "This response is too large to preview. Open the page in Notion."
        case .unavailable: "Could not reach Notion. Check your connection and try again."
        case .storage: "The saved Notion connection could not be accessed. Try again after unlocking Keychain."
        case .changed: "The workspace connection changed. Reload it before continuing."
        case .busy: "The connection is still being updated."
        case .rateLimited(let seconds): "Notion is limiting requests. Try again in \(seconds) seconds."
        }
    }
}
