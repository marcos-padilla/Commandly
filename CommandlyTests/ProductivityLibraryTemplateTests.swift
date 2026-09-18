import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ProductivityLibraryTemplateTests {
    @Test func templateExpandsOneSnapshotWithoutReinterpretingPrivateInput() throws {
        let id = try #require(UUID(uuidString: "12345678-1234-1234-1234-123456789abc"))
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let template = try SnippetTemplate(
            "{{date}} {{time}} {{datetime}} {{uuid}} {{input:Name}} {{input:Name}} {{clipboard}} {{unknown}}"
        )
        #expect(template.fields == ["Name"])
        #expect(template.needsClipboard)
        let output = try template.expanded(
            clipboard: "{{date}} $(do not execute)",
            date: Date(timeIntervalSince1970: 0), uuid: id,
            inputs: ["Name": "{{clipboard}}"], timeZone: zone
        )
        #expect(output == "1970-01-01 00:00 1970-01-01 00:00 12345678-1234-1234-1234-123456789abc {{clipboard}} {{clipboard}} {{date}} $(do not execute) {{unknown}}")
    }

    @Test func templatesPreserveCodeAndRejectUnboundedExpansionOrMissingFields() throws {
        let source = "{{input:}} {{unknown}} {{unterminated"
        let template = try SnippetTemplate(source)
        #expect(template.fields.isEmpty)
        #expect(!template.needsClipboard)
        #expect(try template.expanded(clipboard: "", date: Date(), uuid: UUID()) == source)
        let input = try SnippetTemplate("{{input:Title}}")
        #expect(throws: SnippetTemplate.Failure.missingInput) {
            try input.expanded(clipboard: "", date: Date(), uuid: UUID())
        }
        #expect(throws: SnippetTemplate.Failure.tooManyFields) {
            try SnippetTemplate((0..<17).map { "{{input:Field\($0)}}" }.joined())
        }
        let repeated = try SnippetTemplate("{{clipboard}}{{clipboard}}")
        #expect(throws: SnippetTemplate.Failure.tooLarge) {
            try repeated.expanded(
                clipboard: String(repeating: "é", count: 300_000), date: Date(), uuid: UUID()
            )
        }
    }

    @Test @MainActor func legacyLibraryMigratesWithoutLosingContentAndRoundTripsTags() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let legacy = """
        {"version":1,"items":[{"id":"12345678-1234-1234-1234-123456789ABC",
        "kind":"snippet","title":"Legacy","content":"Keep {{clipboard}}", "createdAt":0,"updatedAt":1}]}
        """
        try Data(legacy.utf8).write(to: url)
        let store = JSONProductivityLibraryStore(fileURL: url)
        var items = try await store.loadItems()
        #expect(items.count == 1)
        #expect(items.first?.tags.isEmpty == true)
        items[0].tags = ["Work", "Writing"]
        try await store.saveItems(items)
        #expect(try await store.loadItems() == items)
        #expect(items[0].content == "Keep {{clipboard}}")
        let future = "{\"version\":99,\"items\":[]}"
        try Data(future.utf8).write(to: url)
        await #expect(throws: ProductivityLibraryPersistenceError.unsupportedVersion) {
            try await store.loadItems()
        }
    }

    @Test @MainActor func tagsSaveSearchFilterAndEditAcrossLibraryKinds() async throws {
        let store = InMemoryProductivityLibraryStore()
        let model = makeModel(store: store)
        await model.load()
        model.beginCreating(kind: .snippet)
        model.draft.title = "Greeting"
        model.draft.content = "Hello"
        model.draft.tags = " Work, work, Writing, , PERSONAL "
        model.saveDraft()
        await model.flushPersistenceForTesting()
        #expect(model.selectedItem?.tags == ["Work", "Writing", "PERSONAL"])
        model.query = "writing"
        #expect(model.filteredItems.count == 1)
        model.selectedTag = "missing"
        #expect(model.filteredItems.isEmpty)
        model.selectedTag = "WORK"
        #expect(model.filteredItems.count == 1)
        model.beginEditingSelected()
        #expect(model.draft.tags == "Work, Writing, PERSONAL")
        model.draft.tags = "Updated"
        model.saveDraft()
        await model.flushPersistenceForTesting()
        #expect(model.selectedTag == nil)
        #expect(model.availableTags == ["Updated"])
        #expect(await store.snapshot().first?.tags == ["Updated"])
    }

    @Test @MainActor func namedInputsWaitForConfirmationAndClearOnCopyCancelAndStop() async throws {
        let item = ProductivityLibraryItem(
            id: UUID(), kind: .snippet, title: "Reply", content: "Hello {{input:Name}}: {{clipboard}}",
            createdAt: Date(), updatedAt: Date()
        )
        let pasteboard = InMemoryPasteboard(initial: "original")
        let model = makeModel(store: InMemoryProductivityLibraryStore(items: [item]), pasteboard: pasteboard)
        await model.load()
        model.perform(ProductivityLibraryActionID.useSelected)
        #expect(model.pendingSnippet?.id == item.id)
        #expect(model.snippetFields == ["Name"])
        #expect(!model.canCopyPreparedSnippet)
        model.copyPreparedSnippet()
        #expect(pasteboard.currentValue == "original")
        model.snippetInputs["Name"] = "Alex"
        #expect(model.canCopyPreparedSnippet)
        model.copyPreparedSnippet()
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "Hello Alex: original")
        #expect(model.pendingSnippet == nil)
        #expect(model.snippetInputs.isEmpty)

        model.perform(ProductivityLibraryActionID.useSelected)
        model.snippetInputs["Name"] = "Temporary"
        #expect(model.handleEscape())
        #expect(model.pendingSnippet == nil)
        #expect(model.snippetInputs.isEmpty)
        model.perform(ProductivityLibraryActionID.useSelected)
        model.snippetInputs["Name"] = "Temporary"
        model.stop()
        #expect(model.pendingSnippet == nil)
        #expect(model.snippetInputs.isEmpty)
        #expect(pasteboard.currentValue == "Hello Alex: original")
    }

    @Test func tagBoundsAreAppliedPerItemWithoutSplittingUnicodeCharacters() {
        let longTag = String(repeating: "👨‍👩‍👧‍👦", count: 40)
        let tags = ProductivityLibraryTags.normalized([longTag] + (1...20).map { "tag\($0)" })
        #expect(tags.count == 12)
        #expect(tags.first?.count == 32)
        #expect(ProductivityLibraryTags.parse("a, A, b\nc") == ["a", "b", "c"])
    }

    @Test @MainActor func oversizedExpansionKeepsNamedInputsForCorrection() async throws {
        let item = ProductivityLibraryItem(
            id: UUID(), kind: .snippet, title: "Reply", content: "{{input:Message}}{{input:Message}}",
            createdAt: Date(), updatedAt: Date()
        )
        let pasteboard = InMemoryPasteboard(initial: "Unchanged")
        let model = makeModel(store: InMemoryProductivityLibraryStore(items: [item]), pasteboard: pasteboard)
        await model.load()
        model.perform(ProductivityLibraryActionID.useSelected)
        let oversized = String(repeating: "é", count: 300_000)
        model.snippetInputs["Message"] = oversized
        model.copyPreparedSnippet()
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "Unchanged")
        #expect(model.pendingSnippet?.id == item.id)
        #expect(model.snippetInputs["Message"] == oversized)
        #expect(model.statusMessage == SnippetTemplate.Failure.tooLarge.message)

        model.snippetInputs["Message"] = "Hello"
        model.copyPreparedSnippet()
        await model.flushPrimaryActionForTesting()
        #expect(pasteboard.currentValue == "HelloHello")
        #expect(model.pendingSnippet == nil)
        #expect(model.snippetInputs.isEmpty)
    }

    @Test @MainActor func quicklinkTagsRoundTripAndAggregateFilterIncludesEveryItemTag() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let snippets = (0..<15).map { index in
            ProductivityLibraryItem(
                id: UUID(), kind: .snippet, title: "Snippet \(index)", content: "Text",
                createdAt: date, updatedAt: date, tags: ["Tag \(index)"]
            )
        }
        let store = InMemoryProductivityLibraryStore(items: snippets)
        let model = makeModel(store: store)
        await model.load()
        model.beginCreating(kind: .quicklink)
        model.draft.title = "Project"
        model.draft.content = "https://example.com/project"
        model.draft.tags = "Project, Work, project"
        model.saveDraft()
        await model.flushPersistenceForTesting()
        #expect(model.selectedItem?.kind == .quicklink)
        #expect(model.selectedItem?.tags == ["Project", "Work"])
        #expect(model.availableTags.count == 17)
        model.selectedTag = "project"
        #expect(model.filteredItems.map(\.title) == ["Project"])
        let reopened = makeModel(store: store)
        await reopened.load()
        reopened.query = "work"
        #expect(reopened.filteredItems.map(\.title) == ["Project"])
        #expect(reopened.filteredItems.first?.content == "https://example.com/project")
    }

    @MainActor private func makeModel(
        store: any ProductivityLibraryPersisting,
        pasteboard: any PasteboardAccessing = InMemoryPasteboard()
    ) -> ProductivityLibraryViewModel {
        ProductivityLibraryViewModel(
            services: ProductivityLibraryApplicationServices(
                persistence: store, pasteboard: pasteboard, urlOpener: NoOpURLOpener()
            ), onGoBack: {}, onDismiss: {}
        )
    }
}
