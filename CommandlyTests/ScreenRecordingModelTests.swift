import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Screen recording state and cancellation", .timeLimit(.minutes(1)))
@MainActor
struct ScreenRecordingModelTests {
    @Test
    func openingDoesNotCaptureAndRepeatedStartFreezesOneAudioConfiguration() async {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let model = ScreenRecordingModel(capture: capture, storage: store)
        #expect(model.options.audio == .none && capture.requests.isEmpty)
        #expect(await store.prepares == 0)
        model.options.audio = .systemAudio
        model.start(); model.start()
        await capture.waitForBegin()
        model.options.audio = .none
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        #expect(capture.requests.count == 1 && capture.requests[0].audio == .systemAudio)
        #expect(model.audioDescription == "System audio on · Microphone off")
        model.discard()
        await model.waitForCancellationForTesting()
        #expect(await store.discards.count == 1 && model.canStart)
    }

    @Test
    func stopWaitsForFinalVideoAndExportOccursOnlyOnExplicitSave() async {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let model = ScreenRecordingModel(capture: capture, storage: store)
        model.start()
        await capture.waitForBegin()
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        model.stop()
        await capture.waitForStop()
        #expect(model.phase == .stopping && model.artifact == nil)
        #expect(await store.finalizations == 0)
        #expect(await store.exports.isEmpty)
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        #expect(model.phase == .review && model.artifact != nil)
        #expect(await store.exports.isEmpty)
        model.export(to: URL(fileURLWithPath: "/generated-export.mp4"))
        await model.waitForExportForTesting()
        #expect(await store.exports.count == 1 && model.hasSavedCopy)
        model.discard()
        await model.waitForCancellationForTesting()
    }

    @Test
    func cancellationWaitsForNoncooperativePreparationAndNeverBeginsCapture() async {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble(blocksPrepare: true)
        let model = ScreenRecordingModel(capture: capture, storage: store)
        model.start()
        await store.waitForPrepare()
        model.discard()
        model.start()
        #expect(model.phase == .cancelling && !model.canStart)
        #expect(await store.discards.isEmpty)
        await store.releasePrepare()
        await model.waitForCancellationForTesting()
        #expect(capture.requests.isEmpty)
        #expect(await store.discards.count == 1)
        #expect(model.canStart && model.artifact == nil)
    }

    @Test
    func cancellationCannotDeleteOrRestartUntilNativeShutdownCompletes() async {
        let capture = RecordingCaptureDouble()
        capture.blocksCancellation = true
        let store = RecordingStoreDouble()
        let model = ScreenRecordingModel(capture: capture, storage: store)
        model.start()
        await capture.waitForBegin()
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        model.discard()
        await capture.waitForCancel()
        model.start()
        #expect(model.phase == .cancelling && capture.requests.count == 1)
        #expect(await store.discards.isEmpty)
        capture.send(.finished(RecordingTestFixture.summary))
        capture.releaseCancellation()
        await model.waitForCancellationForTesting()
        #expect(model.phase == .setup && model.artifact == nil)
        #expect(await store.finalizations == 0)
        #expect(await store.discards.count == 1)
    }

    @Test
    func exportFailureKeepsReviewAndSuccessfulSaveAllowsCloseWithoutSecondPrompt() async {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let model = ScreenRecordingModel(capture: capture, storage: store)
        let callbacks = RecordingCallbackDouble()
        model.onClose = { callbacks.closes += 1 }
        model.start(); await capture.waitForBegin()
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        let original = model.artifact
        await store.setExportFailure(true)
        model.export(to: URL(fileURLWithPath: "/generated.mp4"))
        await model.waitForExportForTesting()
        #expect(model.artifact == original && model.phase == .review && !model.hasSavedCopy)
        await store.setExportFailure(false)
        model.export(to: URL(fileURLWithPath: "/generated.mp4"))
        await model.waitForExportForTesting()
        model.requestClose()
        await model.waitForCancellationForTesting()
        #expect(callbacks.closes == 1 && !model.showsCloseConfirmation)
    }

    @Test
    func discardFailureBlocksNewCaptureAndRetryKeepsExactDraftOwnership() async {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let model = ScreenRecordingModel(capture: capture, storage: store)
        model.start(); await capture.waitForBegin()
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        let original = model.artifact?.draft
        await store.setDiscardFailure(true)
        model.discard()
        await model.waitForCancellationForTesting()
        #expect(model.phase == .discardFailed && !model.canStart && model.artifact?.draft == original)
        await store.setDiscardFailure(false)
        model.discard()
        await model.waitForCancellationForTesting()
        #expect(model.canStart)
        let discarded = await store.discards
        #expect(discarded == [original].compactMap { $0 })
    }

