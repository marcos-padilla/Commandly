import Foundation
import MarkdownPreviewKit
import Testing
@testable import Commandly

struct MarkdownPreviewModelTests {
    @Test
    func loaderRejectsAnOversizedSourceBeforeDecoding() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let sourceURL = directory.appendingPathComponent("large.md")
        try Data(repeating: 0x61, count: 17).write(to: sourceURL)
        let loader = BoundedMarkdownPreviewFileLoader(
            limits: MarkdownPreviewFileLimits(
                maximumSourceBytes: 16,
                maximumImageCount: 32,
                maximumImageBytes: 100,
                maximumTotalImageBytes: 200
            )
        )

        do {
            _ = try await loader.load(from: sourceURL)
            Issue.record("Expected the source-byte bound to reject the document")
        } catch let error as MarkdownPreviewFileError {
            #expect(error == .sourceTooLarge(maximumBytes: 16))
        } catch {
            Issue.record("Expected a typed MarkdownPreviewFileError")
        }
    }

    @Test
    func loaderDecodesBOMUnicodeAndLegacyText() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let text = "# Résumé"
        let fixtures: [(String, Data, MarkdownPreviewTextEncoding)] = [
            (
                "utf8.md",
                Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8),
                .utf8
            ),
            (
                "utf16-le.md",
                Data([0xFF, 0xFE])
                    + (try #require(text.data(using: .utf16LittleEndian))),
                .utf16LittleEndian
            ),
            (
                "utf32-be.md",
                Data([0x00, 0x00, 0xFE, 0xFF])
                    + (try #require(text.data(using: .utf32BigEndian))),
                .utf32BigEndian
            ),
            (
                "windows.md",
                Data([0x23, 0x20, 0x52, 0xE9, 0x73, 0x75, 0x6D, 0xE9]),
                .windows1252
            ),
        ]
        let loader = BoundedMarkdownPreviewFileLoader()

        for fixture in fixtures {
            let url = directory.appendingPathComponent(fixture.0)
            try fixture.1.write(to: url)
            let loaded = try await loader.load(from: url)
            #expect(loaded.markdown == text)
            #expect(loaded.encoding == fixture.2)
        }
    }

    @Test
    func loaderInlinesOnlyCanonicalContainedImages() async throws {
        let parent = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(parent) }
        let directory = parent.appendingPathComponent("Document")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideURL = parent.appendingPathComponent("outside.png")
        try validPNGData.write(to: outsideURL)
        let nestedDirectory = directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        try validPNGData.write(to: nestedDirectory.appendingPathComponent("safe.png"))
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked.png"),
            withDestinationURL: outsideURL
        )
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked-images"),
            withDestinationURL: nestedDirectory
        )

        let sourceURL = directory.appendingPathComponent("document.md")
        let markdown = """
        ![safe](./images/safe.png)
        ![traversal](../outside.png)
        ![encoded](%2E%2E/outside.png)
        ![absolute](/private/tmp/outside.png)
        ![symlink](linked.png)
        ![nested symlink](linked-images/safe.png)
        """
        try Data(markdown.utf8).write(to: sourceURL)

        let loaded = try await BoundedMarkdownPreviewFileLoader().load(from: sourceURL)

        #expect(loaded.localImageDataURLs.keys.sorted() == ["images/safe.png"])
        #expect(loaded.localImageDataURLs["images/safe.png"]?.hasPrefix("data:image/png;base64,") == true)
        #expect(
            loaded.warnings.filter { $0 == .unsafeImageReference }.count == 5
        )
        #expect(loaded.localImageDataURLs.values.allSatisfy { $0.contains(outsideURL.path) == false })
    }

    @Test
    func loaderStopsAtImageCountPerImageAndTotalByteBounds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try validPNGData.write(to: directory.appendingPathComponent("one.png"))
        try validPNGData.write(to: directory.appendingPathComponent("two.png"))

        let countSource = directory.appendingPathComponent("count.md")
        try Data("![one](one.png)\n![two](two.png)".utf8).write(to: countSource)
        let countLoader = BoundedMarkdownPreviewFileLoader(
            limits: MarkdownPreviewFileLimits(
                maximumSourceBytes: 1_024,
                maximumImageCount: 1,
                maximumImageBytes: validPNGData.count,
                maximumTotalImageBytes: validPNGData.count
            )
        )
        let countLoaded = try await countLoader.load(from: countSource)
        #expect(countLoaded.localImageDataURLs.count == 1)
        #expect(countLoaded.warnings.contains(.imageCountLimitReached(maximum: 1)))

        let imageLoader = BoundedMarkdownPreviewFileLoader(
            limits: MarkdownPreviewFileLimits(
                maximumSourceBytes: 1_024,
                maximumImageCount: 2,
                maximumImageBytes: 7,
                maximumTotalImageBytes: validPNGData.count * 2
            )
        )
        let imageLoaded = try await imageLoader.load(from: countSource)
        #expect(imageLoaded.localImageDataURLs.isEmpty)
        #expect(
            imageLoaded.warnings.filter {
                $0 == .imageTooLarge(maximumBytes: 7)
            }.count == 2
        )

        let totalLoader = BoundedMarkdownPreviewFileLoader(
            limits: MarkdownPreviewFileLimits(
                maximumSourceBytes: 1_024,
                maximumImageCount: 2,
                maximumImageBytes: validPNGData.count,
                maximumTotalImageBytes: validPNGData.count
            )
        )
        let totalLoaded = try await totalLoader.load(from: countSource)
        #expect(totalLoaded.localImageDataURLs.count == 1)
        #expect(
            totalLoaded.warnings.contains(
                .totalImageBytesLimitReached(maximumBytes: validPNGData.count)
            )
        )
    }

    @Test
    func loaderRejectsMalformedAndExcessiveDecodedImagePayloads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try oversizedPNGData.write(to: directory.appendingPathComponent("oversized.png"))
        try validPNGData.prefix(8).write(to: directory.appendingPathComponent("malformed.png"))

        let sourceURL = directory.appendingPathComponent("images.md")
        try Data(
            "![oversized](oversized.png)\n![malformed](malformed.png)".utf8
        ).write(to: sourceURL)

        let loaded = try await BoundedMarkdownPreviewFileLoader().load(from: sourceURL)

        #expect(loaded.localImageDataURLs.isEmpty)
        #expect(loaded.warnings.filter { $0 == .unsupportedImageType }.count == 2)
    }

    @Test
    func scrollStorePersistsOnlyAHashedBoundedDocumentIdentifier() async throws {
        let suiteName = "CommandlyTests.MarkdownPreview.\(UUID().uuidString)"
        let key = "scroll"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sourceURL = URL(
            fileURLWithPath: "/private/user-documents/sensitive-project/notes.md"
        )
        let store = UserDefaultsMarkdownPreviewScrollStore(
            suiteName: suiteName,
            key: key,
            maximumRecordCount: 2
        )

        await store.setScrollPosition(123, for: sourceURL)

        let payload = try #require(defaults.array(forKey: key))
        let record = try #require(payload.first as? [String: Any])
        let identifier = try #require(record["identifier"] as? String)
        #expect(identifier.count == 64)
        #expect(identifier.contains(sourceURL.path) == false)
        #expect(String(describing: payload).contains(sourceURL.path) == false)
        #expect(await store.scrollPosition(for: sourceURL) == 123)
    }

    @Test @MainActor
    func staleAndCancelledLoadsCannotReplaceTheNewestDocument() async {
        let loader = ControlledMarkdownPreviewLoader()
        let renderer = StubMarkdownPreviewRenderer()
        let webController = RecordingMarkdownPreviewWebController()
        let model = MarkdownPreviewViewModel(
            loader: loader,
            renderer: renderer,
            watcher: NoopMarkdownPreviewFileWatcher(),
            scrollStore: InMemoryMarkdownPreviewScrollStore(),
            webController: webController
        )
        let firstURL = URL(fileURLWithPath: "/tmp/markdown-preview-first.md")
        let secondURL = URL(fileURLWithPath: "/tmp/markdown-preview-second.md")

        model.open(firstURL)
        await loader.waitUntilRequested("markdown-preview-first.md")
        model.open(secondURL)
        await loader.waitUntilRequested("markdown-preview-second.md")
        await loader.complete(
            "markdown-preview-second.md",
            markdown: "# Newest"
        )
        await model.waitForLoadForTesting()

        #expect(model.document?.source.markdown == "# Newest")
        #expect(webController.loadedHTML.last?.contains("# Newest") == true)

        await loader.complete(
            "markdown-preview-first.md",
            markdown: "# Stale"
        )
        await loader.waitUntilFinished("markdown-preview-first.md")

        #expect(await loader.wasCancelled("markdown-preview-first.md"))
        #expect(model.document?.source.markdown == "# Newest")
        #expect(webController.loadedHTML.last?.contains("# Newest") == true)
    }

    @Test @MainActor
    func failedLoadCanRetryAfterTheDocumentBecomesAvailable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let sourceURL = directory.appendingPathComponent("retry.md")
        let model = MarkdownPreviewViewModel(
            loader: BoundedMarkdownPreviewFileLoader(),
            renderer: StubMarkdownPreviewRenderer(),
            watcher: NoopMarkdownPreviewFileWatcher(),
            scrollStore: InMemoryMarkdownPreviewScrollStore(),
            webController: RecordingMarkdownPreviewWebController()
        )

        model.open(sourceURL)
        await model.waitForLoadForTesting()
        guard case .failure = model.state else {
            Issue.record("Expected the missing document to fail its first load")
            return
        }

        try Data("# Available now".utf8).write(to: sourceURL)
        model.reload()
        await model.waitForLoadForTesting()

        #expect(model.document?.source.markdown == "# Available now")
    }

    @Test @MainActor
    func modelRoutesSearchOutlineZoomSourceAndExportActions() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/markdown-preview-actions.md")
        let loader = ImmediateMarkdownPreviewLoader(markdown: "# Actions")
        let webController = RecordingMarkdownPreviewWebController()
        webController.pdfData = Data([1, 2, 3])
        webController.scrollPosition = 42
        let scrollStore = InMemoryMarkdownPreviewScrollStore()
        await scrollStore.setScrollPosition(17, for: sourceURL)
        let model = MarkdownPreviewViewModel(
            loader: loader,
            renderer: StubMarkdownPreviewRenderer(),
            watcher: NoopMarkdownPreviewFileWatcher(),
            scrollStore: scrollStore,
            webController: webController
        )

        model.open(sourceURL)
        await model.waitForLoadForTesting()
        await model.waitForScrollStateForTesting()
        #expect(webController.restoredScrollPositions == [17])
        let entry = try #require(model.outline.first)
        model.selectOutlineEntry(entry)
        model.searchQuery = "Actions"
        model.searchOptions.usesRegularExpression = true
        model.findPrevious()
        model.toggleSource()
        model.setZoom(99)
        model.requestHTMLExport()

        #expect(webController.scrolledAnchors == [entry.anchor])
        #expect(webController.findRequests.last?.query == "Actions")
        #expect(webController.findRequests.last?.options.searchesBackwards == true)
        #expect(webController.findRequests.last?.options.usesRegularExpression == true)
        #expect(webController.sourceVisibility.last == true)
        #expect(model.zoom == MarkdownPreviewConfiguration.zoomRange.upperBound)
        #expect(model.showsHTMLExporter)
        #expect(model.htmlExportData != nil)

        model.completeHTMLExport(.success(URL(fileURLWithPath: "/tmp/actions.html")))
        model.requestPDFExport()
        await model.waitForActionForTesting()
        #expect(model.documentActionState == .idle)
        #expect(model.pdfExportData == Data([1, 2, 3]))
        #expect(model.showsPDFExporter)

        model.completePDFExport(.success(URL(fileURLWithPath: "/tmp/actions.pdf")))
        model.requestPrint()
        await model.waitForActionForTesting()
        #expect(webController.printRequestCount == 1)
        #expect(model.documentActionState == .idle)

        model.stop()
        await model.waitForScrollStateForTesting()
        #expect(model.state == .empty)
        #expect(webController.loadedHTML.last == "")
        #expect(await scrollStore.scrollPosition(for: sourceURL) == 42)
    }

    @Test @MainActor
    func stopIsIdempotentAndPersistsScrollExactlyOnce() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/markdown-preview-stop.md")
        let webController = RecordingMarkdownPreviewWebController()
        webController.scrollPosition = 73
        let scrollStore = InMemoryMarkdownPreviewScrollStore()
        let model = MarkdownPreviewViewModel(
            loader: ImmediateMarkdownPreviewLoader(markdown: "# Stop"),
            renderer: StubMarkdownPreviewRenderer(),
            watcher: NoopMarkdownPreviewFileWatcher(),
            scrollStore: scrollStore,
            webController: webController
        )

        model.open(sourceURL)
        await model.waitForLoadForTesting()
        model.stop()
        model.stop()
        await model.waitForScrollStateForTesting()

        #expect(await scrollStore.scrollPosition(for: sourceURL) == 73)
        #expect(webController.loadedHTML.filter(\.isEmpty).count == 1)
    }

    @Test @MainActor
    func automaticReloadHonorsTheConfigurationSwitch() async {
        let loader = CountingMarkdownPreviewLoader(markdown: "# Reload")
        let watcher = ControllableMarkdownPreviewWatcher()
        let model = MarkdownPreviewViewModel(
            loader: loader,
            renderer: StubMarkdownPreviewRenderer(),
            watcher: watcher,
            scrollStore: InMemoryMarkdownPreviewScrollStore(),
            webController: RecordingMarkdownPreviewWebController(),
            autoReload: false
        )
        model.open(URL(fileURLWithPath: "/tmp/markdown-preview-reload.md"))
        await model.waitForLoadForTesting()
        await watcher.waitUntilObserved()

        #expect(model.autoReload == false)
        #expect(await loader.requestCount() == 1)

        model.setAutoReload(true)
        await watcher.send(.contentsChanged)
        await loader.waitForRequestCount(2)
        await model.waitForLoadForTesting()
        #expect(await loader.requestCount() == 2)
    }
}

