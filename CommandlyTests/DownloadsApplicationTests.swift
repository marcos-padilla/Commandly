import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct DownloadsApplicationTests {
    @Test func nativeScannerReturnsVisibleRegularFilesInDownloadRecencyOrder() async throws {
        let fileManager = FileManager()
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("Commandly-Downloads-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let olderURL = directory.appendingPathComponent("b-older.txt")
        try Data("older".utf8).write(to: olderURL)
        try fileManager.setAttributes(
            [
                .creationDate: baseDate,
                .modificationDate: baseDate.addingTimeInterval(1_000)
            ],
            ofItemAtPath: olderURL.path
        )

        let hiddenURL = directory.appendingPathComponent(".private.txt")
        try Data("hidden".utf8).write(to: hiddenURL)
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("Expanded Archive", isDirectory: true),
            withIntermediateDirectories: true
        )

        let newestURL = directory.appendingPathComponent("a-newest.txt")
        try Data("newest".utf8).write(to: newestURL)
        try fileManager.setAttributes(
            [
                .creationDate: baseDate.addingTimeInterval(100),
                .modificationDate: baseDate.addingTimeInterval(-1_000)
            ],
            ofItemAtPath: newestURL.path
        )

        let service = NativeRecentDownloadsService(directoryURL: directory)
        let results = try await service.recentDownloads(limit: 10)

        #expect(results.map(\.name) == ["a-newest.txt", "b-older.txt"])
        #expect(results.allSatisfy { $0.name.hasPrefix(".") == false })
        #expect(results.allSatisfy { $0.byteCount > 0 })
        #expect(try await service.recentDownloads(limit: 1).map(\.name) == ["a-newest.txt"])
    }

    @Test func nativeScannerUsesTypedContentFreeDirectoryError() async {
        let unavailable = FileManager.default.temporaryDirectory
            .appendingPathComponent("Commandly-Missing-\(UUID().uuidString)", isDirectory: true)
        let service = NativeRecentDownloadsService(directoryURL: unavailable)

        await #expect(throws: RecentDownloadsError.directoryUnavailable) {
            try await service.recentDownloads(limit: 10)
        }
    }

    @Test @MainActor func applicationSessionLoadsAndPerformsEveryNativeFileAction() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_800_100_000)
        let newest = item(
            name: "Latest Package.zip",
            addedAt: baseDate.addingTimeInterval(60),
            modifiedAt: baseDate
        )
        let second = item(
            name: "Reference.pdf",
            addedAt: baseDate,
            modifiedAt: baseDate.addingTimeInterval(500)
        )
        let provider = FixedRecentDownloadsProvider(items: [newest, second])
        let opener = RecordingDownloadOpener()
        let revealer = RecordingDownloadRevealer()
        let pasteboard = InMemoryPasteboard()
        var didDismiss = false
        let application = DownloadsApplication(
            services: DownloadsApplicationServices(
                provider: provider,
                urlOpener: opener,
                fileRevealer: revealer,
                pasteboard: pasteboard
            )
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: { didDismiss = true },
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )

        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected Recent Downloads to present a session")
            return
        }
        let model = try #require(session.model(as: DownloadsViewModel.self))
        model.load()
        await model.waitForLoadForTesting()

        #expect(application.definition.id == DownloadsApplication.applicationID)
        #expect(application.definition.kind == .application)
        #expect(application.definition.commandManifest?.mode == .view)
        #expect(DownloadsApplication.manifest.defaultActions.first?.title == "Open Newest Download")
        #expect(model.loadState == .loaded)
        #expect(model.selectedItem == newest)

        model.perform(BuiltInCommandActionID.openFile)
        await model.waitForOperationForTesting()
        #expect(await opener.recordedURLs() == [newest.url])
        #expect(didDismiss)

        model.perform(BuiltInCommandActionID.copyFile)
        await model.waitForOperationForTesting()
        #expect(pasteboard.currentFileURLs == [newest.url])

        model.select(second.id)
        model.perform(BuiltInCommandActionID.revealFile)
        await model.waitForOperationForTesting()
        #expect(await revealer.recordedURLs() == [second.url])

        model.perform(DownloadsActionID.copyNewest)
        await model.waitForOperationForTesting()
        #expect(pasteboard.currentFileURLs == [newest.url])
        #expect(model.statusMessage == "Copied download.")
    }

    @Test @MainActor func filteringSelectionEmptyAndFailureStatesRemainKeyboardUsable() async {
        let baseDate = Date(timeIntervalSince1970: 1_800_200_000)
        let first = item(name: "Archive.zip", addedAt: baseDate, modifiedAt: baseDate)
        let second = item(
            name: "Notes.txt",
            addedAt: baseDate.addingTimeInterval(-1),
            modifiedAt: baseDate
        )
        let model = makeModel(provider: FixedRecentDownloadsProvider(items: [first, second]))
        model.load()
        await model.waitForLoadForTesting()

        model.query = "notes"
        #expect(model.filteredItems == [second])
        #expect(model.selectedItem == second)
        #expect(model.handleEscape())
        #expect(model.query.isEmpty)
        model.moveSelection(offset: 1)
        #expect(model.selectedItem == first)

        let emptyModel = makeModel(provider: FixedRecentDownloadsProvider(items: []))
        emptyModel.load()
        await emptyModel.waitForLoadForTesting()
        #expect(emptyModel.loadState == .empty)
        #expect(emptyModel.footerActions.first?.id == DownloadsActionID.refresh)

        let failingModel = makeModel(provider: FailingRecentDownloadsProvider())
        failingModel.load()
        await failingModel.waitForLoadForTesting()
        #expect(failingModel.loadState == .failed(.directoryUnavailable))
        #expect(failingModel.statusMessage == "The Downloads folder is unavailable.")
    }

    @Test @MainActor func aNewRefreshCancelsTheSupersededScanWithoutStaleResults() async throws {
        let provider = ControlledRecentDownloadsProvider()
        let model = makeModel(provider: provider)
        var starts = provider.starts.makeAsyncIterator()

        model.load()
        let firstRequest = try #require(await starts.next())

        model.refresh(showSuccessMessage: false)
        let secondRequest = try #require(await starts.next())
        let replacement = item(
            name: "Replacement.dmg",
            addedAt: Date(timeIntervalSince1970: 1_800_300_000),
            modifiedAt: Date(timeIntervalSince1970: 1_800_300_000)
        )
        await provider.resume(request: secondRequest, with: [replacement])
        await model.waitForLoadForTesting()

        #expect(await provider.cancelledRequests().contains(firstRequest))
        #expect(model.items == [replacement])
        #expect(model.loadState == .loaded)
    }

    @MainActor
    private func makeModel(provider: any RecentDownloadsProviding) -> DownloadsViewModel {
        DownloadsViewModel(
            provider: provider,
            urlOpener: RecordingDownloadOpener(),
            fileRevealer: RecordingDownloadRevealer(),
            pasteboard: InMemoryPasteboard()
        )
    }

    private func item(
        name: String,
        addedAt: Date,
        modifiedAt: Date
    ) -> RecentDownloadItem {
        RecentDownloadItem(
            url: URL(fileURLWithPath: "/Downloads/\(name)"),
            addedToDirectoryAt: addedAt,
            createdAt: nil,
            modifiedAt: modifiedAt,
            byteCount: 4_096
        )
    }
}

