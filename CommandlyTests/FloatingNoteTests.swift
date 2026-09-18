import Foundation
import Testing
@testable import Commandly

@Suite("Floating note editing", .timeLimit(.minutes(1)))
@MainActor
struct FloatingNoteTests {
    @Test
    func explicitSaveNamesAnUntitledNoteAndClosingDoesNotDeleteIt() async throws {
        let store = InMemoryProductivityLibraryStore()
        let callbacks = FloatingNoteCallbacks()
        let identifier = UUID()
        let model = FloatingNoteModel(
            noteID: identifier, persistence: store, onSaved: { callbacks.saved += 1 },
            onCloseApproved: { callbacks.closed += 1 }
        )
        #expect(await store.saveCount == 0)
        #expect(!model.hasUnsavedChanges && model.isPinned)
        model.content = "A small idea\nKeep the original lines.\n"
        model.saveAndClose()
        await model.flushSaveForTesting()
        let saved = try #require(await store.snapshot().first)
        #expect(saved.id == identifier && saved.title == "A small idea")
        #expect(saved.content == "A small idea\nKeep the original lines.\n")
        #expect(saved.kind == .quickNote)
        #expect(callbacks.saved == 1 && callbacks.closed == 1)
        let reopened = FloatingNoteModel(noteID: saved.id, item: saved, persistence: store)
        #expect(!reopened.hasUnsavedChanges && reopened.statusText == "Saved in Quick Notes")
    }

    @Test
    func closeConfirmationCanKeepEditingOrDiscardWithoutTouchingSavedText() async throws {
        let item = FloatingNoteFixtures.item("Saved")
        let store = InMemoryProductivityLibraryStore(items: [item])
        let callbacks = FloatingNoteCallbacks()
        let model = FloatingNoteModel(
            noteID: item.id, item: item, persistence: store,
            onCloseApproved: { callbacks.closed += 1 }, onCloseCancelled: { callbacks.cancelled += 1 }
        )
        model.content = "An unsaved revision"
        model.requestClose()
        #expect(model.showsCloseConfirmation && callbacks.closed == 0)
        model.keepEditing()
        #expect(!model.showsCloseConfirmation && callbacks.cancelled == 1)
        #expect(model.content == "An unsaved revision")
        model.requestClose()
        model.discardAndClose()
        #expect(callbacks.closed == 1)
        #expect(await store.snapshot() == [item])
        #expect(await store.saveCount == 0)
    }

    @Test
    func failedSaveAndCloseRetainsDraftAndCancelsPendingQuit() async {
        let store = FloatingNoteStoreDouble(fails: true)
        let callbacks = FloatingNoteCallbacks()
        let model = FloatingNoteModel(
            noteID: UUID(), persistence: store, onCloseApproved: { callbacks.closed += 1 },
            onCloseCancelled: { callbacks.cancelled += 1 }
        )
        model.content = "Keep this draft after an I/O failure"
        model.saveAndClose()
        await model.flushSaveForTesting()
        #expect(callbacks.closed == 0 && callbacks.cancelled == 1)
        #expect(model.content == "Keep this draft after an I/O failure" && model.hasUnsavedChanges)
        #expect(model.errorMessage != nil && !model.isSaving)
        await store.setFails(false)
        model.saveAndClose()
        await model.flushSaveForTesting()
        #expect(callbacks.closed == 1)
        #expect(await store.snapshot().count == 1)
    }

    @Test
    func editsDuringASuspendedSaveRemainDirtyAndCannotBeClosedAsAlreadySaved() async throws {
        let store = FloatingNoteStoreDouble(blocksSave: true)
        let callbacks = FloatingNoteCallbacks()
        let model = FloatingNoteModel(noteID: UUID(), persistence: store, onCloseApproved: { callbacks.closed += 1 })
        model.title = "Draft"
        model.content = "First version"
        model.saveAndClose()
        await store.waitUntilSaveStarts()
        model.content = "A later edit"
        model.requestClose()
        #expect(callbacks.closed == 0 && model.isSaving)
        await store.releaseSave()
        await model.flushSaveForTesting()
        #expect(await store.snapshot().first?.content == "First version")
        #expect(model.content == "A later edit" && model.hasUnsavedChanges)
        #expect(model.showsCloseConfirmation && callbacks.closed == 0)
    }

    @Test
    func conflictingSavedVersionPreservesDraftAndSaveAsCopyKeepsBothVersions() async throws {
        let original = FloatingNoteFixtures.item("Original")
        let store = InMemoryProductivityLibraryStore(items: [original])
        let copyID = UUID()
        let model = FloatingNoteModel(noteID: original.id, item: original, persistence: store, makeID: { copyID })
        var external = original
        external.content = "Edited elsewhere"
        _ = try await store.applyChanges([.replace(external, expected: original)])
        model.content = "My floating draft"
        model.save()
        await model.flushSaveForTesting()
        #expect(model.hasConflict && model.hasUnsavedChanges)
        #expect(model.content == "My floating draft")
        #expect(await store.snapshot() == [external])
        model.saveAsCopy()
        await model.flushSaveForTesting()
        let saved = await store.snapshot()
        #expect(saved.count == 2)
        #expect(saved.first(where: { $0.id == original.id }) == external)
        #expect(saved.first(where: { $0.id == copyID })?.content == "My floating draft")
        #expect(saved.first(where: { $0.id == copyID })?.tags == original.tags)
        #expect(model.noteID == copyID && !model.hasConflict && !model.hasUnsavedChanges)
    }

