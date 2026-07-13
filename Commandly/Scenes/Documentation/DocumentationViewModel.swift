import Foundation
import Observation

@Observable
@MainActor
final class DocumentationViewModel {
    @ObservationIgnored
    private let registry: LauncherApplicationRegistry
    @ObservationIgnored
    private let coreArticles: [CoreDocumentationArticle]

    private(set) var articles: [DocumentationArticle] = []
    private(set) var filteredArticles: [DocumentationArticle] = []
    var selectedArticleID: String?
    var query = "" {
        didSet {
            guard oldValue != query else { return }
            updateFilteredArticles()
            repairSelection()
        }
    }

    init(
        registry: LauncherApplicationRegistry,
        coreArticles: [CoreDocumentationArticle] = CoreDocumentationCatalog.articles
    ) {
        self.registry = registry
        self.coreArticles = coreArticles
        refresh()
    }

    var groupedArticles: [(category: DocumentationCategory, articles: [DocumentationArticle])] {
        DocumentationCategory.allCases.compactMap { category in
            let matching = filteredArticles.filter { $0.category == category }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    var selectedArticle: DocumentationArticle? {
        guard let selectedArticleID else { return filteredArticles.first }
        return filteredArticles.first { $0.id == selectedArticleID } ?? filteredArticles.first
    }

    var resultSummary: String {
        let count = filteredArticles.count
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(articles.count) articles"
        }
        return count == 1 ? "1 result" : "\(count) results"
    }

    func refresh() {
        let previousSelection = selectedArticleID
        articles = DocumentationCatalog.articles(
            registry: registry,
            coreArticles: coreArticles
        )
        selectedArticleID = previousSelection
        updateFilteredArticles()
        repairSelection()
    }

    func select(_ articleID: String) {
        guard filteredArticles.contains(where: { $0.id == articleID }) else { return }
        selectedArticleID = articleID
    }

    func clearSearch() {
        query = ""
    }

    func moveSelection(offset: Int) {
        let visible = filteredArticles
        guard visible.isEmpty == false else { return }
        let currentIndex = selectedArticleID.flatMap { id in
            visible.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visible.count - 1)
        selectedArticleID = visible[nextIndex].id
    }

    private func repairSelection() {
        let visible = filteredArticles
        guard visible.isEmpty == false else {
            selectedArticleID = nil
            return
        }
        if let selectedArticleID,
           visible.contains(where: { $0.id == selectedArticleID }) {
            return
        }
        selectedArticleID = visible[0].id
    }

    private func updateFilteredArticles() {
        let needle = query.foldedForDocumentationQuery
        guard needle.isEmpty == false else {
            filteredArticles = articles
            return
        }
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        filteredArticles = articles.filter { article in
            words.allSatisfy(article.searchableText.contains)
        }
    }
}

extension String {
    fileprivate var foldedForDocumentationQuery: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
