import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

struct NotionWorkspaceTests {
    @Test func parsesPageTitlesNestedBlocksAndPagination() throws {
        let data = Data("""
        {"object":"list","has_more":true,"next_cursor":"next-page","results":[
          {"object":"page","id":"11111111-1111-4111-8111-111111111111","properties":{"Name":{"type":"title","title":[{"plain_text":"Planning"}]}}},
          {"object":"block","id":"22222222-2222-4222-8222-222222222222","type":"to_do","has_children":true,"to_do":{"checked":true,"rich_text":[{"plain_text":"Ship the feature"}]}}
        ]}
        """.utf8)
        let page = try NotionWorkspaceParser.page(data)
        #expect(page.items.map(\.title) == ["Planning", "☑ Ship the feature"])
        #expect(page.items.allSatisfy { $0.hasChildren })
        #expect(page.nextCursor == "next-page")
        #expect(page.items.first?.webURL?.host == "www.notion.so")
        #expect(throws: NotionWorkspaceError.self) {
            try NotionWorkspaceParser.page(Data("{\"object\":\"list\",\"has_more\":true,\"results\":[]}".utf8))
        }
    }
    @Test func verifiesBeforeSavingAndUsesOnlyFixedNotionEndpoints() async throws {
        let http = NotionTestHTTP()
        let store = InMemorySecureStore()
        let service = NotionWorkspaceService(store: store, http: http)
        #expect(try await service.connection() == nil)
        let connection = try await service.connect(token: "ntn_generated_test_token")
        #expect(try await service.connection() == connection)
        _ = try await service.search("launch plan", cursor: "cursor with spaces", connection: connection)
        let requests = await http.requests
        #expect(requests.map { $0.url?.host } == ["api.notion.com", "api.notion.com", "api.notion.com"])
        #expect(requests.map { $0.url?.path } == ["/v1/users/me", "/v1/search", "/v1/search"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Notion-Version") == "2025-09-03" })
        let searchBody = try #require(requests.last?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: searchBody) as? [String: Any])
        #expect(json["query"] as? String == "launch plan"); #expect(json["start_cursor"] as? String == "cursor with spaces")
        try await service.disconnect()
        await #expect(throws: NotionWorkspaceError.self) { try await service.search("", cursor: nil, connection: connection) }
        #expect(await http.requests.count == 3)
    }
    @Test @MainActor func registryIncludesNotionApplicationAndTool() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        #expect(registry.isLaunchableCommand(NotionWorkspaceApplication.id))
        #expect(registry.isLaunchableCommand(NotionWorkspaceApplication.searchID))
    }
}
private actor NotionTestHTTP: NotionHTTPTransporting {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) throws -> NotionHTTPResponse {
        requests.append(request)
        let text = request.url?.path == "/v1/users/me"
            ? "{\"id\":\"11111111-1111-4111-8111-111111111111\",\"type\":\"bot\",\"bot\":{\"workspace_name\":\"Generated Workspace\"}}"
            : "{\"object\":\"list\",\"results\":[],\"has_more\":false,\"next_cursor\":null}"
        return .init(data: Data(text.utf8), status: 200, retryAfter: nil)
    }
}
