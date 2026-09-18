import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

struct GIFCatalogTests {
    @Test func exactQueryEncodingPreservesSpecialCharactersAndOnlySendsRequiredData() throws {
        let text = "  café & cats @creator + hugs  "
        let request = try GIPHYCatalogService.request(.search(text), rating: .pg, offset: 24, key: "generated-test-key")
        let url = try #require(request.url); let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.giphy.com"); #expect(url.path == "/v1/gifs/search")
        #expect(values["q"] == text); #expect(values["api_key"] == "generated-test-key")
        #expect(values["limit"] == "24"); #expect(values["rating"] == "pg"); #expect(values["offset"] == "24")
        #expect(values["customer_id"] == nil); #expect(values["random_id"] == nil)
        #expect(throws: GIFSearchError.queryTooLong) { _ = try GIPHYCatalogService.request(.search(String(repeating: "x", count: 51)), rating: .g, offset: 0, key: "generated") }
        #expect(throws: GIFSearchError.invalidRequest) { _ = try GIPHYCatalogService.request(.trending, rating: .g, offset: 500, key: "generated") }
    }
    @Test func parsePreservesProviderOrderAttributionAndUnmodifiedMediaQueries() throws {
        let body = try response(items: [item(id: "second", title: "Second by provider", media: "https://media2.giphy.com/media/second/giphy.gif?cid=provided&rid=giphy.gif"), item(id: "first", title: "First alphabetically", media: "https://media.giphy.com/media/first/giphy.gif")], total: 3)
        let page = try GIPHYCatalogService.parse(body, query: .search("fixture"), offset: 0)
        #expect(page.items.map(\.id) == ["second", "first"])
        #expect(page.items.first?.originalURL?.query == "cid=provided&rid=giphy.gif")
        #expect(page.items.first?.creator == "Generated Creator"); #expect(page.nextOffset == 2)
        let unsafe = try response(items: [item(id: "unsafe", title: "Remains in place", media: "https://attacker.invalid/asset.gif")])
        let unavailable = try GIPHYCatalogService.parse(unsafe, query: .trending, offset: 0)
        #expect(unavailable.items.count == 1); #expect(unavailable.items.first?.originalURL == nil)
    }
    @Test func rejectsDuplicateIDsAndPaginationMismatchRatherThanReordering() throws {
        let duplicate = try response(items: [item(id: "same"), item(id: "same")])
        #expect(throws: GIFSearchError.invalidResponse) { _ = try GIPHYCatalogService.parse(duplicate, query: .trending, offset: 0) }
        let normal = try response(items: [item(id: "one")])
        #expect(throws: GIFSearchError.invalidResponse) { _ = try GIPHYCatalogService.parse(normal, query: .trending, offset: 24) }
    }
    @Test(arguments: ["http://media.giphy.com/a.gif", "https://media.giphy.com.attacker.invalid/a.gif", "https://user:pass@media.giphy.com/a.gif", "https://media.giphy.com:444/a.gif", "https://api.giphy.com/a.gif", "https://media.giphy.com/a.mp4", "https://media.giphy.com/a.gif#fragment"])
    func mediaPolicyRejectsUnsafeURLs(_ text: String) throws { #expect(!GIPHYURLPolicy.media(try #require(URL(string: text)))) }
    @Test func connectionStorePersistsOnlyInInjectedSecureStoreAndChangesRevision() async throws {
        let secure = InMemorySecureStore(); let credentials = GIPHYCredentialStore(secureStore: secure)
        let initial = try await credentials.state(); #expect(!initial.isConfigured)
        let configured = try await credentials.configure(" generated-key ")
        #expect(configured.isConfigured); #expect(configured.revision != initial.revision)
        #expect(try await credentials.key(matching: configured.revision) == "generated-key")
        let reloaded = GIPHYCredentialStore(secureStore: secure)
        async let firstRead = reloaded.state(); async let secondRead = reloaded.state()
        let states = try await (firstRead, secondRead)
        #expect(states.0 == configured); #expect(states.1 == configured)
        let replacement = try await credentials.configure("replacement-key")
        await #expect(throws: GIFSearchError.changedConnection) { _ = try await credentials.key(matching: configured.revision) }
        let disconnected = try await credentials.disconnect(); #expect(!disconnected.isConfigured)
        await #expect(throws: GIFSearchError.changedConnection) { _ = try await credentials.key(matching: replacement.revision) }
        #expect(try await secure.read(SecureStoreKey(rawValue: "gif-search.giphy.api-key.v1")) == nil)
    }
    @Test func configuredStatusDoesNotRequestProviderAndDisconnectRejectsLateTransportBytes() async throws {
        let credentials = GIPHYCredentialStore(secureStore: InMemorySecureStore())
        let transport = ControlledGIFTransport()
        let service = GIPHYCatalogService(credentials: credentials, transport: transport)
        let state = try await service.configure(key: "generated-key")
        _ = try await service.connection(); #expect(await transport.requests.isEmpty)
        let task = Task { try await service.search(.search("hello"), rating: .g, offset: 0, connection: state.revision) }
        await transport.waitForRequest()
        _ = try await service.disconnect()
        await transport.complete(try response(items: [item(id: "late")]))
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
    private func item(id: String, title: String = "Generated fixture", media: String = "https://media.giphy.com/media/generated/giphy.gif") -> [String: Any] {
        ["id": id, "title": title, "url": "https://giphy.com/gifs/" + id, "username": "generated", "user": ["display_name": "Generated Creator"],
         "source": "https://example.com/source", "source_tld": "example.com", "images": ["original": ["url": media], "fixed_width": ["url": media]]]
    }
    private func response(items: [[String: Any]], total: Int? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": items, "meta": ["status": 200], "pagination": ["offset": 0, "count": items.count, "total_count": total ?? items.count]])
    }
}
actor ControlledGIFTransport {
    private(set) var requests: [URLRequest] = []
    private var pending: CheckedContinuation<Data, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func get(_ request: URLRequest, maximumBytes: Int, allowedContentTypes: Set<String>) async -> Data {
        requests.append(request); waiters.forEach { $0.resume() }; waiters = []
        return await withCheckedContinuation { pending = $0 }
    }
    func waitForRequest() async { if pending == nil { await withCheckedContinuation { waiters.append($0) } } }
    func complete(_ data: Data) { pending?.resume(returning: data); pending = nil }
}
extension ControlledGIFTransport: GIFHTTPTransporting {}
