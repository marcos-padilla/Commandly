import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct GIFSearchViewModelTests {
    @Test func resultAccessibilityDistinguishesTitlesAndCreatorsWithIdenticalProviderDescriptions() {
        func item(title: String, creator: String?, source: String? = nil, description: String = "A generated moving circle") -> GIFCatalogItem {
            .init(id: title, title: title, accessibilityText: description, creator: creator, sourceName: source,
                  pageURL: nil, sourceURL: nil, previewURL: nil, originalURL: nil)
        }
        let first = GIFSearchViewModel.resultAccessibilityLabel(for: item(title: "Hello", creator: "Creator One"))
        let second = GIFSearchViewModel.resultAccessibilityLabel(for: item(title: "Celebrate", creator: "Creator Two"))
        let third = GIFSearchViewModel.resultAccessibilityLabel(for: item(title: "Agree", creator: nil, source: "Generated Source"))
        #expect(Set([first, second, third]).count == 3)
        #expect(first.contains("Hello")); #expect(first.contains("Creator One")); #expect(first.contains("moving circle"))
        #expect(second.contains("Celebrate")); #expect(second.contains("Creator Two"))
        #expect(third.contains("Generated Source"))
        let repeatedTitle = GIFSearchViewModel.resultAccessibilityLabel(for: item(title: "Hello", creator: nil, description: " hello "))
        #expect(repeatedTitle == "Hello")
    }
    @Test func openingAndTypingDoNotQueryUntilExplicitSubmitAndRapidReturnCoalesces() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "hello"
        #expect(await context.catalog.queries.isEmpty)
        model.submitFromKeyboard(); model.submitFromKeyboard()
        await context.catalog.waitForSearch()
        #expect(await context.catalog.queries.count == 1)
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil))
        await model.waitForSearchForTesting()
        #expect(model.selected?.id == "first"); #expect(model.animation?.frames.count == 4)
        #expect(await context.exporter.copies.isEmpty)
        model.submitFromKeyboard(); model.submitFromKeyboard(); await model.waitForExportForTesting()
        #expect(await context.exporter.copies.count == 1)
        #expect(model.statusMessage != nil)
        model.openConnection()
        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == nil)
        model.stop()
    }
    @Test func generatedConnectionChangesNeverClaimARealKeychainWrite() async {
        let context = GIFModelTestContext()
        let model = GIFSearchViewModel(services: GIFSearchDebugFixture.services(exporter: context.exporter), onGoBack: {})
        model.load(); await model.waitForLoadForTesting(); model.openConnection()
        model.apiKeyInput = "generated-test-value"; model.saveKey(); await model.waitForConnectionForTesting()
        #expect(model.connection?.isConfigured == true)
        #expect(model.statusMessage == "Generated connection enabled. No key was saved or sent.")
        model.disconnect(); await model.waitForConnectionForTesting()
        #expect(model.connection?.isConfigured == false)
        #expect(model.statusMessage == "Generated connection disabled. No saved key was changed.")
        model.stop()
    }
    @Test func queryEditRejectsLateSearchAndCannotCopyPreviousResults() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "old"; model.submitSearch(); await context.catalog.waitForSearch()
        let pending = model.pendingSearchForTesting
        model.query = "new"; model.export(.copy)
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil)); await pending?.value
        #expect(model.items.isEmpty); #expect(!model.isSearching); #expect(model.animation == nil)
        #expect(await context.exporter.copies.isEmpty)
        model.stop()
    }
    @Test func returnCopiesSelectedTrendingGIFWithoutSubmittingTextSearch() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "a previous unsubmitted query"
        model.loadTrending(); await context.catalog.waitForSearch()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil))
        await model.waitForSearchForTesting()
        #expect(model.footerActions.first?.id == BuiltInCommandActionID.copy)
        model.submitFromKeyboard(); await model.waitForExportForTesting()
        #expect(await context.catalog.queries == [.trending])
        #expect(await context.exporter.copies.count == 1)
        #expect(model.errorMessage == nil)
        model.stop()
    }
    @Test func reduceMotionDisablesPreviewActionsAndRequiresExplicitReplayWhenDisabled() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.setReduceMotion(true)
        model.loadTrending(); await context.catalog.waitForSearch()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil))
        await model.waitForSearchForTesting()
        #expect(model.animation != nil); #expect(!model.isPlaying)
        let motionAction = try #require(model.menuActions.first { $0.id == GIFSearchActionID.pause })
        #expect(motionAction.title == "Still Preview"); #expect(!motionAction.isEnabled)
        model.perform(GIFSearchActionID.pause); #expect(!model.isPlaying)
        model.setReduceMotion(false)
        #expect(model.canTogglePreviewPlayback); #expect(!model.isPlaying)
        model.perform(GIFSearchActionID.pause); #expect(model.isPlaying)
        model.setReduceMotion(true); #expect(!model.isPlaying)
        model.stop()
    }
    @Test func selectionChangeRejectsLateOriginalDownloadBeforeAnyCopy() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "hello"; model.submitSearch(); await context.catalog.waitForSearch()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first, GIFModelTestCatalog.second], nextOffset: nil)); await model.waitForSearchForTesting()
        await context.catalog.suspendOriginals()
        model.export(.copy); await context.catalog.waitForOriginal()
        let pending = model.pendingExportForTesting
        model.moveSelection(offset: 1); await context.catalog.completeOriginal(); await pending?.value
        #expect(model.selected?.id == "second"); #expect(await context.exporter.copies.isEmpty)
        model.stop()
    }
    @Test func disconnectImmediatelyClearsBuffersAndRejectsLatePreview() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "hello"; model.submitSearch(); await context.catalog.waitForSearch()
        await context.catalog.suspendPreviews()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil)); await context.catalog.waitForPreview()
        let pending = model.pendingPreviewForTesting
        model.disconnect(); #expect(model.items.isEmpty); #expect(model.animation == nil)
        await model.waitForConnectionForTesting(); await context.catalog.completePreview(); await pending?.value
        #expect(model.connection?.isConfigured == false); #expect(model.animation == nil)
        #expect(!model.canSearch); #expect(!model.canExport)
        model.stop()
    }
    @Test func loadingSavedStateAfterExternalKeyChangeClearsResultBuffers() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.loadTrending(); await context.catalog.waitForSearch()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: 24)); await model.waitForSearchForTesting()
        #expect(model.animation != nil); #expect(model.canGoNext)
        _ = await context.catalog.configure(key: "generated replacement")
        model.refreshConnection(); await model.waitForLoadForTesting()
        #expect(model.items.isEmpty); #expect(model.animation == nil); #expect(!model.canGoNext)
        model.stop()
    }
    @Test func routeStopRejectsPendingPreviewAndClearsUnsavedKey() async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "hello"; model.submitSearch(); await context.catalog.waitForSearch()
        let pending = model.pendingSearchForTesting
        model.apiKeyInput = "generated-unsaved-key"; model.stop()
        await context.catalog.completeSearch(.init(items: [GIFModelTestCatalog.first], nextOffset: nil)); await pending?.value
        #expect(model.apiKeyInput.isEmpty); #expect(model.items.isEmpty); #expect(model.animation == nil)
    }
    @Test(arguments: [true, false]) func stoppedConnectionMutationCanReloadWithoutStaleSheetOrSuccess(saving: Bool) async throws {
        let context = GIFModelTestContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting()
        await context.catalog.suspendConnectionChanges()
        model.openConnection(); model.showsActionsMenu = true; model.apiKeyInput = "generated-replacement-key"
        if saving { model.saveKey() } else { model.disconnect() }
        await context.catalog.waitForConnectionChange()
        #expect(model.isChangingConnection)
        model.stop()
        #expect(!model.isChangingConnection); #expect(!model.isLoading)
        #expect(!model.showsConnection); #expect(!model.showsActionsMenu); #expect(model.apiKeyInput.isEmpty)
        model.load(); #expect(model.isLoading)
        await context.catalog.completeConnectionChange()
        await model.waitForLoadForTesting()
        let freshState = await context.catalog.connection()
        #expect(model.connection == freshState); #expect(model.connection?.isConfigured == saving)
        #expect(!model.isLoading); #expect(!model.isChangingConnection)
        #expect(model.errorMessage == nil); #expect(model.statusMessage == nil)
        model.openConnection(); model.closeConnection(); #expect(!model.showsConnection)
        model.stop()
    }
    @Test func registeredEntryOpensWithoutRemoteRequest() async throws {
        let fixture = GIFModelTestContext(); let app = GIFSearchApplication(services: fixture.services)
        let context = LauncherApplicationContext(navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        #expect(app.definition.id.rawValue == "media.gif-search")
        #expect(app.definition.documentation != nil); #expect(app.toolDefinitions.map(\.id) == [GIFSearchApplication.openToolID])
        let launch = app.launch(in: context)
        guard case .present(let session) = launch else { Issue.record("Expected GIF search session"); return }
        let model = try #require(session.model(as: GIFSearchViewModel.self)); model.load(); await model.waitForLoadForTesting()
        #expect(await fixture.catalog.queries.isEmpty); session.stop()
    }
}