nonisolated private let validPNGData = Data([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x04, 0x00, 0x00, 0x00, 0xB5, 0x1C, 0x0C, 0x02, 0x00, 0x00, 0x00,
    0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0x64, 0xF8, 0x0F, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x27, 0x18, 0xE3, 0x66, 0x00, 0x00, 0x00, 0x00,
    0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
])

nonisolated private let oversizedPNGData = replacingPNGDimensions(
    in: validPNGData,
    width: 10_000,
    height: 10_000
)

nonisolated private func replacingPNGDimensions(
    in data: Data,
    width: UInt32,
    height: UInt32
) -> Data {
    var bytes = [UInt8](data)
    guard bytes.count >= 33 else { return Data() }

    bytes.replaceSubrange(16 ..< 20, with: bigEndianBytes(width))
    bytes.replaceSubrange(20 ..< 24, with: bigEndianBytes(height))
    let checksum = pngCRC32(bytes[12 ..< 29])
    bytes.replaceSubrange(29 ..< 33, with: bigEndianBytes(checksum))
    return Data(bytes)
}

nonisolated private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
}

nonisolated private func pngCRC32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    var checksum = UInt32.max
    for byte in bytes {
        checksum ^= UInt32(byte)
        for _ in 0 ..< 8 {
            let mask = UInt32(0) &- (checksum & 1)
            checksum = (checksum >> 1) ^ (0xEDB8_8320 & mask)
        }
    }
    return ~checksum
}

