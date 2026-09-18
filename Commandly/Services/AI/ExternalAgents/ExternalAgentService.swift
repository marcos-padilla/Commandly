import AIKit
import Foundation
import SecurityKit

actor ExternalAgentService: ExternalAgentServing {
    private struct Record: Codable, Sendable { let connection: ExternalAgentConnection; let token: String }
    private let store: any SecureStoring
    private let http: any AIHTTPTransport
    private let streaming: any AIHTTPStreamingTransport
    private var mutations: [ExternalAgentKind: Task<ExternalAgentConnection?, Error>] = [:]
    private var discovered: [UUID: [String]] = [:]

    init(store: any SecureStoring, http: any AIHTTPTransport, streaming: any AIHTTPStreamingTransport) {
        self.store = store; self.http = http; self.streaming = streaming
    }
    func connection(for kind: ExternalAgentKind) async throws -> ExternalAgentConnection? {
        if let mutation = mutations[kind] { _ = await mutation.result }
        try Task.checkCancellation()
        return try await record(kind)?.connection
    }
    func connect(kind: ExternalAgentKind, endpoint: String, token: String) async throws -> ExternalAgentConnection {
        guard mutations[kind] == nil else { throw ExternalAgentError.busy }
        let endpoint = try ExternalAgentEndpoint.parse(endpoint)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExternalAgentEndpoint.validToken(token) else { throw ExternalAgentError.invalidToken }
        let task = Task<ExternalAgentConnection?, Error> { [store] in
            let targets = try await self.models(endpoint: endpoint, token: token)
            try Task.checkCancellation()
            let connection = ExternalAgentConnection(kind: kind, endpoint: endpoint, targets: targets)
            let encoded = try JSONEncoder().encode(Record(connection: connection, token: token))
            do { try await store.write(Self.key(kind), value: encoded) } catch { throw ExternalAgentError.storage }
            return connection
        }
        mutations[kind] = task; defer { mutations[kind] = nil }
        let connection = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard let connection else { throw ExternalAgentError.storage }
        discovered = discovered.filter { $0.key == connection.revision }
        return connection
    }
    func disconnect(kind: ExternalAgentKind) async throws {
        guard mutations[kind] == nil else { throw ExternalAgentError.busy }
        let task = Task<ExternalAgentConnection?, Error> { [store] in
            try Task.checkCancellation()
            do { try await store.delete(Self.key(kind)) } catch { throw ExternalAgentError.storage }
            return nil
        }
        mutations[kind] = task; defer { mutations[kind] = nil }
        _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func refresh(_ connection: ExternalAgentConnection) async throws -> [String] {
        let saved = try await checked(connection)
        let targets = try await models(endpoint: connection.endpoint, token: saved.token)
        _ = try await checked(connection)
        discovered[connection.revision] = targets
        return targets
    }
    func respond(connection: ExternalAgentConnection, target: String, conversationID: UUID,
                 messages: [ExternalAgentMessage], onText: @escaping ExternalAgentTextReceiver,
                 onProgress: @escaping ExternalAgentProgressReceiver) async throws {
        let saved = try await checked(connection)
        guard ExternalAgentEndpoint.validTarget(target), (discovered[connection.revision] ?? connection.targets).contains(target),
              !messages.isEmpty, messages.count <= 64, messages.last?.role == .user,
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 1024 * 1024 else { throw ExternalAgentError.tooLarge }
        var body: [String: Any] = ["model": target, "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }]
        if connection.kind == .openClaw { body["user"] = "commandly:" + conversationID.uuidString.lowercased() }
        // Hermes receives the caller-owned transcript without a persistent-session header.
        // This selects its documented synchronous delegation mode and avoids unseen background delivery.
        let request = AIHTTPRequest(method: .post, url: connection.endpoint.appendingPathComponent("chat/completions"),
            headers: ["Authorization": "Bearer " + saved.token, "Content-Type": "application/json", "Accept": "text/event-stream"],
            body: try JSONSerialization.data(withJSONObject: body), timeout: 120)
        let parser = ExternalAgentStream(onText: { delta in
            _ = try await self.checked(connection)
            try Task.checkCancellation(); try await onText(delta)
        }, onProgress: {
            _ = try await self.checked(connection)
            try Task.checkCancellation(); try await onProgress()
        })
        let response = try await streaming.send(request) { line in try await parser.accept(line) }
        guard (200..<300).contains(response.statusCode),
              response.header(named: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
            throw ExternalAgentError.invalidResponse
        }
        try await parser.complete()
        _ = try await checked(connection)
        try Task.checkCancellation()
    }
    private func models(endpoint: URL, token: String) async throws -> [String] {
        let response = try await http.send(.init(method: .get, url: endpoint.appendingPathComponent("models"),
            headers: ["Authorization": "Bearer " + token, "Accept": "application/json"], timeout: 20))
        try Task.checkCancellation()
        switch response.statusCode {
        case 200..<300: break
        case 401: throw AIProviderError.invalidCredential
        case 403: throw AIProviderError.insufficientPermission
        case 429: throw AIProviderError.rateLimited(retryAfterSeconds: nil)
        default: throw ExternalAgentError.unavailable
        }
        guard response.body.count <= 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let rows = object["data"] as? [[String: Any]], rows.count <= 1024 else { throw ExternalAgentError.invalidResponse }
        var seen = Set<String>()
        let targets = rows.compactMap { $0["id"] as? String }.filter {
            ExternalAgentEndpoint.validTarget($0) && seen.insert($0).inserted
        }.prefix(128).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !targets.isEmpty else { throw ExternalAgentError.invalidResponse }
        return targets
    }
    private func checked(_ connection: ExternalAgentConnection) async throws -> Record {
        try Task.checkCancellation()
        guard mutations[connection.kind] == nil, let saved = try await record(connection.kind),
              mutations[connection.kind] == nil, saved.connection == connection else { throw ExternalAgentError.changed }
        return saved
    }
    private func record(_ kind: ExternalAgentKind) async throws -> Record? {
        do {
            guard let data = try await store.read(Self.key(kind)) else { return nil }
            guard data.count <= 64 * 1024 else { throw ExternalAgentError.storage }
            let record = try JSONDecoder().decode(Record.self, from: data)
            let connection = record.connection
            guard connection.kind == kind, ExternalAgentEndpoint.validToken(record.token),
                  try ExternalAgentEndpoint.parse(connection.endpoint.absoluteString) == connection.endpoint,
                  !connection.targets.isEmpty, connection.targets.count <= 128,
                  connection.targets.allSatisfy({ ExternalAgentEndpoint.validTarget($0) }) else { throw ExternalAgentError.storage }
            return record
        } catch is CancellationError { throw CancellationError() }
        catch { throw ExternalAgentError.storage }
    }
    private static func key(_ kind: ExternalAgentKind) -> SecureStoreKey {
        .init(rawValue: "external.agent." + kind.rawValue + ".v1")
    }
}

/// Explicit endpoints are never redirected, including to another path on the same host.
final class ExternalAgentRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