    @Test
    func coordinatorReusesWindowAndCancelledQuitStopsIntoReviewWithoutRestart() async throws {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let window = RecordingWindowDouble()
        let callbacks = RecordingCallbackDouble()
        let coordinator = ScreenRecordingCoordinator(capture: capture, storage: store, makeWindow: { window })
        coordinator.present(source: .display)
        let model = try #require(coordinator.model)
        coordinator.present(source: .window)
        #expect(coordinator.model === model && window.focusCalls == 1 && model.options.source == .window)
        model.start(); await capture.waitForBegin()
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        coordinator.requestCloseForTermination { callbacks.results.append($0) }
        await capture.waitForStop()
        #expect(callbacks.results.isEmpty && model.phase == .stopping)
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        #expect(model.showsCloseConfirmation)
        model.keepOpen()
        #expect(callbacks.results == [false] && model.phase == .review)
        #expect(capture.requests.count == 1 && window.closeCalls == 0)
        model.discard(close: true)
        await model.waitForCancellationForTesting()
        #expect(coordinator.model == nil && window.closeCalls == 1)
    }

    @Test
    func reopeningDuringQuitCancelsPendingCloseButDoesNotResumeCapture() async throws {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let window = RecordingWindowDouble()
        let callbacks = RecordingCallbackDouble()
        let coordinator = ScreenRecordingCoordinator(capture: capture, storage: store, makeWindow: { window })
        coordinator.present()
        let model = try #require(coordinator.model)
        model.start(); await capture.waitForBegin()
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        coordinator.requestCloseForTermination { callbacks.results.append($0) }
        await capture.waitForStop()
        coordinator.present(source: .display)
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        #expect(callbacks.results == [false] && model.phase == .review && !model.showsCloseConfirmation)
        #expect(capture.requests.count == 1)
        model.discard(close: true)
        await model.waitForCancellationForTesting()
    }
    @Test
    func approvedQuitRetainsSavedReviewUntilOtherDocumentsApprove() async throws {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let window = RecordingWindowDouble()
        let callbacks = RecordingCallbackDouble()
        let coordinator = ScreenRecordingCoordinator(capture: capture, storage: store, makeWindow: { window })
        coordinator.present()
        let model = try #require(coordinator.model)
        model.start(); await capture.waitForBegin()
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        let original = model.artifact
        coordinator.requestCloseForTermination { callbacks.results.append($0) }
        model.requestExport(closeAfterSaving: true)
        model.export(to: URL(fileURLWithPath: "/generated-saved.mp4"))
        await model.waitForExportForTesting()
        #expect(callbacks.results == [true] && window.closeCalls == 0)
        #expect(model.artifact == original && model.hasSavedCopy)
        coordinator.cancelPendingTermination()
        #expect(model.artifact == original && capture.requests.count == 1)
        #expect(await coordinator.commitPreparedTermination() == false)
        coordinator.requestCloseForTermination { callbacks.results.append($0) }
        #expect(callbacks.results == [true, true] && window.closeCalls == 0)
        #expect(await coordinator.commitPreparedTermination())
        #expect(coordinator.model == nil && window.closeCalls == 1)
        #expect(await store.discards.count == 1)
    }

    @Test
    func newRecordingInExistingWindowInvalidatesOldQuitApproval() async throws {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let window = RecordingWindowDouble()
        let coordinator = ScreenRecordingCoordinator(capture: capture, storage: store, makeWindow: { window })
        coordinator.present()
        let model = try #require(coordinator.model)
        model.start(); await capture.waitForBegin()
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        model.export(to: URL(fileURLWithPath: "/generated-old.mp4"))
        await model.waitForExportForTesting()
        coordinator.requestCloseForTermination { _ in }
        model.discard()
        await model.waitForCancellationForTesting()
        model.options.source = .display
        model.start()
        await waitForRecordingPhase(.selecting, in: model)
        capture.send(.started)
        await waitForRecordingPhase(.recording, in: model)
        #expect(await coordinator.commitPreparedTermination() == false)
        #expect(model.phase == .recording && capture.requests.count == 2 && window.closeCalls == 0)
        #expect(await store.discards.count == 1)
        model.discard(close: true)
        await model.waitForCancellationForTesting()
    }

    @Test
    func reopeningDuringCommitCleanupCancelsWindowCloseAndKeepsFutureSessionAvailable() async throws {
        let capture = RecordingCaptureDouble()
        let store = RecordingStoreDouble()
        let window = RecordingWindowDouble()
        let coordinator = ScreenRecordingCoordinator(capture: capture, storage: store, makeWindow: { window })
        coordinator.present()
        let model = try #require(coordinator.model)
        model.start(); await capture.waitForBegin()
        capture.send(.finished(RecordingTestFixture.summary))
        await model.waitForOperationForTesting()
        model.export(to: URL(fileURLWithPath: "/generated-old.mp4"))
        await model.waitForExportForTesting()
        coordinator.requestCloseForTermination { _ in }
        await store.setBlocksDiscard(true)
        let commit = Task { await coordinator.commitPreparedTermination() }
        await store.waitForDiscard()
        coordinator.present(source: .display)
        model.start()
        #expect(model.phase == .cancelling && capture.requests.count == 1)
        await store.releaseDiscard()
        #expect(await commit.value == false)
        #expect(model.canStart && coordinator.model === model && window.closeCalls == 0)
        model.discard(close: true)
        await model.waitForCancellationForTesting()
    }

}