nonisolated private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Commandly-MarkdownPreview-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

nonisolated private func removeTemporaryDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

nonisolated private func makeLoadedSource(
    url: URL,
    markdown: String
) -> MarkdownPreviewLoadedSource {
    MarkdownPreviewLoadedSource(
        sourceURL: url.standardizedFileURL,
        displayName: url.lastPathComponent,
        markdown: markdown,
        encoding: .utf8,
        sourceByteCount: markdown.utf8.count,
        localImageDataURLs: [:],
        warnings: []
    )
}

private actor ImmediateMarkdownPreviewLoader: MarkdownPreviewFileLoading {
    private let markdown: String

    init(markdown: String) {
        self.markdown = markdown
    }

    func load(from sourceURL: URL) -> MarkdownPreviewLoadedSource {
        makeLoadedSource(url: sourceURL, markdown: markdown)
    }
}

private actor ControlledMarkdownPreviewLoader: MarkdownPreviewFileLoading {
    private var continuations: [
        String: CheckedContinuation<MarkdownPreviewLoadedSource, Never>
    ] = [:]
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var finishWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var finished: Set<String> = []
    private var cancelled: Set<String> = []

    func load(from sourceURL: URL) async -> MarkdownPreviewLoadedSource {
        let filename = sourceURL.lastPathComponent
        let source = await withCheckedContinuation { continuation in
            continuations[filename] = continuation
            for waiter in requestWaiters.removeValue(forKey: filename) ?? [] {
                waiter.resume()
            }
        }
        if Task.isCancelled {
            cancelled.insert(filename)
        }
        finished.insert(filename)
        for waiter in finishWaiters.removeValue(forKey: filename) ?? [] {
            waiter.resume()
        }
        return source
    }

    func waitUntilRequested(_ filename: String) async {
        guard continuations[filename] == nil else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[filename, default: []].append(continuation)
        }
    }

    func complete(_ filename: String, markdown: String) {
        let url = URL(fileURLWithPath: "/tmp/\(filename)")
        continuations.removeValue(forKey: filename)?.resume(
            returning: makeLoadedSource(url: url, markdown: markdown)
        )
    }

    func waitUntilFinished(_ filename: String) async {
        guard finished.contains(filename) == false else { return }
        await withCheckedContinuation { continuation in
            finishWaiters[filename, default: []].append(continuation)
        }
    }

    func wasCancelled(_ filename: String) -> Bool {
        cancelled.contains(filename)
    }
}

