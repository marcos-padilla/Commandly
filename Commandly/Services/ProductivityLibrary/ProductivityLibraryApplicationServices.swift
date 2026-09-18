import Foundation
import Infrastructure

/// Focused dependency bundle injected into the Productivity Library application.
@MainActor
struct ProductivityLibraryApplicationServices {
    let persistence: any ProductivityLibraryPersisting
    let pasteboard: any PasteboardAccessing
    let urlOpener: any URLOpening
    let quicklinkValidator: ProductivityQuicklinkValidator
    let now: () -> Date
    let makeID: () -> UUID
    let floatingNotes: (any FloatingNotePresenting)?

    init(
        persistence: any ProductivityLibraryPersisting,
        pasteboard: any PasteboardAccessing,
        urlOpener: any URLOpening,
        quicklinkValidator: ProductivityQuicklinkValidator = ProductivityQuicklinkValidator(),
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> UUID = { UUID() },
        floatingNotes: (any FloatingNotePresenting)? = nil
    ) {
        self.persistence = persistence
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
        self.quicklinkValidator = quicklinkValidator
        self.now = now
        self.makeID = makeID
        self.floatingNotes = floatingNotes
    }

    func withFloatingNotes(_ presenter: any FloatingNotePresenting) -> Self {
        Self(persistence: persistence, pasteboard: pasteboard, urlOpener: urlOpener,
             quicklinkValidator: quicklinkValidator, now: now, makeID: makeID,
             floatingNotes: presenter)
    }

    static var live: ProductivityLibraryApplicationServices {
        let persistence = JSONProductivityLibraryStore()
        return ProductivityLibraryApplicationServices(
            persistence: persistence,
            pasteboard: SystemPasteboard(),
            urlOpener: WorkspaceURLOpener(),
            floatingNotes: FloatingNoteCoordinator(persistence: persistence)
        )
    }

    static var inMemory: ProductivityLibraryApplicationServices {
        ProductivityLibraryApplicationServices(
            persistence: InMemoryProductivityLibraryStore(),
            pasteboard: InMemoryPasteboard(),
            urlOpener: NoOpURLOpener()
        )
    }
}
