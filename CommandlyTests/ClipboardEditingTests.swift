import AppKit
import CommandKit
import Foundation
import Testing
@testable import Commandly

struct ClipboardEditingTests {
    @Test @MainActor func createEditAndAppendTextEntriesUpdateNamedPasteboard() throws {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.clipboard.edit.\(UUID().uuidString)")
        )
        let ids = [UUID(), UUID(), UUID()]
        var nextID = 0
        let store = ClipboardHistoryStore(
            pasteboard: pasteboard,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) },
            uuidProvider: {
                defer { nextID += 1 }
                return ids[nextID]
            }
        )

        let created = try #require(store.createTextEntry("First value"))
        #expect(created == ids[0])
        #expect(store.entries.first?.text == "First value")
        #expect(pasteboard.string(forType: .string) == "First value")

        #expect(store.updateTextEntry(id: created, text: "Edited value"))
        #expect(store.entry(id: created)?.text == "Edited value")
        #expect(pasteboard.string(forType: .string) == "Edited value")

        let appended = try #require(store.appendTextToCurrentClipboard("Second line"))
        #expect(appended == ids[1])
        #expect(store.entries.first?.text == "Edited value\nSecond line")
        #expect(pasteboard.string(forType: .string) == "Edited value\nSecond line")

        store.poll()
        #expect(store.entries.count == 2)
    }

    @Test @MainActor func clipboardEditorSupportsCreateEditAppendAndEscape() throws {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.clipboard.editor.\(UUID().uuidString)")
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let viewModel = ClipboardHistoryViewModel(
            store: store,
            onGoBack: {},
            onDismiss: {}
        )

        viewModel.beginNewEntry()
        #expect(viewModel.editorMode == .newEntry)
        viewModel.editorText = "A reusable value"
        viewModel.saveEditor()
        let createdID = try #require(viewModel.selectedEntry?.id)
        #expect(viewModel.statusMessage == "Clipboard updated.")
        #expect(pasteboard.string(forType: .string) == "A reusable value")

        viewModel.beginEditingSelected()
        #expect(viewModel.editorMode == .edit(createdID))
        viewModel.editorText = "Updated"
        viewModel.saveEditor()
        #expect(store.entry(id: createdID)?.text == "Updated")

        viewModel.beginAppend()
        viewModel.editorText = "More"
        viewModel.saveEditor()
        #expect(pasteboard.string(forType: .string) == "Updated\nMore")

        viewModel.beginNewEntry()
        #expect(viewModel.handleEscape())
        #expect(viewModel.editorMode == nil)
    }

    @Test @MainActor func nonTextEntriesCannotEnterEditMode() {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.clipboard.noedit.\(UUID().uuidString)")
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        store.replaceEntriesForTesting([
            ClipboardHistoryEntry(
                id: UUID(),
                createdAt: Date(),
                contentType: .image,
                preview: "Image",
                text: nil,
                imageTIFFData: Data([0x00]),
                fileURLs: [],
                sourceAppName: nil,
                sourceBundleIdentifier: nil
            )
        ])
        let viewModel = ClipboardHistoryViewModel(
            store: store,
            onGoBack: {},
            onDismiss: {}
        )

        viewModel.beginEditingSelected()

        #expect(viewModel.editorMode == nil)
        #expect(
            viewModel.menuActions.first(where: {
                $0.id == ClipboardHistoryActionID.editEntry
            })?.isEnabled == false
        )
    }

    @Test @MainActor func textEditingPreservesIntentionalWhitespace() throws {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.clipboard.whitespace.\(UUID().uuidString)")
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard)

        let id = try #require(store.createTextEntry("  indented\n"))
        #expect(store.entry(id: id)?.text == "  indented\n")
        #expect(pasteboard.string(forType: .string) == "  indented\n")
        #expect(store.createTextEntry(" \n\t ") == nil)
    }
}
