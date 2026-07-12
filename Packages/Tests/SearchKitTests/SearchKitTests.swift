import Foundation
import Testing
@testable import SearchKit

struct SearchKitTests {
    @Test func searchQueryTrimsWhitespace() {
        let query = SearchQuery(text: "  launch notes  ", limit: 10)
        #expect(query.text == "launch notes")
        #expect(query.limit == 10)
        #expect(query.isEmpty == false)
    }

    @Test func emptySearchQuery() {
        let query = SearchQuery(text: "   ")
        #expect(query.isEmpty)
    }

    @Test func searchResultHoldsItems() {
        let query = SearchQuery(text: "test")
        let item = SearchItem(
            id: "1",
            title: "Test Item",
            providerID: SearchProviderID(rawValue: "stub"),
            score: 1.0
        )
        let result = SearchResult(query: query, items: [item])
        #expect(result.items.count == 1)
        #expect(result.isComplete)
    }

    @Test func searchMatchScorerRanksPrefixAboveContains() {
        #expect(SearchMatchScorer.score(query: "set", title: "Settings") == SearchMatchScorer.titlePrefix)
        #expect(SearchMatchScorer.score(query: "ting", title: "Settings") == SearchMatchScorer.titleContains)
        #expect(SearchMatchScorer.score(query: "zzz", title: "Settings") == nil)
        #expect(SearchMatchScorer.score(query: "", title: "Settings") == SearchMatchScorer.emptyQueryBaseline)
    }

    @Test func searchMatchScorerUsesKeywords() {
        let score = SearchMatchScorer.score(
            query: "pref",
            title: "Open Settings",
            keywords: ["preferences"]
        )
        #expect(score == SearchMatchScorer.keywordPrefix)
    }

    @Test func fileSearchCategoriesHaveStableTitles() {
        #expect(FileSearchCategory.all.title == "All Files")
        #expect(FileSearchCategory.sourceCode.title == "Source Code")
        #expect(Set(FileSearchCategory.allCases.map(\.id)).count == FileSearchCategory.allCases.count)
    }

    @Test func inMemoryFileSearchRecordsAndLimitsRequests() async throws {
        let items = (0..<3).map { index in
            FileSearchItem(
                url: URL(fileURLWithPath: "/tmp/file-\(index).txt"),
                name: "file-\(index).txt",
                parentPath: "/tmp",
                kind: .file,
                contentTypeDescription: "Text"
            )
        }
        let service = InMemoryFileSearchService(items: items)
        let request = FileSearchRequest(
            query: SearchQuery(text: "file", limit: 2),
            category: .documents
        )

        let results = try await service.search(request)

        #expect(results.count == 2)
        #expect(await service.requests == [request])
    }
}
