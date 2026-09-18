import Foundation
import CommandKit
import Infrastructure
import Testing
@testable import Commandly

@Suite("Emoji Search interaction")
@MainActor
struct EmojiSearchViewModelTests {
    @Test func typingAndChoosingVariantsNeverCopiesOrSendsAI() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        fixture.model.query = "handshake"; await fixture.model.waitForSearchForTesting()
        let handshake = try #require(fixture.model.entries.first { $0.symbol == "🤝" })
        fixture.model.select(handshake); fixture.model.selectVariant("🫱🏻‍🫲🏿")
        #expect(fixture.model.selected?.symbol == "🫱🏻‍🫲🏿")
        #expect(await fixture.board.writes.isEmpty)
        #expect(await fixture.semantic.requestCount == 0)
        fixture.model.copy(); await fixture.model.waitForCopyForTesting()
        #expect(await fixture.board.writes == ["🫱🏻‍🫲🏿"])
        fixture.model.stop()
    }
    @Test func immediateReturnWaitsForCurrentQueryAndRepeatedReturnCopiesOnlyOnce() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        await fixture.catalog.setSuspended(true)
        fixture.model.query = "flag Japan"; fixture.model.submit(); fixture.model.submit()
        #expect(fixture.model.selected == nil)
        #expect(await fixture.board.writes.isEmpty)
        await fixture.catalog.waitForSearches(2)
        await fixture.catalog.complete(1)
        await fixture.model.waitForSearchForTesting()
        #expect(await fixture.board.writes == ["🇯🇵"])
        fixture.model.stop()
    }
    @Test func editingOrLeavingInvalidatesDeferredCopyAndLateResults() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        await fixture.catalog.setSuspended(true)
        fixture.model.query = "Japan"; fixture.model.submit()
        await fixture.catalog.waitForSearches(2)
        let older = fixture.model.pendingSearchForTesting
        fixture.model.query = "astronaut"
        await fixture.catalog.waitForSearches(3)
        await fixture.catalog.complete(2); await fixture.model.waitForSearchForTesting()
        await fixture.catalog.complete(1); await older?.value
        #expect(fixture.model.entries.first?.name.contains("astronaut") == true)
        #expect(await fixture.board.writes.isEmpty)
        fixture.model.query = "heart"; fixture.model.submit()
        await fixture.catalog.waitForSearches(4)
        let leaving = fixture.model.pendingSearchForTesting
        fixture.model.stop(); await fixture.catalog.complete(3); await leaving?.value
        #expect(await fixture.board.writes.isEmpty)
        #expect(fixture.model.entries.isEmpty)
    }
    @Test func aiRequiresExplicitIntentAndChangingProviderRejectsLateNonCooperativeResponse() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        fixture.model.mode = .ai; fixture.model.query = "a brave first step"
        #expect(await fixture.semantic.requestCount == 0)
        fixture.model.submit()
        if let primary = fixture.model.footerActions.first(where: \.isPrimary) { fixture.model.perform(primary.id) }
        await fixture.semantic.waitForRequests(1)
        #expect(await fixture.semantic.requestCount == 1)
        let older = fixture.model.pendingAIForTesting
        fixture.model.providerID = EmojiTestSelection.second.id
        await fixture.semantic.complete(0, symbols: ["🚀"]); await older?.value
        #expect(fixture.model.entries.isEmpty)
        #expect(!fixture.model.hasAIResult)
        fixture.model.findWithAI(); await fixture.semantic.waitForRequests(2)
        await fixture.semantic.complete(1, symbols: ["🧑‍🚀", "🚀"]); await fixture.model.waitForAIForTesting()
        #expect(fixture.model.entries.map(\.symbol) == ["🧑‍🚀", "🚀"])
        #expect(await fixture.board.writes.isEmpty)
        fixture.model.submit(); await fixture.model.waitForCopyForTesting()
        #expect(await fixture.board.writes == ["🧑‍🚀"])
        fixture.model.stop()
    }
    @Test func escapeCancelsAIWhileKeepingDescriptionThenClearsDescriptionBeforeLeaving() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        fixture.model.mode = .ai; fixture.model.query = "quiet confidence"; fixture.model.findWithAI()
        await fixture.semantic.waitForRequests(1)
        let older = fixture.model.pendingAIForTesting
        #expect(fixture.model.handleEscape())
        #expect(fixture.model.query == "quiet confidence")
        await fixture.semantic.complete(0, symbols: ["😌"]); await older?.value
        #expect(fixture.model.entries.isEmpty)
        #expect(fixture.model.handleEscape())
        #expect(fixture.model.query.isEmpty)
        #expect(!fixture.model.handleEscape())
        fixture.model.stop()
    }
    @Test func keyboardMovesBySixColumnsAndCopyUsesTheVisibleSelection() async throws {
        let fixture = try await setup()
        fixture.model.start(); await fixture.model.waitForLoadingForTesting()
        let values = fixture.model.entries
        fixture.model.moveSelection(offset: 1)
        #expect(fixture.model.selectedID == values[6].id)
        fixture.model.moveCell(offset: 1)
        #expect(fixture.model.selectedID == values[7].id)
        fixture.model.copy(); await fixture.model.waitForCopyForTesting()
        #expect(await fixture.board.writes == [values[7].symbol])
        fixture.model.stop()
    }

    private func setup() async throws -> (model: EmojiSearchViewModel, catalog: ControlledEmojiCatalog, semantic: ControlledEmojiSemanticSearch, board: EmojiPasteboardFake) {
        let value = try await EmojiTestData.catalog()
        let catalog = ControlledEmojiCatalog(value)
        let semantic = ControlledEmojiSemanticSearch()
        let board = EmojiPasteboardFake()
        let model = EmojiSearchViewModel(services: .init(catalog: catalog, semantic: semantic, pasteboard: board), onGoBack: {}, onOpenSettings: {})
        return (model, catalog, semantic, board)
    }
}

