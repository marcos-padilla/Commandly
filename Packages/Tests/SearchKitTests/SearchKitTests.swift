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
}