private actor StubMarkdownPreviewRenderer: MarkdownPreviewRendering {
    func render(
        source: MarkdownPreviewLoadedSource,
        configuration: MarkdownPreviewConfiguration
    ) -> MarkdownRenderedDocument {
        _ = configuration
        return MarkdownRenderedDocument(
            html: "<html><body>\(source.markdown)</body></html>",
            outline: [
                MarkdownOutlineEntry(level: 1, title: "Heading", anchor: "heading")
            ],
            frontMatter: []
        )
    }
}

private actor CountingMarkdownPreviewLoader: MarkdownPreviewFileLoading {
    private let markdown: String
    private var count = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(markdown: String) {
        self.markdown = markdown
    }

    func load(from sourceURL: URL) -> MarkdownPreviewLoadedSource {
        count += 1
        let ready = waiters.filter { count >= $0.count }
        waiters.removeAll { count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
        return makeLoadedSource(url: sourceURL, markdown: markdown)
    }

    func requestCount() -> Int {
        count
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            waiters.append((expectedCount, continuation))
        }
    }
}

private actor ControllableMarkdownPreviewWatcher: MarkdownPreviewFileWatching {
    private var continuation: AsyncStream<MarkdownPreviewFileChange>.Continuation?
    private var observationWaiters: [CheckedContinuation<Void, Never>] = []

    func changes(for sourceURL: URL) -> AsyncStream<MarkdownPreviewFileChange> {
        _ = sourceURL
        let streamPair = AsyncStream<MarkdownPreviewFileChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation = streamPair.continuation
        for waiter in observationWaiters {
            waiter.resume()
        }
        observationWaiters.removeAll()
        return streamPair.stream
    }

    func waitUntilObserved() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            observationWaiters.append(continuation)
        }
    }

    func send(_ change: MarkdownPreviewFileChange) {
        continuation?.yield(change)
    }
}

