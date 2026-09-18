import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct GIFHTTPTransportTests {
    @Test func nativeRedirectDelegateRefusesSameAndDifferentProviderTargets() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [GIFHTTPProtocolFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let original = try request("ok"); let task = session.dataTask(with: original)
        defer { task.cancel() } // Never resumed; direct delegate callback makes no request.
        let originalURL = try #require(original.url)
        let response = try #require(HTTPURLResponse(url: originalURL, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: nil))
        let delegate = GIFNoRedirectDelegate()
        for text in ["https://api.giphy.com/v1/gifs/search?api_key=generated-fixture-key", "https://other-fixture.invalid/redirect"] {
            let destination = URLRequest(url: try #require(URL(string: text)))
            let decision: URLRequest? = await withCheckedContinuation { continuation in
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: destination) {
                    continuation.resume(returning: $0)
                }
            }
            #expect(decision == nil)
        }
    }
    @Test func boundedHTTPChecksStatusMIMEDeclaredAndActualLength() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [GIFHTTPProtocolFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = GIPHYHTTPTransport(session: session)
        let data = try await transport.get(request("ok"), maximumBytes: 8, allowedContentTypes: ["image/gif"])
        #expect(data == Data("GIFDATA".utf8))
        await #expect(throws: GIFSearchError.rateLimited) { try await transport.get(request("rate"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
        await #expect(throws: GIFSearchError.unauthorized) { try await transport.get(request("key"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
        await #expect(throws: GIFSearchError.invalidResponse) { try await transport.get(request("html"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
        await #expect(throws: GIFSearchError.responseTooLarge) { try await transport.get(request("declared"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
        await #expect(throws: GIFSearchError.responseTooLarge) { try await transport.get(request("actual"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
        await #expect(throws: GIFSearchError.unsafeURL) { try await transport.get(request("redirect"), maximumBytes: 8, allowedContentTypes: ["image/gif"]) }
    }
    private func request(_ mode: String) throws -> URLRequest {
        URLRequest(url: try #require(URL(string: "https://gif-fixture.invalid/" + mode)))
    }
}
/// Immutable local URLProtocol cases; no global handlers, keys, network, or mutable static state.
nonisolated private final class GIFHTTPProtocolFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "gif-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: GIFSearchError.invalidRequest); return }
        let mode = url.lastPathComponent
        let status = mode == "rate" ? 429 : mode == "key" ? 403 : mode == "redirect" ? 302 : 200
        var headers = ["Content-Type": mode == "html" ? "text/html" : "image/gif"]
        if mode == "declared" { headers["Content-Length"] = "99" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: GIFSearchError.invalidResponse); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((mode == "actual" ? "GIFDATA-TOO-LARGE" : "GIFDATA").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
