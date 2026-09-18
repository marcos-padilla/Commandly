import AppKit
import Foundation
import Testing
@testable import Commandly

struct ClipboardOrganizationTests {
    @Test @MainActor func organizingPreservesPayloadAndDoesNotRewritePasteboard() throws {
        let pasteboard = namedPasteboard()
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let id = try #require(store.createTextEntry("  exact payload\n"))
        let original = try #require(store.entry(id: id))
        let changeCount = pasteboard.changeCount

        try store.updateOrganization(id: id, name: "  Useful   Example  ", collection: "  Research  ")
        try store.setPinned(true, id: id)

        let updated = try #require(store.entry(id: id))
        #expect(updated.displayTitle == "Useful Example")
        #expect(updated.organization.collection == "Research")
        #expect(updated.organization.isPinned)
        #expect(updated.text == original.text)
        #expect(updated.preview == original.preview)
        #expect(updated.createdAt == original.createdAt)
        #expect(pasteboard.changeCount == changeCount)

        store.copyToPasteboard(updated)
        #expect(pasteboard.string(forType: .string) == "  exact payload\n")
        store.poll()
        #expect(store.entries.count == 1)
    }

    @Test @MainActor func metadataWorksForImagesAndIsSearchableWithoutChangingImageBytes() throws {
        let store = ClipboardHistoryStore(pasteboard: namedPasteboard())
        let image = entry(preview: "Image", type: .image, date: 1)
        store.replaceEntriesForTesting([image])

        try store.updateOrganization(id: image.id, name: "Café inspiration", collection: "Moodboard")

        #expect(store.entry(id: image.id)?.imageTIFFData == image.imageTIFFData)
        #expect(store.searchEntries(matching: "cafe", limit: 6).map(\.id) == [image.id])
        #expect(store.searchEntries(matching: "moodboard", limit: 6).map(\.id) == [image.id])
    }

    @Test @MainActor func pinnedEntriesSurviveBoundedCaptureAndOneSlotRemainsAvailable() throws {
        let store = ClipboardHistoryStore(maxEntries: 3, pasteboard: namedPasteboard())
        let newest = entry(preview: "Newest", date: 3)
        let middle = entry(preview: "Middle", date: 2)
        let oldest = entry(preview: "Oldest", date: 1)
        store.replaceEntriesForTesting([newest, middle, oldest])
        try store.setPinned(true, id: oldest.id)
        try store.setPinned(true, id: middle.id)

        #expect(throws: ClipboardOrganizationError.self) {
            try store.setPinned(true, id: newest.id)
        }
        let fresh = try #require(store.createTextEntry("Fresh capture"))
        #expect(store.entries.count == 3)
        #expect(store.entries.first?.id == fresh)
        #expect(store.entry(id: newest.id) == nil)
        #expect(store.entry(id: middle.id)?.organization.isPinned == true)
        #expect(store.entry(id: oldest.id)?.organization.isPinned == true)

