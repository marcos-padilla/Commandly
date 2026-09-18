import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
@Suite("Screenshot reviewed annotation", .timeLimit(.minutes(1)))
struct ScreenshotAnnotationViewModelTests {
    @Test
    func annotationRequiresReviewedImageAndExplicitActionThenSendsExactArtifact() async throws {
        let image = try await CleanShotTestImageFactory().image()
        let annotator = ScreenshotAnnotatorFake()
        let model = makeModel(image, annotator: annotator)
        model.openInCleanShot()
        #expect(annotator.images.isEmpty)
        model.kind = .window; model.capture(); await model.waitForWorkForTesting()
        #expect(annotator.images.isEmpty && model.image == image)
        model.perform(ScreenshotActionID.annotate); await model.waitForWorkForTesting()
        #expect(annotator.images == [image] && model.image == image && model.isOpeningAnnotation == false)
        #expect(model.statusMessage?.contains("Finish editing there") == true)
    }

    @Test
    func missingAndOutdatedAppKeepReviewWithSpecificRecoveryAndNoAutomaticFallback() async throws {
        let image = try await CleanShotTestImageFactory().image()
        for (failure, message) in [(ScreenshotAnnotationError.applicationUnavailable, "Install and open"), (.applicationOutdated, "3.8.1"), (.unexpectedApplication, "verified CleanShot X")] {
            let annotator = ScreenshotAnnotatorFake(); annotator.failure = failure
            let model = makeModel(image, annotator: annotator)
            model.kind = .window; model.capture(); await model.waitForWorkForTesting()
            model.openInCleanShot(); await model.waitForWorkForTesting()
            #expect(model.image == image && model.isOpeningAnnotation == false && model.errorMessage?.contains(message) == true)
            #expect(model.showsFileExporter == false && annotator.images == [image])
        }
    }

    @Test
    func repeatedActionsDoNotDuplicateHandoffAndLateCompletionCannotRestoreDiscardedReview() async throws {
        let image = try await CleanShotTestImageFactory().image()
        let annotator = ScreenshotAnnotatorFake(); annotator.blocks = true
        let model = makeModel(image, annotator: annotator)
        model.kind = .window; model.capture(); await model.waitForWorkForTesting()
        model.openInCleanShot(); await annotator.waitUntilCalled()
        let task = model.pendingWorkForTesting()
        model.openInCleanShot(); model.copy(); model.perform(ScreenshotActionID.save)
        #expect(annotator.images == [image] && model.isReviewActionBusy && model.showsFileExporter == false)
        model.stop(); annotator.release(); await task?.value
        #expect(model.image == nil && model.isOpeningAnnotation == false && model.errorMessage == nil)
        #expect(model.statusMessage == "No screenshot retained.")
    }

    private func makeModel(_ image: ScreenshotImage, annotator: ScreenshotAnnotatorFake) -> ScreenshotViewModel {
        ScreenshotViewModel(services: ScreenshotApplicationServices(
            permissions: InMemoryPermissionService(), makeCapture: { ScreenshotAnnotationCaptureFake(image: image) },
            copier: ScreenshotAnnotationCopierFake(), privacySettings: InMemoryPrivacySettingsOpener(), annotator: annotator), onGoBack: {})
    }
}

@MainActor private final class ScreenshotAnnotatorFake: ScreenshotAnnotating {
    var failure: ScreenshotAnnotationError?
    var blocks = false
    private(set) var images: [ScreenshotImage] = []
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func openInCleanShot(_ image: ScreenshotImage) async throws {
        images.append(image); waiter?.resume(); waiter = nil
        if blocks { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }
    }
    func waitUntilCalled() async { if images.isEmpty == false { return }; await withCheckedContinuation { waiter = $0 } }
    func release() { pending?.resume(); pending = nil }
}
@MainActor private struct ScreenshotAnnotationCaptureFake: ScreenshotCapturing {
    let image: ScreenshotImage
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage { image }
    func cancel() {}
}
nonisolated private struct ScreenshotAnnotationCopierFake: ScreenshotCopying {
    func copyPNG(_ data: Data) async throws { Issue.record("Annotation must not copy the clipboard") }
}
