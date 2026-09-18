import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

struct SlackEmojiServiceTests {
    @Test func connectsEmojiOnlyBotAndUsesBearerPOSTWithoutSearchQueries() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let storage = InMemorySecureStore(); let credentials = SlackEmojiCredentialStore(secureStore: storage)
        let service = SlackEmojiService(credentials: credentials, transport: transport)
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil)
        #expect(workspace.id == "TFIXTURE"); #expect(workspace.botID == "BFIXTURE")
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/api/auth.test", "/api/emoji.list"])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.query == nil && $0.url?.host == "slack.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer xoxb-generated-token" })
        let reloaded = SlackEmojiCredentialStore(secureStore: storage)
        #expect(try await reloaded.workspaces() == [workspace])
        #expect(try await reloaded.token(for: workspace) == "xoxb-generated-token")
    }
    @Test(arguments: [nil, "emoji:read,chat:write", "channels:read"]) func scopeFailuresNeverSaveTheToken(scope: String?) async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(scopes: scope)])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let expected: SlackEmojiError = scope == nil ? .unverifiedScopes : scope == "channels:read" ? .missingScope : .excessiveScopes
        await #expect(throws: expected) { try await service.connect(token: "xoxb-generated-token", replacing: nil) }
        #expect(try await service.connections().isEmpty); #expect(await transport.requests.count == 1)
    }
    @Test func aliasMediaUsesValidatedRedirectsWithoutTokenAndReleaseRejectsOldCatalog() async throws {
        let redirect = SlackEmojiHTTPResponse(data: Data(), status: 302, contentType: nil, scopes: nil, retryAfter: nil, location: "https://emoji.slack-edge.com/TFIXTURE/circle/redirected.png?signature=generated")
        let bytes = try await GeneratedSlackEmojiMedia().make(animated: false)
        let media = SlackEmojiHTTPResponse(data: bytes, status: 200, contentType: "image/png", scopes: nil, retryAfter: nil, location: nil)
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), redirect, media])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil)
        let catalog = try await service.refresh(workspace)
        let matches = try await service.search("wave", catalog: catalog); let item = try #require(matches.items.first)
        #expect(try await service.media(item, catalog: catalog) == bytes)
        let requests = await transport.requests
        #expect(requests.count == 6)
        #expect(requests.suffix(2).allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        #expect(requests.last?.url?.query == "signature=generated")
        await service.release(catalog)
        await #expect(throws: SlackEmojiError.changedConnection) { try await service.media(item, catalog: catalog) }
        #expect(await transport.requests.count == 6)
    }
    @Test func foreignMediaRedirectNeverReceivesARequestAndRateLimitPreventsImmediateRetry() async throws {
        let foreign = SlackEmojiHTTPResponse(data: Data(), status: 307, contentType: nil, scopes: nil, retryAfter: nil, location: "https://other.invalid/image.png")
        let rate = SlackEmojiHTTPResponse(data: Data(), status: 429, contentType: nil, scopes: nil, retryAfter: 123, location: nil)
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), foreign, rate])
        let fixed = Date(timeIntervalSince1970: 1_900_000_000)
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport, now: { fixed })
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil)
        let catalog = try await service.refresh(workspace)
        let result = try await service.search("circle", catalog: catalog); let item = try #require(result.items.first)
        await #expect(throws: SlackEmojiError.unsafeURL) { try await service.media(item, catalog: catalog) }
        await #expect(throws: SlackEmojiError.rateLimited(seconds: 123)) { try await service.media(item, catalog: catalog) }
        await #expect(throws: SlackEmojiError.rateLimited(seconds: 123)) { try await service.media(item, catalog: catalog) }
        #expect(await transport.requests.count == 6)
    }
    @Test func disconnectCancelsAndRejectsALateMediaResponse() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil); let catalog = try await service.refresh(workspace)
        let found = try await service.search("circle", catalog: catalog); let item = try #require(found.items.first)
        let pending = Task { try await service.media(item, catalog: catalog) }; await transport.waitForSuspension()
        try await service.disconnect(workspace)
        await transport.complete(.init(data: Data("late generated bytes".utf8), status: 200, contentType: "image/png", scopes: nil, retryAfter: nil, location: nil))
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await service.connections().isEmpty)
    }
    @Test func forgedResultAndDifferentWorkspaceReplacementAreRejected() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog(), try SlackEmojiTestData.auth(teamID: "TOTHER")])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil); let catalog = try await service.refresh(workspace)
        let forged = SlackCustomEmoji(name: "unlisted", resolution: .image(url: try #require(URL(string: "https://emoji.slack-edge.com/TFIXTURE/unlisted/image.png")), canonicalName: "unlisted", aliasChain: []))
        await #expect(throws: SlackEmojiError.changedConnection) { try await service.media(forged, catalog: catalog) }
        await #expect(throws: SlackEmojiError.identityChanged) { try await service.connect(token: "xoxb-generated-other", replacing: workspace) }
        #expect(try await service.connections() == [workspace])
    }
    @Test(arguments: ["host", "enterprise", "removed-enterprise", "team", "bot"])
    func changedWorkspaceHostOrEnterpriseMembershipCannotReuseSavedMediaAuthority(change: String) async throws {
        let refreshed = try SlackEmojiTestData.auth(
            teamID: change == "team" ? "TOTHER" : "TFIXTURE",
            workspaceURL: change == "host" ? "https://renamed.slack.com/" : "https://fixture.slack.com/",
            enterpriseID: change == "removed-enterprise" ? nil : change == "enterprise" ? "ENEW" : "EOLD",
            botID: change == "bot" ? "BOTHER" : "BFIXTURE"
        )
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(enterpriseID: "EOLD"), try SlackEmojiTestData.responseCatalog(),
                                                refreshed])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let workspace = try await service.connect(token: "xoxb-generated-token", replacing: nil)
        await #expect(throws: SlackEmojiError.identityChanged) { try await service.refresh(workspace) }
        #expect(await transport.requests.count == 3) // No emoji-list or media request under stale authority.
        #expect(try await service.connections() == [workspace])
    }
    @Test func cancelledPrecommitConnectionCheckNeverWritesAToken() async throws {
        let transport = SlackEmojiTestTransport([])
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: InMemorySecureStore()), transport: transport)
        let operation = Task { try await service.connect(token: "xoxb-generated-token", replacing: nil) }
        await transport.waitForSuspension(); operation.cancel()
        await transport.complete(try SlackEmojiTestData.auth())
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try await service.connections().isEmpty); #expect(await transport.requests.count == 1)
    }
}
actor SlackEmojiTestTransport {
    private var responses: [SlackEmojiHTTPResponse]
    private(set) var requests: [URLRequest] = []
    private var suspended: CheckedContinuation<SlackEmojiHTTPResponse, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ responses: [SlackEmojiHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SlackEmojiHTTPResponse {
        requests.append(request)
        if !responses.isEmpty { return responses.removeFirst() }
        waiters.forEach { $0.resume() }; waiters = []
        return await withCheckedContinuation { suspended = $0 }
    }
    func waitForSuspension() async { if suspended == nil { await withCheckedContinuation { waiters.append($0) } } }
    func complete(_ response: SlackEmojiHTTPResponse) { suspended?.resume(returning: response); suspended = nil }
}
extension SlackEmojiTestTransport: SlackEmojiHTTPTransporting {}
extension SlackEmojiTestData {
    static func auth(scopes: String? = "emoji:read", teamID: String = "TFIXTURE", workspaceURL: String = "https://fixture.slack.com/", enterpriseID: String? = nil, botID: String = "BFIXTURE") throws -> SlackEmojiHTTPResponse {
        var value: [String: Any] = ["ok": true, "team_id": teamID, "team": "Generated Workspace", "url": workspaceURL, "bot_id": botID]
        if let enterpriseID { value["enterprise_id"] = enterpriseID }
        return .init(data: try JSONSerialization.data(withJSONObject: value), status: 200, contentType: "application/json", scopes: scopes, retryAfter: nil, location: nil)
    }
    static func responseCatalog() throws -> SlackEmojiHTTPResponse {
        .init(data: try catalog(["circle": "https://emoji.slack-edge.com/TFIXTURE/circle/generated.png", "wave": "alias:circle"]),
              status: 200, contentType: "application/json", scopes: "emoji:read", retryAfter: nil, location: nil)
    }
}