    @Test
    func blankAndOversizedNotesDoNotWriteAndTheirDraftStaysEditable() async {
        let store = InMemoryProductivityLibraryStore()
        let model = FloatingNoteModel(noteID: UUID(), persistence: store)
        model.save()
        #expect(model.errorMessage != nil && !model.isSaving)
        model.content = String(repeating: "x", count: FloatingNoteModel.maximumBodyBytes + 1)
        model.save()
        #expect(model.errorMessage != nil && model.hasUnsavedChanges)
        #expect(await store.saveCount == 0)
        model.content = "Within the bound"
        model.save()
        await model.flushSaveForTesting()
        #expect(await store.saveCount == 1 && model.errorMessage == nil)
    }
}

@Suite("Floating note windows", .timeLimit(.minutes(1)))
@MainActor
struct FloatingNoteCoordinatorTests {
    @Test
    func openingTheSameNoteFocusesItsExistingDraftAndOtherNotesHaveIndependentWindows() async throws {
        let first = FloatingNoteFixtures.item("First")
        let second = FloatingNoteFixtures.item("Second")
        let store = InMemoryProductivityLibraryStore(items: [first, second])
        let factory = FloatingNoteWindowFactory()
        let coordinator = FloatingNoteCoordinator(persistence: store, makeWindow: { factory.make() })
        #expect(factory.windows.isEmpty && coordinator.openWindowCount == 0)
        coordinator.openNote(first)
        let firstModel = try #require(coordinator.modelForTesting(noteID: first.id))
        firstModel.content = "Unsaved first-window text"
        coordinator.openNote(first)
        coordinator.openNote(second)
        let secondModel = try #require(coordinator.modelForTesting(noteID: second.id))
        #expect(factory.windows.count == 2 && coordinator.openWindowCount == 2)
        #expect(factory.windows[0].focusCount == 1)
        #expect(firstModel.content == "Unsaved first-window text")
        #expect(secondModel.content == second.content)
        secondModel.content = "Saved in second window"
        firstModel.save()
        secondModel.saveAndClose()
        await firstModel.flushSaveForTesting()
        await secondModel.flushSaveForTesting()
        #expect(coordinator.openWindowCount == 1 && coordinator.savedRevision == 2)
        let saved = await store.snapshot()
        #expect(saved.first(where: { $0.id == first.id })?.content == "Unsaved first-window text")
        #expect(saved.first(where: { $0.id == second.id })?.content == "Saved in second window")
        #expect(factory.windows[0].focusCount == 1) // Saves never reorder an unrelated window.
        firstModel.requestClose()
        #expect(coordinator.openWindowCount == 0)
        #expect(await store.snapshot().count == 2)
    }

    @Test
    func newNoteIsLazyAndAnEmptyCloseDoesNotCreateALibraryItem() async {
        let store = InMemoryProductivityLibraryStore()
        let factory = FloatingNoteWindowFactory()
        let coordinator = FloatingNoteCoordinator(persistence: store, makeWindow: { factory.make() })
        coordinator.newNote()
        #expect(coordinator.openWindowCount == 1)
        #expect(coordinator.hasUnsavedNotes == false)
        factory.windows.first?.model?.requestClose()
        #expect(coordinator.openWindowCount == 0)
        #expect(await store.snapshot().isEmpty)
    }