        try store.setPinned(false, id: oldest.id)
        _ = store.createTextEntry("Next capture")
        #expect(store.entry(id: oldest.id) == nil)
        #expect(store.entries.count == 3)
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test @MainActor func textEditingPreservesOrganizationAndClearingMetadataRestoresPreview() throws {
        let store = ClipboardHistoryStore(pasteboard: namedPasteboard())
        let id = try #require(store.createTextEntry("Original"))
        try store.updateOrganization(id: id, name: "Shortcut", collection: "Work")
        try store.setPinned(true, id: id)
        #expect(store.updateTextEntry(id: id, text: "Replacement"))
        #expect(store.entry(id: id)?.organization == ClipboardEntryOrganization(
            name: "Shortcut", collection: "Work", isPinned: true
        ))
        try store.updateOrganization(id: id, name: " \n ", collection: "\t")
        #expect(store.entry(id: id)?.displayTitle == "Replacement")
        #expect(store.entry(id: id)?.organization.collection == nil)
        #expect(store.entry(id: id)?.organization.isPinned == true)
    }

    @Test @MainActor func metadataValidationIsAtomicAndCollectionsReuseExistingSpelling() throws {
        let store = ClipboardHistoryStore(pasteboard: namedPasteboard())
        let first = try #require(store.createTextEntry("First"))
        let second = try #require(store.createTextEntry("Second"))
        try store.updateOrganization(id: first, name: "First name", collection: "Café")
        try store.updateOrganization(id: second, name: "Second name", collection: "CAFE")
        #expect(store.entry(id: second)?.organization.collection == "Café")

        #expect(throws: ClipboardOrganizationError.self) {
            try store.updateOrganization(
                id: second, name: "Changed", collection: String(repeating: "x", count: 41)
            )
        }
        #expect(store.entry(id: second)?.organization.name == "Second name")
        #expect(throws: ClipboardOrganizationError.self) {
            try store.updateOrganization(
                id: second, name: String(repeating: "x", count: 121), collection: ""
            )
        }
        #expect(throws: ClipboardOrganizationError.self) {
            try store.updateOrganization(id: UUID(), name: "Missing", collection: "")
        }
    }

    @Test @MainActor func modelGroupsPinsFirstAndUsesTheSameOrderForKeyboardSelection() throws {
        let store = ClipboardHistoryStore(pasteboard: namedPasteboard())
        defer { store.stopMonitoring() }
        let recent = entry(preview: "Recent", date: 3)
        let middle = entry(preview: "Middle", date: 2)
        let oldest = entry(preview: "Old", date: 1)
        store.replaceEntriesForTesting([recent, middle, oldest])
        try store.updateOrganization(id: oldest.id, name: "Reference", collection: "Work")
        try store.updateOrganization(id: middle.id, name: "Draft", collection: "Work")
        try store.setPinned(true, id: oldest.id)
        let model = ClipboardHistoryViewModel(store: store, onGoBack: {}, onDismiss: {})

        #expect(model.selectedEntry?.id == oldest.id)
        #expect(model.sections.first?.title == "Pinned")
        #expect(model.sections.flatMap(\.entries).map(\.id) == model.filteredEntries.map(\.id))
        model.moveSelection(offset: 1)
        #expect(model.selectedEntry?.id == recent.id)
        model.selectedCollection = "Work"
        #expect(model.filteredEntries.map(\.id) == [oldest.id, middle.id])
        model.filter = .pinned
        #expect(model.filteredEntries.map(\.id) == [oldest.id])
        model.toggleSelectedPin()
        #expect(model.filteredEntries.isEmpty)
        model.filter = .all
        model.query = "Reference"
        #expect(model.filteredEntries.map(\.id) == [oldest.id])
        model.query = "Work"
        #expect(model.filteredEntries.count == 2)
    }

    @Test @MainActor func metadataEditorSavesWithoutCopyingAndEscapeDiscardsDraft() throws {
        let pasteboard = namedPasteboard()
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        defer { store.stopMonitoring() }
        let id = try #require(store.createTextEntry("Payload"))
        let model = ClipboardHistoryViewModel(store: store, onGoBack: {}, onDismiss: {})
        model.beginOrganizingSelected()
        #expect(model.editorMode == .organize(id))
        #expect(model.canSaveEditor)
        model.editorName = "Saved name"
        model.editorCollection = "Work"
        let changeCount = pasteboard.changeCount
        model.performPrimary()
        #expect(model.statusMessage == "Entry organization updated.")
        #expect(store.entry(id: id)?.displayTitle == "Saved name")
        #expect(pasteboard.changeCount == changeCount)

        model.beginOrganizingSelected()
        model.editorName = "Discarded"
        #expect(model.handleEscape())
        #expect(model.editorMode == nil)
        #expect(store.entry(id: id)?.displayTitle == "Saved name")
        model.beginOrganizingSelected()
        model.editorName = String(repeating: "x", count: 121)
        #expect(model.canSaveEditor == false)
        model.saveEditor()
        #expect(model.editorMode == .organize(id))
        #expect(store.entry(id: id)?.displayTitle == "Saved name")
    }

    @MainActor private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("CommandlyTests.clipboard.organization.\(UUID().uuidString)"))
    }

    private func entry(
        preview: String,
        type: ClipboardContentType = .text,
        date: TimeInterval
    ) -> ClipboardHistoryEntry {
        ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: date),
            contentType: type,
            preview: preview,
            text: type == .text ? preview : nil,
            imageTIFFData: type == .image ? Data([1, 2, 3]) : nil,
            fileURLs: [],
            sourceAppName: nil,
            sourceBundleIdentifier: nil
        )
    }
}
