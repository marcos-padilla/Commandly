import Foundation
import Infrastructure
import SecurityKit

actor NotionWorkspaceService: NotionWorkspaceServing {
    private struct Record: Codable, Sendable { let connection: NotionWorkspaceConnection; let token: String }
    private let store: any SecureStoring
    private let http: any NotionHTTPTransporting
    private let key = SecureStoreKey(rawValue: "notion.workspace.connection.v1")
    private var mutation: Task<NotionWorkspaceConnection?, Error>?
    private var retryAt: Date?
    init(store: any SecureStoring, http: any NotionHTTPTransporting = NotionHTTPTransport()) { self.store = store; self.http = http }

    func connection() async throws -> NotionWorkspaceConnection? {
        if let mutation {
            // Closing a sheet cannot hide a secure write that already committed. New sessions
            // await the shared mutation, then read actual storage even if that operation failed.
            let outcome = await mutation.result
            if case .failure(let error) = outcome, Task.isCancelled { throw error }
        }
        try Task.checkCancellation()
        return try await record()?.connection
    }
    func connect(token: String) async throws -> NotionWorkspaceConnection {
        guard mutation == nil else { throw NotionWorkspaceError.busy }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validToken(token) else { throw NotionWorkspaceError.invalidToken }
        let operation = Task<NotionWorkspaceConnection?, Error> { [store, key] in
            let data = try await self.request(path: "users/me", token: token)
            let identity = try NotionWorkspaceParser.identity(data)
            // The read-only search also proves the configured integration can read shared content.
            _ = try NotionWorkspaceParser.page(await self.request(path: "search", token: token, body: ["page_size": 1]))
            try Task.checkCancellation()
            let dataToSave = try JSONEncoder().encode(Record(connection: identity, token: token))
            do { try await store.write(key, value: dataToSave) } catch { throw NotionWorkspaceError.storage }
            return identity
        }
        mutation = operation; defer { mutation = nil }
        let result = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
        guard let result else { throw NotionWorkspaceError.storage }; return result
    }
    func disconnect() async throws {
        guard mutation == nil else { throw NotionWorkspaceError.busy }
        let operation = Task<NotionWorkspaceConnection?, Error> { [store, key] in
            try Task.checkCancellation()
            do { try await store.delete(key) } catch { throw NotionWorkspaceError.storage }
            return nil
        }
        mutation = operation; defer { mutation = nil }
        _ = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }
    func search(_ query: String, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage {
        guard query.utf8.count <= 512 else { throw NotionWorkspaceError.tooLarge }
        var body: [String: Any] = ["page_size": 100, "sort": ["direction": "descending", "timestamp": "last_edited_time"]]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["query"] = query }
        if let cursor { try validateCursor(cursor); body["start_cursor"] = cursor }
        return try await page(path: "search", body: body, connection: connection)
    }
    func children(of item: NotionWorkspaceItem, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage {
        if let cursor { try validateCursor(cursor) }
        let id = item.id.uuidString.lowercased()
        switch item.kind {
        case .dataSource:
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            return try await page(path: "data_sources/\(id)/query", body: body, connection: connection)
        case .database:
            let saved = try await checked(connection)
            let data = try await request(path: "databases/\(id)", token: saved.token)
            _ = try await checked(connection)
            return try NotionWorkspaceParser.database(data)
        case .page, .block:
            let saved = try await checked(connection)
            var parameters = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { parameters.append(.init(name: "start_cursor", value: cursor)) }
            let data = try await request(path: "blocks/\(id)/children", token: saved.token, query: parameters)
            _ = try await checked(connection)
            return try NotionWorkspaceParser.page(data)
        }
    }
    private func page(path: String, body: [String: Any], connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage {
        let saved = try await checked(connection)
        let data = try await request(path: path, token: saved.token, body: body)
        _ = try await checked(connection)
        return try NotionWorkspaceParser.page(data)
    }
    private func checked(_ connection: NotionWorkspaceConnection) async throws -> Record {
        try Task.checkCancellation()
        guard mutation == nil, let saved = try await record(), mutation == nil, saved.connection == connection else { throw NotionWorkspaceError.changed }
        return saved
    }
    private func record() async throws -> Record? {
        do {
            guard let data = try await store.read(key) else { return nil }
            guard data.count <= 8192 else { throw NotionWorkspaceError.storage }
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard Self.validToken(record.token), !record.connection.name.isEmpty, record.connection.name.utf8.count <= 512 else { throw NotionWorkspaceError.storage }
            return record
        } catch is CancellationError { throw CancellationError() }
        catch { throw NotionWorkspaceError.storage }
    }
    private func request(path: String, token: String, body: [String: Any]? = nil, query: [URLQueryItem] = []) async throws -> Data {
        try Task.checkCancellation()
        if let retryAt, retryAt > Date() { throw NotionWorkspaceError.rateLimited(max(1, Int(ceil(retryAt.timeIntervalSinceNow)))) }
        var components = URLComponents()
        components.scheme = "https"; components.host = "api.notion.com"; components.path = "/v1/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw NotionWorkspaceError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try await http.send(request)
        try Task.checkCancellation()
        switch response.status {
        case 200: return response.data
        case 401, 403: throw NotionWorkspaceError.denied
        case 404: throw NotionWorkspaceError.notShared
        case 429:
            let seconds = min(3600, max(1, response.retryAfter ?? 60))
            retryAt = Date().addingTimeInterval(TimeInterval(seconds)); throw NotionWorkspaceError.rateLimited(seconds)
        default: throw NotionWorkspaceError.unavailable
        }
    }
    private func validateCursor(_ cursor: String) throws {
        guard !cursor.isEmpty, cursor.utf8.count <= 2048 else { throw NotionWorkspaceError.invalidResponse }
    }
    private static func validToken(_ token: String) -> Bool {
        (16...4096).contains(token.utf8.count) && token.utf8.allSatisfy { (33...126).contains($0) }
    }
}
