import Foundation

/// Operator-managed agents exposed through their documented Chat Completions API.
public enum ExternalAgentKind: String, Codable, CaseIterable, Sendable {
    case hermes, openClaw
    public var title: String { self == .hermes ? "Hermes" : "OpenClaw" }
    public var suggestedEndpoint: String {
        self == .hermes ? "http://127.0.0.1:8642/v1" : "http://127.0.0.1:18789/v1"
    }
    public var setupURL: URL? {
        URL(string: self == .hermes
            ? "https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server"
            : "https://docs.openclaw.ai/gateway/openai-http-api")
    }
}

/// Non-secret connection metadata. Credentials are stored separately from views in Keychain.
public struct ExternalAgentConnection: Codable, Equatable, Sendable {
    public let kind: ExternalAgentKind
    public let endpoint: URL
    public let revision: UUID
    public let targets: [String]
    public init(kind: ExternalAgentKind, endpoint: URL, revision: UUID = UUID(), targets: [String]) {
        self.kind = kind; self.endpoint = endpoint; self.revision = revision; self.targets = targets
    }
}

/// Only explicitly submitted conversation text crosses this boundary.
public struct ExternalAgentMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) { self.role = role; self.content = content }
}

/// Streaming callbacks share one explicit concurrency contract across app and package targets.
public typealias ExternalAgentTextReceiver = @Sendable (String) async throws -> Void
public typealias ExternalAgentProgressReceiver = @Sendable () async throws -> Void

/// Tools run on the agent server under its policy. No client tools are advertised or executed.
public protocol ExternalAgentServing: Sendable {
    func connection(for kind: ExternalAgentKind) async throws -> ExternalAgentConnection?
    func connect(kind: ExternalAgentKind, endpoint: String, token: String) async throws -> ExternalAgentConnection
    func disconnect(kind: ExternalAgentKind) async throws
    func refresh(_ connection: ExternalAgentConnection) async throws -> [String]
    func respond(connection: ExternalAgentConnection, target: String, conversationID: UUID,
                 messages: [ExternalAgentMessage], onText: @escaping ExternalAgentTextReceiver,
                 onProgress: @escaping ExternalAgentProgressReceiver) async throws
}

/// Fixed messages never expose credentials, private endpoints, server bodies or tool arguments.
public enum ExternalAgentError: Error, LocalizedError, Sendable {
    case invalidEndpoint, invalidToken, invalidResponse, unavailable, changed, busy, storage, tooLarge, unsupportedTool
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter an HTTPS API base URL ending in /v1, or an HTTP loopback address. Credentials, queries and fragments are not allowed in the URL."
        case .invalidToken: "Enter the server's bearer token or password (up to 4,096 characters)."
        case .invalidResponse: "The agent returned an incomplete or unsupported response. Check its server console before sending another message."
        case .unavailable: "The agent server is unavailable. Start its API server and check the address and credentials."
        case .changed: "This connection changed. Reopen the connection and start a new conversation."
        case .busy: "A connection change is still in progress. Try again when it finishes."
        case .storage: "The connection could not be read or saved in Keychain."
        case .tooLarge: "This conversation reached its size limit. Start a new conversation."
        case .unsupportedTool: "The server requested a client-side tool or approval. Use the agent's own interface to review it. Commandly did not run or approve it."
        }
    }
}