@MainActor private struct GIFModelTestContext {
    let catalog = GIFModelTestCatalog()
    let exporter = GIFModelTestExporter()
    var services: GIFSearchApplicationServices { .init(catalog: catalog, decoder: GIFAnimationDecoder(), exporter: exporter, openURL: { _ in }) }
    func model() -> GIFSearchViewModel { .init(services: services, onGoBack: {}) }
}
private actor GIFModelTestCatalog {
    nonisolated static let first = item("first")
    nonisolated static let second = item("second")
    nonisolated private static func item(_ id: String) -> GIFCatalogItem {
        .init(id: id, title: id, accessibilityText: id, creator: "Generated", sourceName: nil, pageURL: nil, sourceURL: nil,
              previewURL: URL(string: "https://media.giphy.com/media/\(id)/200w.gif"), originalURL: URL(string: "https://media.giphy.com/media/\(id)/giphy.gif"))
    }
    private var state = GIFConnectionState(revision: UUID(), isConfigured: true)
    private let generator = GeneratedGIFData()
    private(set) var queries: [GIFCatalogQuery] = []
    private var search: CheckedContinuation<GIFCatalogPage, Never>?
    private var searchWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendOriginal = false
    private var original: CheckedContinuation<Void, Never>?
    private var originalWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendPreview = false
    private var preview: CheckedContinuation<Void, Never>?
    private var previewWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendsConnection = false
    private var connectionChange: CheckedContinuation<Void, Never>?
    private var connectionWaiters: [CheckedContinuation<Void, Never>] = []
    func connection() -> GIFConnectionState { state }
    func configure(key: String) async -> GIFConnectionState { await changeConnection(configured: true) }
    func disconnect() async -> GIFConnectionState { await changeConnection(configured: false) }
    private func changeConnection(configured: Bool) async -> GIFConnectionState {
        if suspendsConnection {
            connectionWaiters.forEach { $0.resume() }; connectionWaiters = []
            await withCheckedContinuation { connectionChange = $0 }
        }
        state = .init(revision: UUID(), isConfigured: configured); return state
    }
    func suspendConnectionChanges() { suspendsConnection = true }
    func waitForConnectionChange() async { if connectionChange == nil { await withCheckedContinuation { connectionWaiters.append($0) } } }
    func completeConnectionChange() { connectionChange?.resume(); connectionChange = nil }
    func search(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, connection: UUID) async -> GIFCatalogPage {
        queries.append(query); searchWaiters.forEach { $0.resume() }; searchWaiters = []
        return await withCheckedContinuation { search = $0 }
    }
    func media(_ item: GIFCatalogItem, original: Bool, connection: UUID) async throws -> Data {
        if original, suspendOriginal {
            originalWaiters.forEach { $0.resume() }; originalWaiters = []
            await withCheckedContinuation { self.original = $0 }
        } else if !original, suspendPreview {
            previewWaiters.forEach { $0.resume() }; previewWaiters = []
            await withCheckedContinuation { preview = $0 }
        }
        return try await generator.make()
    }
    func waitForSearch() async { if search == nil { await withCheckedContinuation { searchWaiters.append($0) } } }
    func completeSearch(_ page: GIFCatalogPage) { search?.resume(returning: page); search = nil }
    func suspendOriginals() { suspendOriginal = true }
    func waitForOriginal() async { if original == nil { await withCheckedContinuation { originalWaiters.append($0) } } }
    func completeOriginal() { original?.resume(); original = nil }
    func suspendPreviews() { suspendPreview = true }
    func waitForPreview() async { if preview == nil { await withCheckedContinuation { previewWaiters.append($0) } } }
    func completePreview() { preview?.resume(); preview = nil }
}
extension GIFModelTestCatalog: GIFCatalogServing {}
private actor GIFModelTestExporter {
    private(set) var copies: [Data] = []
    private(set) var saves: [Data] = []
    func copy(_ data: Data) { copies.append(data) }
    func save(_ data: Data, suggestedName: String) -> Bool { saves.append(data); return true }
}
extension GIFModelTestExporter: GIFExporting {}
