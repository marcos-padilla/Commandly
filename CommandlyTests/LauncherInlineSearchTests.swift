import AppKit
import CalculatorKit
import Foundation
import Infrastructure
import SearchKit
import Testing
@testable import Commandly

@MainActor
struct LauncherInlineSearchTests {
    @Test func rootSearchSurfacesBoundedClipboardAndFileResultsWithoutAutocompletingPrivateRows()
        async throws
    {
        let entryID = UUID()
        let store = ClipboardHistoryStore()
        store.replaceEntriesForTesting([
            ClipboardHistoryEntry(
                id: entryID,
                createdAt: Date(timeIntervalSince1970: 10),
                contentType: .text,
                preview: "Roadmap private draft",
                text: "Roadmap private draft",
                imageTIFFData: nil,
                fileURLs: [],
                sourceAppName: "Notes",
                sourceBundleIdentifier: "com.apple.Notes"
            )
        ])
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/Roadmap.md")
        let fileService = InMemoryFileSearchService(items: [
            FileSearchItem(
                url: fileURL,
                name: "Roadmap.md",
                parentPath: "/Users/test/Documents",
                kind: .file,
                contentTypeDescription: "Markdown document"
            )
        ])
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: store,
            fileSearchService: fileService,
            placeholderItems: []
        )

        viewModel.query = "roadmap"
        await viewModel.flushSearchForTesting()

        #expect(viewModel.rootItems.contains {
            $0.id == "clipboard:\(entryID.uuidString.lowercased())"
                && $0.section == .clipboard
        })
        #expect(viewModel.rootItems.contains {
            $0.id == "file:\(fileURL.path)" && $0.section == .files
        })
        let request = try #require(await fileService.requests.last)
        #expect(request.query.text == "roadmap")
        #expect(request.query.limit == 10)
        #expect(viewModel.autocompleteCompletion != "Roadmap private draft")
        #expect(viewModel.autocompleteCompletion != "Roadmap.md")
    }

    @Test func clipboardInlineResultReResolvesAndCopiesTheLiveEntry() async throws {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.inline-clipboard.\(UUID().uuidString)")
        )
        let entry = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .text,
            preview: "needle",
            text: "needle value",
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: "Editor",
            sourceBundleIdentifier: "com.example.editor"
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        store.replaceEntriesForTesting([entry])
        var dismissCount = 0
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: store,
            placeholderItems: [],
            onDismiss: { dismissCount += 1 }
        )

        viewModel.query = "needle"
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = "clipboard:\(entry.id.uuidString.lowercased())"
        await viewModel.confirmSelectionAndWaitForTesting()

        #expect(pasteboard.string(forType: .string) == "needle value")
        #expect(store.entries == [entry])
        #expect(dismissCount == 1)
    }

    @Test func fileInlineResultOpensItsExactURLAndDismissesOnlyOnSuccess() async throws {
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/Needle.pdf")
        let fileService = InMemoryFileSearchService(items: [
            FileSearchItem(
                url: fileURL,
                name: "Needle.pdf",
                parentPath: "/Users/test/Documents",
                kind: .file,
                contentTypeDescription: "PDF document"
            )
        ])
        let opener = RecordingInlineURLOpener()
        var dismissCount = 0
        let viewModel = LauncherViewModel(
            fileSearchService: fileService,
            urlOpener: opener,
            placeholderItems: [],
            onDismiss: { dismissCount += 1 }
        )

        viewModel.query = "needle"
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = "file:\(fileURL.path)"
        await viewModel.confirmSelectionAndWaitForTesting()

        #expect(await opener.openedURLs == [fileURL])
        #expect(dismissCount == 1)
    }

    @Test func missingFileAccessKeepsOtherResultsAndOffersPermissionsRecovery() async {
        var dismissCount = 0
        var permissionsCount = 0
        let viewModel = LauncherViewModel(
            fileSearchService: FailingInlineFileSearchService(),
            placeholderItems: [],
            onDismiss: { dismissCount += 1 },
            onOpenPermissionsSettings: { permissionsCount += 1 }
        )

        viewModel.query = "picker"
        await viewModel.flushSearchForTesting()

        #expect(viewModel.rootItems.contains {
            $0.title == "Color Tools" && $0.section == .suggestions
        })
        #expect(viewModel.rootItems.contains {
            $0.id == "file-search-permission-required"
                && $0.section == .files
                && $0.action == .openFileSearchPermissions
        })

        viewModel.selectedID = "file-search-permission-required"
        await viewModel.confirmSelectionAndWaitForTesting()

        #expect(dismissCount == 1)
        #expect(permissionsCount == 1)
    }

    @Test func staleFileResultsCannotReplaceANewerQuery() async throws {
        let fileService = QueryEchoInlineFileSearchService()
        let viewModel = LauncherViewModel(
            fileSearchService: fileService,
            placeholderItems: []
        )

        viewModel.query = "old"
        await fileService.waitUntilRequested("old")
        viewModel.query = "new"
        await viewModel.flushSearchForTesting()
        await fileService.waitUntilIdle()

        #expect(viewModel.rootItems.contains { $0.title == "new.txt" })
        #expect(viewModel.rootItems.contains { $0.title == "old.txt" } == false)
    }

    @Test func dismissalClearsQueryWithoutSchedulingHiddenSearchWork() async {
        let calculator = RecordingInlineCalculator()
        let viewModel = LauncherViewModel(
            calculator: calculator,
            placeholderItems: []
        )

        viewModel.query = "lifecycle"
        await viewModel.flushSearchForTesting()
        let evaluationCountBeforeDismissal = await calculator.evaluationCount

        viewModel.resetAfterDismiss()
        for _ in 0..<4 {
            await Task.yield()
        }

        #expect(viewModel.query.isEmpty)
        #expect(await calculator.evaluationCount == evaluationCountBeforeDismissal)
    }

    @Test func clipboardSearchUsesCapturedMetadataAndHonorsTheLimit() {
        let store = ClipboardHistoryStore()
        store.replaceEntriesForTesting([
            clipboardEntry(
                preview: "Image",
                searchableText: "Quarterly invoice",
                labels: ["Document"],
                source: "Preview",
                timestamp: 3
            ),
            clipboardEntry(
                preview: "Invoice summary",
                searchableText: nil,
                labels: [],
                source: "Notes",
                timestamp: 2
            ),
            clipboardEntry(
                preview: "Meeting notes",
                searchableText: nil,
                labels: [],
                source: "Finder",
                timestamp: 1
            ),
        ])

        let results = store.searchEntries(matching: "invoice", limit: 2)

        #expect(results.count == 2)
        #expect(results.first?.preview == "Invoice summary")
        #expect(results.contains { $0.searchableText == "Quarterly invoice" })
        #expect(store.searchEntries(matching: "preview", limit: 1).first?.sourceAppName == "Preview")
    }

    private func clipboardEntry(
        preview: String,
        searchableText: String?,
        labels: [String],
        source: String,
        timestamp: TimeInterval
    ) -> ClipboardHistoryEntry {
        ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: timestamp),
            contentType: .image,
            preview: preview,
            text: nil,
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: source,
            sourceBundleIdentifier: nil,
            searchableText: searchableText,
            classificationLabels: labels,
            enrichmentStatus: .ready
        )
    }
}