    @Test(arguments: [false, true])
    func openingAnotherNoteCancelsTheQuitPromptOrDeferredCloseButKeepsItsSave(blockedSave: Bool) async throws {
        let store = FloatingNoteStoreDouble(blocksSave: blockedSave)
        let factory = FloatingNoteWindowFactory()
        let coordinator = FloatingNoteCoordinator(persistence: store, makeWindow: { factory.make() })
        let callbacks = FloatingNoteCallbacks()
        coordinator.newNote()
        let first = try #require(factory.windows.first?.model)
        first.content = "Keep this window when quitting is cancelled"
        if blockedSave {
            first.save()
            await store.waitUntilSaveStarts()
        }
        coordinator.requestCloseAll { callbacks.closeResults.append($0) }
        if !blockedSave { #expect(first.showsCloseConfirmation) }
        coordinator.newNote()
        #expect(callbacks.closeResults == [false])
        #expect(!first.showsCloseConfirmation && coordinator.openWindowCount == 2)
        if blockedSave {
            await store.releaseSave()
            await first.flushSaveForTesting()
            #expect(await store.snapshot().count == 1)
        }
        #expect(coordinator.openWindowCount == 2)
        #expect(factory.windows.first?.model === first)
    }

    @Test
    func cancellingQuitDoesNotCancelAnEarlierExplicitSaveAndClose() async throws {
        let store = FloatingNoteStoreDouble(blocksSave: true)
        let factory = FloatingNoteWindowFactory()
        let coordinator = FloatingNoteCoordinator(persistence: store, makeWindow: { factory.make() })
        let callbacks = FloatingNoteCallbacks()
        coordinator.newNote()
        let first = try #require(factory.windows.first?.model)
        first.content = "An explicitly closing note"
        first.saveAndClose()
        await store.waitUntilSaveStarts()
        coordinator.requestCloseAll { callbacks.closeResults.append($0) }
        coordinator.newNote()
        await store.releaseSave()
        await first.flushSaveForTesting()
        #expect(callbacks.closeResults == [false])
        #expect(coordinator.openWindowCount == 1 && factory.windows.first?.model == nil)
        #expect(await store.snapshot().count == 1)
    }

    @Test
    func quitCanBeCancelledThenRetriedWithoutDiscardingAnyDraft() async throws {
        let store = InMemoryProductivityLibraryStore()
        let factory = FloatingNoteWindowFactory()
        let coordinator = FloatingNoteCoordinator(persistence: store, makeWindow: { factory.make() })
        let callbacks = FloatingNoteCallbacks()
        coordinator.newNote()
        coordinator.newNote()
        for window in factory.windows { window.model?.content = "Independent window draft" }
        #expect(coordinator.hasUnsavedNotes)
        coordinator.requestCloseAll { callbacks.closeResults.append($0) }
        let firstPromptCandidate = factory.windows.compactMap(\.model).first { $0.showsCloseConfirmation }
        let firstPrompt = try #require(firstPromptCandidate)
        firstPrompt.keepEditing()
        #expect(callbacks.closeResults == [false] && coordinator.openWindowCount == 2)
        #expect(await store.snapshot().isEmpty)

        coordinator.requestCloseAll { callbacks.closeResults.append($0) }
        let retryPromptCandidate = factory.windows.compactMap(\.model).first { $0.showsCloseConfirmation }
        let retryPrompt = try #require(retryPromptCandidate)
        retryPrompt.saveAndClose()
        await retryPrompt.flushSaveForTesting()
        let lastPromptCandidate = factory.windows.compactMap(\.model).first { $0.showsCloseConfirmation }
        let lastPrompt = try #require(lastPromptCandidate)
        lastPrompt.saveAndClose()
        await lastPrompt.flushSaveForTesting()
        #expect(callbacks.closeResults == [false, true])
        #expect(coordinator.openWindowCount == 0)
        #expect(await store.snapshot().count == 2)
    }
}

@MainActor
private final class FloatingNoteCallbacks {
    var saved = 0
    var closed = 0
    var cancelled = 0
    var closeResults: [Bool] = []
}

@MainActor
private final class FloatingNoteWindowFactory {
    private(set) var windows: [FloatingNoteWindowDouble] = []
    func make() -> FloatingNoteWindowDouble {
        let window = FloatingNoteWindowDouble()
        windows.append(window)
        return window
    }
}

@MainActor
private final class FloatingNoteWindowDouble: FloatingNoteWindowPresenting {
    private(set) var model: FloatingNoteModel?
    private(set) var focusCount = 0
    private var onClosed: (() -> Void)?
    func present(model: FloatingNoteModel, placementIndex: Int, onClosed: @escaping () -> Void) {
        self.model = model
        self.onClosed = onClosed
    }
    func focus() { focusCount += 1 }
    func close() {
        let callback = onClosed
        onClosed = nil
        model = nil
        callback?()
    }
}

nonisolated private enum FloatingNoteFixtures {
    static func item(_ title: String) -> ProductivityLibraryItem {
        ProductivityLibraryItem(id: UUID(), kind: .quickNote, title: title, content: "Saved note text",
                                createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 10),
                                tags: ["Ideas"])
    }
}

private actor FloatingNoteStoreDouble: ProductivityLibraryPersisting {
    private var items: [ProductivityLibraryItem] = []
    private var fails: Bool
    private let blocksSave: Bool
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var saveGate: CheckedContinuation<Void, Never>?

    init(fails: Bool = false, blocksSave: Bool = false) { self.fails = fails; self.blocksSave = blocksSave }
    func loadItems() async throws -> [ProductivityLibraryItem] { items }
    func saveItems(_ items: [ProductivityLibraryItem]) async throws { self.items = items }
    func applyChanges(_ changes: [ProductivityLibraryMutation]) async throws -> [ProductivityLibraryItem] {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        if blocksSave { await withCheckedContinuation { saveGate = $0 } }
        try Task.checkCancellation()
        if fails { throw ProductivityLibraryPersistenceError.writeFailed }
        let updated = try ProductivityLibraryMutation.applying(changes, to: items)
        items = updated
        return updated
    }
    func setFails(_ value: Bool) { fails = value }
    func snapshot() -> [ProductivityLibraryItem] { items }
    func waitUntilSaveStarts() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func releaseSave() { saveGate?.resume(); saveGate = nil }
}
