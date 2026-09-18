import Foundation
import Infrastructure

@MainActor
struct CleanShotAnnotationService: ScreenshotAnnotating {
    let opener: any CleanShotApplicationOpening
    let files: CleanShotTemporaryStore

    init(opener: any CleanShotApplicationOpening = WorkspaceCleanShotOpener(), files: CleanShotTemporaryStore = CleanShotTemporaryStore()) {
        self.opener = opener
        self.files = files
    }

    func openInCleanShot(_ image: ScreenshotImage) async throws {
        try Task.checkCancellation()
        let destination: CleanShotDestination
        do { destination = try await opener.destination() }
        catch is CancellationError { throw CancellationError() }
        catch let error as ScreenshotAnnotationError { throw error }
        catch { throw ScreenshotAnnotationError.applicationUnavailable }
        try Task.checkCancellation()
        let lease = try await files.stage(image)
        do {
            try Task.checkCancellation()
            try await opener.open(CleanShotAnnotationURL.make(fileURL: lease.fileURL), in: destination)
            // No cancellation check after dispatch: CleanShot can still be reading this file
            // after activation causes Commandly's view to stop. The independent deadline owns it.
        } catch {
            try await files.remove(lease)
            if error is CancellationError { throw CancellationError() }
            throw ScreenshotAnnotationError.openFailed
        }
    }
}

@MainActor
struct UnavailableScreenshotAnnotator: ScreenshotAnnotating {
    func openInCleanShot(_ image: ScreenshotImage) async throws { throw ScreenshotAnnotationError.applicationUnavailable }
}
