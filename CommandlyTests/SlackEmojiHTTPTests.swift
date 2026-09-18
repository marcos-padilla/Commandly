import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct SlackEmojiHTTPTests {
    @Test func nativeTransportBoundsBodiesAndPreservesOnlyNeededResponseMetadata() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SlackEmojiHTTPFixture.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let transport = SlackEmojiHTTPTransport(session: session)
        let response = try await transport.send(request("ok"), maximumBytes: 8)
        #expect(response.data == Data("fixture".utf8)); #expect(response.scopes == "emoji:read")
        let rate = try await transport.send(request("rate"), maximumBytes: 8)
        #expect(rate.status == 429); #expect(rate.retryAfter == 45); #expect(rate.data.isEmpty)
        let redirect = try await transport.send(request("redirect"), maximumBytes: 8)
        #expect(redirect.status == 302); #expect(redirect.location == "https://other-fixture.invalid/image.png")
        await #expect(throws: SlackEmojiError.responseTooLarge) { try await transport.send(request("declared"), maximumBytes: 8) }
        await #expect(throws: SlackEmojiError.responseTooLarge) { try await transport.send(request("actual"), maximumBytes: 8) }
    }
    @Test func nativeSessionDelegateNeverAutomaticallyForwardsCredentialedRedirect() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [SlackEmojiHTTPFixture.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        var original = try request("ok"); original.setValue("Bearer xoxb-generated-test", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: original); defer { task.cancel() } // Not resumed: no request is made.
        let url = try #require(original.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: nil))
        let redirected = URLRequest(url: try #require(URL(string: "https://emoji.slack-edge.com/TFIXTURE/circle/image.png")))
        let decision: URLRequest? = await withCheckedContinuation { continuation in
            SlackEmojiNoRedirectDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { continuation.resume(returning: $0) }
        }
        #expect(decision == nil)
    }
    private func request(_ mode: String) throws -> URLRequest { URLRequest(url: try #require(URL(string: "https://slack-emoji-fixture.invalid/" + mode))) }
}
nonisolated private final class SlackEmojiHTTPFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "slack-emoji-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: SlackEmojiError.invalidResponse); return }
        let mode = url.lastPathComponent; let status = mode == "rate" ? 429 : mode == "redirect" ? 302 : 200
        var headers = ["Content-Type": "application/json", "X-OAuth-Scopes": "emoji:read"]
        if mode == "rate" { headers["Retry-After"] = "45" }
        if mode == "redirect" { headers["Location"] = "https://other-fixture.invalid/image.png" }
        if mode == "declared" { headers["Content-Length"] = "9000" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { client?.urlProtocol(self, didFailWithError: SlackEmojiError.invalidResponse); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((mode == "actual" ? "generated data exceeding limit" : "fixture").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