private struct FixedRecentDownloadsProvider: RecentDownloadsProviding {
    let items: [RecentDownloadItem]

    func recentDownloads(limit: Int) async throws -> [RecentDownloadItem] {
        Array(items.prefix(max(0, limit)))
    }
}

private struct FailingRecentDownloadsProvider: RecentDownloadsProviding {
    func recentDownloads(limit: Int) async throws -> [RecentDownloadItem] {
        _ = limit
        throw RecentDownloadsError.directoryUnavailable
    }
}

private actor RecordingDownloadOpener: URLOpening {
    private var urls: [URL] = []

    func openURL(_ url: URL) async throws {
        urls.append(url)
    }

    func recordedURLs() -> [URL] {
        urls
    }
}

private actor RecordingDownloadRevealer: FileRevealing {
    private var urls: [URL] = []

    func revealInFinder(urls: [URL]) async throws {
        self.urls.append(contentsOf: urls)
    }

    func recordedURLs() -> [URL] {
        urls
    }
}

private actor ControlledRecentDownloadsProvider: RecentDownloadsProviding {
    nonisolated let starts: AsyncStream<Int>
    private let startContinuation: AsyncStream<Int>.Continuation
    private var nextRequest = 0
    private var pending: [Int: CheckedContinuation<[RecentDownloadItem], any Error>] = [:]
    private var cancelled: Set<Int> = []

    init() {
        let pair = AsyncStream<Int>.makeStream()
        starts = pair.stream
        startContinuation = pair.continuation
    }

    func recentDownloads(limit: Int) async throws -> [RecentDownloadItem] {
        _ = limit
        nextRequest += 1
        let request = nextRequest
        startContinuation.yield(request)
        return try await withTaskCancellationHandler {
            try await waitForResponse(request: request)
        } onCancel: {
            Task {
                await self.cancel(request: request)
            }
        }
    }

    func resume(request: Int, with items: [RecentDownloadItem]) {
        pending.removeValue(forKey: request)?.resume(returning: items)
    }

    func cancelledRequests() -> Set<Int> {
        cancelled
    }

    private func waitForResponse(request: Int) async throws -> [RecentDownloadItem] {
        try await withCheckedThrowingContinuation { continuation in
            pending[request] = continuation
        }
    }

    private func cancel(request: Int) {
        cancelled.insert(request)
        pending.removeValue(forKey: request)?.resume(throwing: CancellationError())
    }
}
