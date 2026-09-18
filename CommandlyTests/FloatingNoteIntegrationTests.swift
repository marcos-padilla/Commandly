import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Floating note launcher integration")
@MainActor
struct FloatingNoteIntegrationTests {
    @Test
    func dedicatedToolDismissesLauncherBeforePresentingIndependentEditor() async throws {
        let presenter = LibraryNotePresenter()
        let store = InMemoryProductivityLibraryStore()
        let app = ProductivityLibraryApplication(services: services(store, presenter))
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: { presenter.events.append("dismiss") }, openSettings: {}, goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:])
        )
        _ = app.launch(toolID: ProductivityLibraryApplicationID.newFloatingNoteTool,
                       arguments: CommandArguments(), in: context)

        #expect(presenter.events == ["dismiss", "new"])
        #expect(await store.snapshot().isEmpty)
    }

    @Test
    func openingSavedNotePassesItsExactIdentityAndLeavesPersistenceUntouched() async throws {
        let item = note()
        let store = InMemoryProductivityLibraryStore(items: [item])
        let presenter = LibraryNotePresenter()
        let model = ProductivityLibraryViewModel(services: services(store, presenter), onGoBack: {},
            onDismiss: { presenter.events.append("dismiss") })
        await model.load()
        #expect(model.menuActions.contains { $0.id == ProductivityLibraryActionID.openFloatingNote })
        model.perform(ProductivityLibraryActionID.openFloatingNote)

        #expect(presenter.events == ["dismiss", "open"])
        #expect(presenter.opened == item)
        #expect(await store.snapshot() == [item])
    }

    @Test
    func floatingSaveRefreshWaitsForAnActiveLibraryDraftToClose() async throws {
        let item = note()
        let store = InMemoryProductivityLibraryStore(items: [item])
        let presenter = LibraryNotePresenter()
        let model = ProductivityLibraryViewModel(services: services(store, presenter), onGoBack: {}, onDismiss: {})
        await model.load()
        model.beginEditingSelected()
        model.draft.content = "Unsaved local draft"
        let originalLoad = model.loadRequestID
        var newer = item
        newer.content = "Saved from the floating editor"
        _ = try await store.applyChanges([.replace(newer, expected: item)])
        presenter.savedRevision += 1
        model.refreshForFloatingNoteChanges()
        #expect(model.loadRequestID == originalLoad)
        #expect(model.draft.content == "Unsaved local draft")

        model.cancelEditor()
        model.refreshForFloatingNoteChanges()
        #expect(model.loadRequestID == originalLoad + 1)
        await model.load()
        #expect(model.selectedItem?.content == newer.content)
        model.refreshForFloatingNoteChanges()
        #expect(model.loadRequestID == originalLoad + 1)
    }

    private func services(_ store: InMemoryProductivityLibraryStore, _ presenter: LibraryNotePresenter)
        -> ProductivityLibraryApplicationServices {
        .init(persistence: store, pasteboard: InMemoryPasteboard(), urlOpener: NoOpURLOpener(), floatingNotes: presenter)
    }

    private func note() -> ProductivityLibraryItem {
        .init(id: UUID(), kind: .quickNote, title: "Test Note", content: "Original",
              createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), tags: ["test"])
    }
}

@MainActor
private final class LibraryNotePresenter: FloatingNotePresenting {
    var savedRevision = 0
    var events: [String] = []
    var opened: ProductivityLibraryItem?
    func newNote() { events.append("new") }
    func openNote(_ item: ProductivityLibraryItem) { events.append("open"); opened = item }
}