@MainActor
private final class RecordingMarkdownPreviewWebController: MarkdownPreviewWebControlling {
    struct FindRequest {
        let query: String
        let options: MarkdownPreviewSearchOptions
    }

    var loadedHTML: [String] = []
    var findRequests: [FindRequest] = []
    var sourceVisibility: [Bool] = []
    var zoomValues: [Double] = []
    var scrolledAnchors: [String] = []
    var restoredScrollPositions: [Double] = []
    var scrollPosition: Double?
    var pdfData = Data()
    var printRequestCount = 0

    func loadHTML(_ html: String, baseURL: URL?) {
        _ = baseURL
        loadedHTML.append(html)
    }

    func find(_ query: String, options: MarkdownPreviewSearchOptions) {
        findRequests.append(FindRequest(query: query, options: options))
    }

    func clearFind() {}

    func setSource(_ source: String, isVisible: Bool) {
        _ = source
        sourceVisibility.append(isVisible)
    }

    func setZoom(_ zoom: Double) {
        zoomValues.append(zoom)
    }

    func scrollTo(anchor: String) {
        scrolledAnchors.append(anchor)
    }

    func currentScrollPosition() -> Double? {
        scrollPosition
    }

    func restoreScrollPosition(_ position: Double) {
        restoredScrollPositions.append(position)
    }

    func makePDF() async throws -> Data {
        pdfData
    }

    func printDocument() async throws {
        printRequestCount += 1
    }
}