private actor RecordingInlineURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []

    func openURL(_ url: URL) async throws {
        openedURLs.append(url)
    }
}

private struct FailingInlineFileSearchService: FileSearching {
    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        _ = request
        throw FileSearchError.noAuthorizedScopes
    }
}

private actor QueryEchoInlineFileSearchService: FileSearching {
    private var activeRequestCount = 0
    private var requestedQueries: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        activeRequestCount += 1
        requestedQueries.insert(request.query.text)
        requestWaiters.removeValue(forKey: request.query.text)?.forEach { $0.resume() }
        defer {
            activeRequestCount -= 1
            if activeRequestCount == 0 {
                idleWaiters.forEach { $0.resume() }
                idleWaiters.removeAll()
            }
        }
        if request.query.text == "old" {
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let name = "\(request.query.text).txt"
        return [
            FileSearchItem(
                url: URL(fileURLWithPath: "/Users/test/\(name)"),
                name: name,
                parentPath: "/Users/test",
                kind: .file,
                contentTypeDescription: "Text document"
            )
        ]
    }

    func waitUntilRequested(_ query: String) async {
        guard requestedQueries.contains(query) == false else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[query, default: []].append(continuation)
        }
    }

    func waitUntilIdle() async {
        guard activeRequestCount > 0 else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }
}

private actor RecordingInlineCalculator: CalculatorEvaluating {
    private(set) var evaluationCount = 0

    func evaluate(
        _ input: String,
        context: CalculatorEvaluationContext
    ) async -> CalculatorEvaluationOutcome {
        _ = input
        _ = context
        evaluationCount += 1
        return .notCalculator
    }
}
