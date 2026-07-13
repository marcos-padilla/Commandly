import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ProductivityLibraryTests {
    @Test @MainActor
    func jsonStoreRoundTripsVersionedItemsAtInjectedApplicationSupportURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Commandly-ProductivityLibraryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("ProductivityLibrary.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProductivityLibraryStore(fileURL: fileURL)
        let item = try makeItem(
            id: "11111111-1111-1111-1111-111111111111",
            kind: .snippet,
            title: "Greeting",
            content: "Hello, {{clipboard}}",
            timestamp: 100
        )

        try await store.saveItems([item])
        let loaded = try await store.loadItems()

        #expect(loaded == [item])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func quicklinkValidatorAcceptsNativeTargetsAndRejectsExecutablePayloads() throws {
        let validator = ProductivityQuicklinkValidator()

        #expect(
            try validator.validatedURL(from: "https://example.com/path?q=1").absoluteString
                == "https://example.com/path?q=1"
        )
        #expect(
            try validator.validatedURL(from: "file:///tmp/Commandly Notes/").isFileURL
        )
        #expect(
            try validator.validatedURL(from: "/tmp/Commandly Notes").path
                == "/tmp/Commandly Notes"
        )
        #expect(
            try validator.validatedURL(from: "things:///show?id=123").scheme == "things"
        )
        #expect(throws: ProductivityLibraryValidationError.invalidQuicklink) {
            try validator.validatedURL(from: "javascript:alert(1)")
        }
        #expect(throws: ProductivityLibraryValidationError.invalidQuicklink) {
            try validator.validatedURL(from: "data:text/plain,private")
        }
        #expect(throws: ProductivityLibraryValidationError.invalidQuicklink) {
            try validator.validatedURL(from: "https:///missing-host")
        }
        #expect(throws: ProductivityLibraryValidationError.invalidQuicklink) {
            try validator.validatedURL(from: "relative/path")
        }
    }

    @Test @MainActor
    func modelCompletesCreateSearchEditAndDeleteWorkflowTransactionally() async throws {
        let store = InMemoryProductivityLibraryStore()
        let fixedID = try #require(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let model = makeModel(
            persistence: store,
            now: { Date(timeIntervalSince1970: 500) },
            makeID: { fixedID }
        )
        await model.load()

        model.beginCreating(kind: .quickNote)
        model.draft.title = "  Standup  "
        model.draft.content = "Yesterday: tests\nToday: implementation"
        model.saveDraft()
        await model.flushPersistenceForTesting()

        #expect(model.items.count == 1)
        #expect(model.selectedItem?.id == fixedID)
        #expect(model.selectedItem?.title == "Standup")
        #expect(model.editorMode == nil)
        #expect(await store.snapshot() == model.items)

        model.query = "implementation"
        #expect(model.filteredItems.map(\.id) == [fixedID])
        model.filter = .snippets
        #expect(model.filteredItems.isEmpty)
        model.filter = .quickNotes
        #expect(model.filteredItems.map(\.id) == [fixedID])
        model.query = ""

        model.beginEditingSelected()
        #expect(model.editorMode == .editing(fixedID))
        model.draft.kind = .snippet
        model.draft.title = "Standup Template"
        model.draft.content = "Notes: {{clipboard}}"
        model.saveDraft()
        await model.flushPersistenceForTesting()

        #expect(model.selectedItem?.kind == .snippet)
        #expect(model.selectedItem?.content == "Notes: {{clipboard}}")
        #expect(await store.saveCount == 2)

        model.requestDeleteSelected()
        #expect(model.pendingDeletionItem?.id == fixedID)
        model.confirmDelete()
        await model.flushPersistenceForTesting()

        #expect(model.items.isEmpty)
        #expect(await store.snapshot().isEmpty)
        #expect(await store.saveCount == 3)
    }

    @Test @MainActor
    func primaryActionsExpandClipboardCopyLocalItemsAndOpenValidatedDeeplinks() async throws {
        let snippetID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let noteID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let emojiID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let linkID = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let items = [
            ProductivityLibraryItem(
                id: snippetID,
                kind: .snippet,
                title: "Wrap",
                content: "before {{clipboard}} after",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 4)
            ),
            ProductivityLibraryItem(
                id: noteID,
                kind: .quickNote,
                title: "Reminder",
                content: "Call the studio",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 3)
            ),
            ProductivityLibraryItem(
                id: emojiID,
                kind: .emojiKeyword,
                title: "celebrate",
                content: "🎉",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            ProductivityLibraryItem(
                id: linkID,
                kind: .quicklink,
                title: "Open Task",
                content: "things:///show?id=123",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        let pasteboard = InMemoryPasteboard(initial: "source")
        let opener = RecordingProductivityLibraryURLOpener()
        var dismissed = false
        let model = makeModel(
            persistence: InMemoryProductivityLibraryStore(items: items),
            pasteboard: pasteboard,
            urlOpener: opener,
            onDismiss: { dismissed = true }
        )
        await model.load()

        model.select(snippetID)
        model.perform(ProductivityLibraryActionID.useSelected)
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "before source after")

        model.select(noteID)
        model.perform(ProductivityLibraryActionID.useSelected)
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "Call the studio")

        model.select(emojiID)
        model.perform(ProductivityLibraryActionID.useSelected)
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "🎉")

        model.select(linkID)
        model.perform(ProductivityLibraryActionID.useSelected)
        await model.flushPrimaryActionForTesting()
        #expect(await opener.openedURLs.map(\.absoluteString) == ["things:///show?id=123"])
        #expect(dismissed)
    }

    @Test @MainActor
    func invalidQuicklinksCannotBeSavedOrOpened() async throws {
        let unsafeID = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let store = InMemoryProductivityLibraryStore()
        let model = makeModel(persistence: store)
        await model.load()

        model.beginCreating(kind: .quicklink)
        model.draft.title = "Unsafe"
        model.draft.content = "javascript:alert(1)"

        #expect(model.canSaveDraft == false)
        #expect(model.draftValidationMessage != nil)
        model.saveDraft()
        #expect(model.items.isEmpty)
        #expect(await store.saveCount == 0)

        let unsafeItem = ProductivityLibraryItem(
            id: unsafeID,
            kind: .quicklink,
            title: "Legacy Unsafe Item",
            content: "data:text/plain,private",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let opener = RecordingProductivityLibraryURLOpener()
        let legacyModel = makeModel(
            persistence: InMemoryProductivityLibraryStore(items: [unsafeItem]),
            urlOpener: opener
        )
        await legacyModel.load()
        legacyModel.perform(ProductivityLibraryActionID.useSelected)
        await legacyModel.flushPrimaryActionForTesting()

        #expect(await opener.openedURLs.isEmpty)
        #expect(legacyModel.statusMessage == "This Quicklink uses an invalid or unsafe URL.")
    }

    @Test @MainActor
    func registeredApplicationCreatesTypedSessionWithoutLauncherBranches() throws {
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        try registry.register(
            ProductivityLibraryApplication(
                services: ProductivityLibraryApplicationServices(
                    persistence: InMemoryProductivityLibraryStore(),
                    pasteboard: InMemoryPasteboard(),
                    urlOpener: RecordingProductivityLibraryURLOpener()
                )
            )
        )
        let launcher = LauncherViewModel(
            applicationRegistry: registry,
            placeholderItems: []
        )

        launcher.launch(ProductivityLibraryApplication.id)

        #expect(launcher.route == .application(ProductivityLibraryApplication.id))
        #expect(
            launcher.activeApplicationModel(as: ProductivityLibraryViewModel.self) != nil
        )
        #expect(launcher.contextTitle == "Productivity Library")
    }

    @Test @MainActor
    func stoppingSessionCancelsBlockedPersistenceBeforeItCommits() async throws {
        let store = SuspendedProductivityLibraryStore()
        let fixedID = try #require(
            UUID(uuidString: "88888888-8888-8888-8888-888888888888")
        )
        let model = makeModel(
            persistence: store,
            makeID: { fixedID }
        )
        await model.load()
        model.beginCreating(kind: .snippet)
        model.draft.title = "Cancelled"
        model.draft.content = "This must not commit"

        model.saveDraft()
        await store.waitUntilSaveStarts()
        model.stop()
        await store.releaseSave()
        await model.flushPersistenceForTesting()

        #expect(await store.snapshot().isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.editorMode == .creating)
    }

    @MainActor
    private func makeModel(
        persistence: any ProductivityLibraryPersisting,
        pasteboard: any PasteboardAccessing = InMemoryPasteboard(),
        urlOpener: any URLOpening = RecordingProductivityLibraryURLOpener(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) },
        makeID: @escaping () -> UUID = { UUID() },
        onDismiss: @escaping () -> Void = {}
    ) -> ProductivityLibraryViewModel {
        ProductivityLibraryViewModel(
            services: ProductivityLibraryApplicationServices(
                persistence: persistence,
                pasteboard: pasteboard,
                urlOpener: urlOpener,
                now: now,
                makeID: makeID
            ),
            onGoBack: {},
            onDismiss: onDismiss
        )
    }

    private func makeItem(
        id: String,
        kind: ProductivityLibraryItemKind,
        title: String,
        content: String,
        timestamp: TimeInterval
    ) throws -> ProductivityLibraryItem {
        ProductivityLibraryItem(
            id: try #require(UUID(uuidString: id)),
            kind: kind,
            title: title,
            content: content,
            createdAt: Date(timeIntervalSince1970: timestamp),
            updatedAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}

private actor RecordingProductivityLibraryURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []

    func openURL(_ url: URL) async throws {
        openedURLs.append(url)
    }
}

private actor SuspendedProductivityLibraryStore: ProductivityLibraryPersisting {
    private var items: [ProductivityLibraryItem] = []
    private var didStartSaving = false
    private var saveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveRelease: CheckedContinuation<Void, Never>?

    func loadItems() async throws -> [ProductivityLibraryItem] {
        items
    }

    func saveItems(_ items: [ProductivityLibraryItem]) async throws {
        didStartSaving = true
        let waiters = saveStartWaiters
        saveStartWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            saveRelease = continuation
        }
        try Task.checkCancellation()
        self.items = items
    }

    func waitUntilSaveStarts() async {
        if didStartSaving { return }
        await withCheckedContinuation { continuation in
            saveStartWaiters.append(continuation)
        }
    }

    func releaseSave() {
        saveRelease?.resume()
        saveRelease = nil
    }

    func snapshot() -> [ProductivityLibraryItem] {
        items
    }
}
