import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct SlackEmojiViewModelTests {
    @Test func openingAndTypingStayLocalUntilRefreshAndReturnCopiesOnlyTheName() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.query = "wave"
        #expect(await context.service.refreshCount == 0)
        model.submit(); model.submit(); await model.waitForRefreshForTesting()
        #expect(await context.service.refreshCount == 1); #expect(model.selected?.name == "wave")
        model.submit(); model.submit(); await model.waitForExportForTesting()
        #expect(await context.exporter.names == ["wave"]); #expect(await context.exporter.images.isEmpty)
        model.stop(); await model.waitForCleanupForTesting()
    }
    @Test func queryEditClearsSelectionBeforeImmediateReturnWithoutRemoteRefresh() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.refresh(); await model.waitForRefreshForTesting()
        #expect(model.selected != nil)
        model.query = "no such generated name"; model.submit(); await model.waitForFilterForTesting()
        #expect(model.items.isEmpty); #expect(await context.exporter.names.isEmpty)
        #expect(await context.service.refreshCount == 1)
        #expect(model.footerActions.first?.isEnabled == false)
        model.stop(); await model.waitForCleanupForTesting()
    }
    @Test func switchingWorkspaceRejectsAndReleasesLateRefreshWithoutFocusSteal() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); let focus = model.focusRequest
        await context.service.suspendRefreshes(); model.refresh(); await context.service.waitForRefresh()
        let pending = model.pendingRefreshForTesting
        model.workspaceID = "TSECOND"; await context.service.completeRefresh(); await pending?.value
        #expect(model.catalog == nil); #expect(model.items.isEmpty); #expect(model.workspace?.id == "TSECOND")
        #expect(model.focusRequest == focus); #expect(await context.service.released.count == 1)
        model.stop()
    }
    @Test func changedSelectionCancelsLateImageCopyAndReduceMotionDisablesAllPlaybackActions() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); model.refresh(); await model.waitForRefreshForTesting()
        model.setReduceMotion(true); #expect(!model.isPlaying); #expect(!model.canTogglePlayback)
        model.perform(SlackEmojiActionID.playback); #expect(!model.isPlaying)
        await context.service.suspendMedia(); model.exportImage(save: false); await context.service.waitForMedia()
        let pending = model.pendingExportForTesting
        model.moveSelection(offset: 1); await context.service.completeMedia(); await pending?.value
        #expect(await context.exporter.images.isEmpty); #expect(model.selected?.name == "wave")
        model.stop(); await model.waitForCleanupForTesting()
    }
    @Test func stoppedConnectionMutationReloadsFreshStateWithoutStaleSheetOrStatus() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); let old = model.workspace
        model.openConnections(); model.tokenInput = "xoxb-generated-replacement"
        await context.service.suspendConnections(); model.connect(replacing: true); await context.service.waitForConnection()
        #expect(model.isChangingConnection)
        model.stop(); model.load(); #expect(model.isLoading); #expect(!model.showsConnections)
        await context.service.completeConnection(); await model.waitForLoadForTesting()
        #expect(model.workspace?.id == old?.id); #expect(model.workspace?.revision != old?.revision)
        #expect(!model.isChangingConnection); #expect(!model.isLoading); #expect(model.statusMessage == nil)
        #expect(model.tokenInput.isEmpty); #expect(model.canRefresh)
        model.stop()
    }
    @Test func registeredEntryDoesNotContactSlackOrRefreshUntilRequested() async throws {
        let context = try SlackEmojiModelContext(); let application = SlackEmojiApplication(services: context.services)
        #expect(application.definition.id == SlackEmojiApplication.id); #expect(application.definition.documentation != nil)
        #expect(application.toolDefinitions.map(\.id) == [SlackEmojiApplication.openToolID])
        let launch = application.launch(in: .init(navigation: .init(dismissLauncher: {}, openSettings: {}, goBack: {}), settings: .init(alias: "", hotKey: nil, isEnabled: true, configuration: [:])))
        guard case .present(let session) = launch else { Issue.record("Expected workspace emoji session"); return }
        let model = try #require(session.model(as: SlackEmojiViewModel.self)); model.load(); await model.waitForLoadForTesting()
        #expect(await context.service.refreshCount == 0); session.stop()
    }
    @Test func escapeCancelsCheckingAndReloadsAnyMutationThatAlreadyCommitted() async throws {
        let context = try SlackEmojiModelContext(); let model = context.model()
        model.load(); await model.waitForLoadForTesting(); let old = model.workspace
        model.openConnections(); model.tokenInput = "xoxb-generated-replacement"
        await context.service.suspendConnections(); model.connect(replacing: true); await context.service.waitForConnection()
        #expect(model.handleEscape()); #expect(model.isCancellingConnection)
        await context.service.completeConnection(); await model.waitForCancellationForTesting()
        #expect(!model.isChangingConnection); #expect(!model.isCancellingConnection); #expect(!model.showsConnections)
        #expect(model.workspace?.id == old?.id); #expect(model.workspace?.revision != old?.revision)
        #expect(model.statusMessage?.contains("finished before cancellation") == true)
        #expect(model.canRefresh); model.stop()
    }
}
@MainActor private struct SlackEmojiModelContext {
    let service: SlackEmojiModelService
    let exporter = SlackEmojiModelExporter()
    init() throws { service = try SlackEmojiModelService() }
    var services: SlackEmojiApplicationServices { .init(service: service, decoder: SlackEmojiImageDecoder(), exporter: exporter, openURL: { _ in }, fixtureLabel: "Generated Test Fixture") }
    func model() -> SlackEmojiViewModel { .init(services: services, onGoBack: {}) }
}
private actor SlackEmojiModelService {
    private var workspaces: [SlackEmojiWorkspace]
    private(set) var refreshCount = 0
    private(set) var released: [UUID] = []
    private var holdsRefresh = false
    private var refreshGate: CheckedContinuation<Void, Never>?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdsMedia = false
    private var mediaGates: [CheckedContinuation<Void, Never>] = []
    private var mediaWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdsConnection = false
    private var connectionGate: CheckedContinuation<Void, Never>?
    private var connectionWaiters: [CheckedContinuation<Void, Never>] = []
    private let images = GeneratedSlackEmojiMedia()
    init() throws { workspaces = [try SlackEmojiTestData.workspace(), try SlackEmojiTestData.workspace(id: "TSECOND")] }
    func connections() -> [SlackEmojiWorkspace] { workspaces }
    func connect(token: String, replacing: SlackEmojiWorkspace?) async throws -> SlackEmojiWorkspace {
        if holdsConnection { connectionWaiters.forEach { $0.resume() }; connectionWaiters = []; await withCheckedContinuation { connectionGate = $0 } }
        let updated = try SlackEmojiTestData.workspace(id: replacing?.id ?? "TNEW")
        workspaces.removeAll { $0.id == updated.id }; workspaces.insert(updated, at: 0); return updated
    }
    func disconnect(_ workspace: SlackEmojiWorkspace) { workspaces.removeAll { $0.id == workspace.id } }
    func refresh(_ workspace: SlackEmojiWorkspace) async -> SlackEmojiCatalog {
        refreshCount += 1
        if holdsRefresh { refreshWaiters.forEach { $0.resume() }; refreshWaiters = []; await withCheckedContinuation { refreshGate = $0 } }
        return .init(id: UUID(), workspace: workspace, count: 2, refreshedAt: Date(timeIntervalSince1970: 1_900_000_000))
    }
    func search(_ query: String, catalog: SlackEmojiCatalog) throws -> SlackEmojiMatches {
        let url = try #require(URL(string: "https://emoji.slack-edge.com/TFIXTURE/circle/generated.gif"))
        let items = [SlackCustomEmoji(name: "circle", resolution: .image(url: url, canonicalName: "circle", aliasChain: [])),
                     SlackCustomEmoji(name: "wave", resolution: .image(url: url, canonicalName: "circle", aliasChain: ["circle"]))]
        return try SlackEmojiCatalogParser.matches(items, query: query)
    }
    func media(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) async throws -> Data {
        if holdsMedia { mediaWaiters.forEach { $0.resume() }; mediaWaiters = []; await withCheckedContinuation { mediaGates.append($0) } }
        return try await images.make(animated: true)
    }
    func release(_ catalog: SlackEmojiCatalog) { released.append(catalog.id) }
    func suspendRefreshes() { holdsRefresh = true }
    func waitForRefresh() async { if refreshGate == nil { await withCheckedContinuation { refreshWaiters.append($0) } } }
    func completeRefresh() { holdsRefresh = false; refreshGate?.resume(); refreshGate = nil }
    func suspendMedia() { holdsMedia = true }
    func waitForMedia() async { if mediaGates.isEmpty { await withCheckedContinuation { mediaWaiters.append($0) } } }
    func completeMedia() { holdsMedia = false; mediaGates.forEach { $0.resume() }; mediaGates = [] }
    func suspendConnections() { holdsConnection = true }
    func waitForConnection() async { if connectionGate == nil { await withCheckedContinuation { connectionWaiters.append($0) } } }
    func completeConnection() { holdsConnection = false; connectionGate?.resume(); connectionGate = nil }
}
extension SlackEmojiModelService: SlackEmojiServing {}
private actor SlackEmojiModelExporter {
    private(set) var names: [String] = []
    private(set) var images: [Data] = []
    func copyName(_ name: String) { names.append(name) }
    func copyImage(_ data: Data) { images.append(data) }
    func saveImage(_ data: Data, name: String) -> Bool { images.append(data); return true }
}
extension SlackEmojiModelExporter: SlackEmojiExporting {}
