import AIKit
import Foundation
import SecurityKit

@MainActor
struct ExternalAgentApplicationServices {
    let service: any ExternalAgentServing
    static func live(store: any SecureStoring) -> Self {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration, delegate: ExternalAgentRedirectDelegate(), delegateQueue: nil)
        return Self(service: ExternalAgentService(store: store, http: URLSessionAIHTTPTransport(session: session),
                                                  streaming: URLSessionAIHTTPStreamingTransport(session: session)))
    }
    static var unavailable: Self { Self(service: UnavailableExternalAgentService()) }
}

private nonisolated struct UnavailableExternalAgentService: ExternalAgentServing {
    func connection(for kind: ExternalAgentKind) async throws -> ExternalAgentConnection? { nil }
    func connect(kind: ExternalAgentKind, endpoint: String, token: String) async throws -> ExternalAgentConnection { throw ExternalAgentError.unavailable }
    func disconnect(kind: ExternalAgentKind) async throws { throw ExternalAgentError.unavailable }
    func refresh(_ connection: ExternalAgentConnection) async throws -> [String] { throw ExternalAgentError.unavailable }
    func respond(connection: ExternalAgentConnection, target: String, conversationID: UUID, messages: [ExternalAgentMessage],
                 onText: @escaping ExternalAgentTextReceiver,
                 onProgress: @escaping ExternalAgentProgressReceiver) async throws { throw ExternalAgentError.unavailable }
}
