import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Concurrent productivity library edits", .timeLimit(.minutes(1)))
@MainActor
struct ProductivityLibraryMutationTests {
    @Test(arguments: [false, true])
    func independentWritesPreserveOtherNotesAndTemplateMetadata(useJSON: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: any ProductivityLibraryPersisting = useJSON
            ? JSONProductivityLibraryStore(fileURL: directory.appendingPathComponent("Library.json"))
            : InMemoryProductivityLibraryStore()
        let first = Self.item(title: "First")
        let second = Self.item(title: "Second")
        var snippet = Self.item(title: "Template")
        snippet.kind = .snippet
        snippet.content = "Hello {{name}}, {{clipboard}}"
        snippet.tags = ["Work", "Reusable"]
        try await store.saveItems([first, second, snippet])
        var editedFirst = first
        editedFirst.content = "First writer"
        var editedSecond = second
        editedSecond.content = "Second writer"

        let firstChanges: [ProductivityLibraryMutation] = [.replace(editedFirst, expected: first)]
        let secondChanges: [ProductivityLibraryMutation] = [.replace(editedSecond, expected: second)]
        async let firstWrite = store.applyChanges(firstChanges)
        async let secondWrite = store.applyChanges(secondChanges)
        _ = try await (firstWrite, secondWrite)
        let saved = try await store.loadItems()
        #expect(saved.first(where: { $0.id == first.id }) == editedFirst)
        #expect(saved.first(where: { $0.id == second.id }) == editedSecond)
        #expect(saved.first(where: { $0.id == snippet.id }) == snippet)

        await #expect(throws: ProductivityLibraryPersistenceError.conflict) {
            try await store.applyChanges([.replace(first, expected: first)])
        }
        #expect(try await store.loadItems() == saved)
    }

    @Test
    func failedTransactionsNeverPartiallyCreateOrDeleteItems() async throws {
        let original = Self.item(title: "Saved note")
        let store = InMemoryProductivityLibraryStore(items: [original])
        let created = Self.item(title: "New note")
        var stale = original
        stale.content = "An older draft"
        await #expect(throws: ProductivityLibraryPersistenceError.conflict) {
            try await store.applyChanges([.create(created), .delete(expected: stale)])
        }
        #expect(await store.snapshot() == [original])
        #expect(await store.saveCount == 0)
        _ = try await store.applyChanges([.create(created), .delete(expected: original)])
        #expect(await store.snapshot() == [created])
    }

    @Test
    func twoLibraryEditorsKeepTheirDraftOnConflictAndCanSaveANewCopy() async throws {
        let original = Self.item(title: "Shared note")
        let copiedID = UUID()
        let store = InMemoryProductivityLibraryStore(items: [original])
        let first = Self.model(store: store)
        let second = Self.model(store: store, makeID: { copiedID })
        await first.load()
        await second.load()
        first.beginEditingSelected()
        second.beginEditingSelected()
        first.draft.content = "Saved by first editor"
        first.saveDraft()
        await first.flushPersistenceForTesting()
        second.draft.content = "Keep the second draft"
        // Reloading list metadata must not replace the edit session's expected version.
        await second.load(force: true)
        second.saveDraft()
        await second.flushPersistenceForTesting()
        #expect(second.hasPersistenceConflict)
        #expect(second.draft.content == "Keep the second draft")
        #expect(second.editorMode == .editing(original.id))
        #expect(await store.snapshot().first?.content == "Saved by first editor")

        second.saveDraftAsNew()
        await second.flushPersistenceForTesting()
        let saved = await store.snapshot()
        #expect(saved.count == 2)
        #expect(saved.first(where: { $0.id == original.id })?.content == "Saved by first editor")
        #expect(saved.first(where: { $0.id == copiedID })?.content == "Keep the second draft")
        #expect(saved.first(where: { $0.id == copiedID })?.tags == original.tags)
        #expect(second.editorMode == nil && !second.hasPersistenceConflict)
    }

    @Test
    func deleteConfirmationCannotDeleteANewerVersionSavedInAnotherWindow() async throws {
        let original = Self.item(title: "Review before deleting")
        let store = InMemoryProductivityLibraryStore(items: [original])
        let model = Self.model(store: store)
        await model.load()
        model.requestDeleteSelected()
        var updated = original
        updated.content = "A newer note to keep"
        _ = try await store.applyChanges([.replace(updated, expected: original)])
        model.confirmDelete()
        await model.flushPersistenceForTesting()
        #expect(model.hasPersistenceConflict)
        #expect(await store.snapshot() == [updated])
    }

    private static func item(title: String) -> ProductivityLibraryItem {
        ProductivityLibraryItem(id: UUID(), kind: .quickNote, title: title, content: "Initial text",
                                createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1),
                                tags: ["Work"])
    }

    private static func model(
        store: any ProductivityLibraryPersisting, makeID: @escaping () -> UUID = { UUID() }
    ) -> ProductivityLibraryViewModel {
        ProductivityLibraryViewModel(
            services: ProductivityLibraryApplicationServices(
                persistence: store, pasteboard: InMemoryPasteboard(), urlOpener: NoOpURLOpener(), makeID: makeID
            ), onGoBack: {}, onDismiss: {}
        )
    }
}
