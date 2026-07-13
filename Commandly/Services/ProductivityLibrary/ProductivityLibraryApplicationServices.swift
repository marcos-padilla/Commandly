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

    init(
        persistence: any ProductivityLibraryPersisting,
        pasteboard: any PasteboardAccessing,
        urlOpener: any URLOpening,
        quicklinkValidator: ProductivityQuicklinkValidator = ProductivityQuicklinkValidator(),
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.persistence = persistence
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
        self.quicklinkValidator = quicklinkValidator
        self.now = now
        self.makeID = makeID
    }

    static var live: ProductivityLibraryApplicationServices {
        ProductivityLibraryApplicationServices(
            persistence: JSONProductivityLibraryStore(),
            pasteboard: SystemPasteboard(),
            urlOpener: WorkspaceURLOpener()
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