actor EmojiPasteboardFake: PasteboardAccessing {
    private(set) var writes: [String] = []
    func readString() async -> String? { nil }
    func writeString(_ value: String) async { writes.append(value) }
}

actor ControlledEmojiCatalog {
    let catalog: UnicodeEmojiCatalog
    private var suspended = false
    private var requests: [UnicodeEmojiSearchRequest] = []
    private var continuations: [Int: CheckedContinuation<[UnicodeEmojiEntry], Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(_ catalog: UnicodeEmojiCatalog) { self.catalog = catalog }
    func load() async throws -> UnicodeEmojiCatalog { catalog }
    func setSuspended(_ value: Bool) { suspended = value }
    func search(_ request: UnicodeEmojiSearchRequest) async throws -> [UnicodeEmojiEntry] {
        let index = requests.count; requests.append(request)
        if !suspended { return try catalog.search(request) }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            for waiter in waiters where requests.count >= waiter.0 { waiter.1.resume() }
            waiters.removeAll { requests.count >= $0.0 }
        }
    }
    func waitForSearches(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func complete(_ index: Int) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        do { continuation.resume(returning: try catalog.search(requests[index])) }
        catch { continuation.resume(throwing: error) }
    }
}

extension ControlledEmojiCatalog: UnicodeEmojiCatalogProviding {}

actor ControlledEmojiSemanticSearch {
    private var catalogs: [UnicodeEmojiCatalog] = []
    private var continuations: [Int: CheckedContinuation<[UnicodeEmojiEntry], Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var requestCount: Int { catalogs.count }
    func selections() async throws -> QuickAICatalog { EmojiTestSelection.catalog }
    func search(description: String, selection: QuickAISelection, catalog: UnicodeEmojiCatalog) async throws -> [UnicodeEmojiEntry] {
        let index = catalogs.count; catalogs.append(catalog)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            for waiter in waiters where catalogs.count >= waiter.0 { waiter.1.resume() }
            waiters.removeAll { catalogs.count >= $0.0 }
        }
    }
    func waitForRequests(_ count: Int) async {
        if catalogs.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func complete(_ index: Int, symbols: [String]) { continuations.removeValue(forKey: index)?.resume(returning: symbols.compactMap { catalogs[index].entry(for: $0) }) }
}

extension ControlledEmojiSemanticSearch: EmojiSemanticSearching {}
