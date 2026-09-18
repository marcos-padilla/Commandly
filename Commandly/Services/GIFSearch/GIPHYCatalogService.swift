import Foundation
import Infrastructure

actor GIPHYCatalogService {
    private let credentials: GIPHYCredentialStore
    private let transport: any GIFHTTPTransporting
    private var connectionEpoch = UUID()
    private var changingConnection = false
    private var requests: [UUID: Task<Data, Error>] = [:]
    init(credentials: GIPHYCredentialStore, transport: any GIFHTTPTransporting = GIPHYHTTPTransport()) { self.credentials = credentials; self.transport = transport }
    func connection() async throws -> GIFConnectionState { try await credentials.state() }
    func configure(key: String) async throws -> GIFConnectionState {
        guard !changingConnection else { throw GIFSearchError.changedConnection }
        changingConnection = true; connectionEpoch = UUID(); cancelRequests()
        defer { changingConnection = false }
        return try await credentials.configure(key)
    }
    func disconnect() async throws -> GIFConnectionState {
        guard !changingConnection else { throw GIFSearchError.changedConnection }
        changingConnection = true; connectionEpoch = UUID(); cancelRequests()
        defer { changingConnection = false }
        return try await credentials.disconnect()
    }
    private func cancelRequests() { requests.values.forEach { $0.cancel() }; requests = [:] }
    func search(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, connection: UUID) async throws -> GIFCatalogPage {
        guard !changingConnection else { throw GIFSearchError.changedConnection }
        let epoch = connectionEpoch
        let key = try await credentials.key(matching: connection)
        guard !changingConnection, connectionEpoch == epoch else { throw GIFSearchError.changedConnection }
        let request = try Self.request(query, rating: rating, offset: offset, key: key)
        let data = try await fetch(request, maximum: 2 * 1_024 * 1_024, types: ["application/json"], revision: connection)
        return try Self.parse(data, query: query, offset: offset)
    }
    func media(_ item: GIFCatalogItem, original: Bool, connection: UUID) async throws -> Data {
        guard let url = original ? item.originalURL : item.previewURL, GIPHYURLPolicy.media(url) else { throw GIFSearchError.unsafeURL }
        guard !changingConnection else { throw GIFSearchError.changedConnection }
        let epoch = connectionEpoch
        _ = try await credentials.key(matching: connection)
        guard !changingConnection, connectionEpoch == epoch else { throw GIFSearchError.changedConnection }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("image/gif", forHTTPHeaderField: "Accept")
        return try await fetch(request, maximum: (original ? 32 : 8) * 1_024 * 1_024, types: ["image/gif", "application/octet-stream"], revision: connection)
    }
    private func fetch(_ request: URLRequest, maximum: Int, types: Set<String>, revision: UUID) async throws -> Data {
        let id = UUID(); let task = Task { [transport] in
            try Task.checkCancellation()
            let data = try await transport.get(request, maximumBytes: maximum, allowedContentTypes: types)
            try Task.checkCancellation(); return data
        }
        requests[id] = task
        defer { requests[id] = nil }
        return try await withTaskCancellationHandler {
            let data = try await task.value; try Task.checkCancellation()
            _ = try await credentials.key(matching: revision)
            return data
        } onCancel: { task.cancel() }
    }
    static func request(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, key: String) throws -> URLRequest {
        var components = URLComponents(); components.scheme = "https"; components.host = "api.giphy.com"
        var values = [URLQueryItem(name: "api_key", value: key), .init(name: "limit", value: "24"), .init(name: "offset", value: String(offset)), .init(name: "rating", value: rating.rawValue)]
        switch query {
        case .search(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GIFSearchError.invalidRequest }
            guard text.count <= 50, text.utf8.count <= 400 else { throw GIFSearchError.queryTooLong }
            guard (0...4_999).contains(offset) else { throw GIFSearchError.invalidRequest }
            components.path = "/v1/gifs/search"; values.append(.init(name: "q", value: text))
        case .trending:
            guard (0...499).contains(offset) else { throw GIFSearchError.invalidRequest }
            components.path = "/v1/gifs/trending"
        }
        values.append(.init(name: "fields", value: "id,title,alt_text,username,user.display_name,source,source_tld,url,images.fixed_width,images.original"))
        components.queryItems = values
        guard let url = components.url else { throw GIFSearchError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    static func parse(_ data: Data, query: GIFCatalogQuery, offset: Int) throws -> GIFCatalogPage {
        guard data.count <= 2 * 1_024 * 1_024 else { throw GIFSearchError.responseTooLarge }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw GIFSearchError.invalidResponse }
        guard response.meta.status == 200, response.data.count <= 24,
              response.pagination.offset == offset, response.pagination.count == response.data.count,
              response.pagination.total_count >= 0, Set(response.data.map(\.id)).count == response.data.count else { throw GIFSearchError.invalidResponse }
        let items = try response.data.map { value -> GIFCatalogItem in
            guard !value.id.isEmpty, value.id.utf8.count <= 128 else { throw GIFSearchError.invalidResponse }
            let title = bounded(value.title, maximum: 300) ?? "Untitled GIF"
            let page = value.url.flatMap(URL.init(string:)).flatMap { GIPHYURLPolicy.page($0) ? $0 : nil }
            let source = value.source.flatMap(URL.init(string:)).flatMap { GIPHYURLPolicy.externalSource($0) ? $0 : nil }
            func media(_ text: String?) -> URL? { text.flatMap(URL.init(string:)).flatMap { GIPHYURLPolicy.media($0) ? $0 : nil } }
            return .init(id: value.id, title: title, accessibilityText: bounded(value.alt_text, maximum: 1_024) ?? title,
                         creator: bounded(value.user?.display_name, maximum: 200) ?? bounded(value.username, maximum: 200),
                         sourceName: bounded(value.source_tld, maximum: 200) ?? source?.host,
                         pageURL: page, sourceURL: source, previewURL: media(value.images.fixed_width?.url), originalURL: media(value.images.original?.url))
        }
        let end = offset + items.count
        let maximum = query == .trending ? 499 : 4_999
        let next = !items.isEmpty && end < response.pagination.total_count && end <= maximum ? end : nil
        return .init(items: items, nextOffset: next)
    }
    private static func bounded(_ value: String?, maximum: Int) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(value.prefix(maximum))
    }
    private struct Response: Decodable { let data: [Item]; let meta: Meta; let pagination: Pagination }
    private struct Meta: Decodable { let status: Int }
    private struct Pagination: Decodable { let offset: Int; let count: Int; let total_count: Int }
    private struct Item: Decodable {
        let id: String; let title: String?; let alt_text: String?; let username: String?; let user: User?
        let source: String?; let source_tld: String?; let url: String?; let images: Images
    }
    private struct User: Decodable { let display_name: String? }
    private struct Images: Decodable { let fixed_width: Rendition?; let original: Rendition? }
    private struct Rendition: Decodable { let url: String? }
}
extension GIPHYCatalogService: GIFCatalogServing {}
