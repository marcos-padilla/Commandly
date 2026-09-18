import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct DictationViewModelTests {
    @Test func loadAndMissingModelNeverPromptCaptureDownloadOrSave() async {
        let context = DictationTestContext(capture: .init(state: .downloadRequired)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting()
        #expect(model.languageID == "en-US")
        #expect(model.availability == .downloadRequired)
        model.requestRecording()
        #expect(!model.canStart)
        #expect(await context.permission.requests == 0)
        #expect(await context.capture.requests.isEmpty)
        #expect(await context.capture.downloads == 0)
        #expect(await context.history.saves == 0)
        #expect(await context.style.requests.isEmpty)
        model.stop()
    }
    @Test(arguments: [DictationMicrophoneAuthorization.denied, .restricted])
    func deniedPermissionNeverStartsInput(_ state: DictationMicrophoneAuthorization) async {
        let context = DictationTestContext(permission: .init(state: state)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.requestRecording(); await model.waitForCaptureForTesting()
        #expect(model.phase == .idle)
        #expect(model.errorMessage != nil)
        #expect(await context.capture.requests.isEmpty)
        model.stop()
    }
    @Test func cancelDuringPermissionRejectsLateGrantAndPreservesPreviousDraft() async {
        let context = DictationTestContext(permission: .init(suspended: true)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.reviewText = "Keep my earlier draft"
        model.requestRecording(); #expect(model.showsReplaceConfirmation)
        model.beginRecording(); await context.permission.waitForRequest()
        model.cancelRecording(); await context.permission.complete(.authorized); await model.waitForStopForTesting()
        #expect(model.phase == .idle)
        #expect(model.reviewText == "Keep my earlier draft")
        #expect(await context.capture.requests.isEmpty)
        model.stop()
    }
    @Test func cancellationDuringPendingNativeStartRejectsLateSession() async {
        let context = DictationTestContext(capture: .init(suspendsStart: true)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.requestRecording()
        await context.capture.waitForStart(); #expect(model.phase == .preparing)
        model.cancelRecording(); #expect(!model.canStart)
        await context.capture.completeStart(); await model.waitForStopForTesting()
        #expect(model.phase == .idle); #expect(model.reviewText.isEmpty)
        let id = await context.capture.requests.first?.id
        #expect(await context.capture.cancellations.contains { $0 == id })
        model.stop()
    }
    @Test func explicitDownloadRefreshesAvailabilityWithoutStartingMicrophone() async {
        let context = DictationTestContext(capture: .init(state: .downloadRequired)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting()
        model.downloadLanguage(); await model.waitForDownloadForTesting()
        #expect(model.availability == .installed); #expect(model.canStart)
        #expect(await context.capture.downloads == 1)
        #expect(await context.permission.requests == 0); #expect(await context.capture.requests.isEmpty)
        model.stop()
    }
    @Test func stopDrainsFinalTextOnceAndSavingPinsRecordingLanguage() async throws {
        let context = DictationTestContext(); let model = context.model()
        model.load(); await model.waitForLoadingForTesting()
        model.microphoneID = "generated-input"; model.requestRecording(); model.requestRecording()
        await waitForDictationPhase(model, .recording)
        let requests = await context.capture.requests; let request = try #require(requests.first)
        #expect(requests.count == 1); #expect(request.microphoneID == "generated-input")
        model.finishRecording(); model.finishRecording(); await model.waitForStopForTesting()
        #expect(model.phase == .stopping); #expect(!model.canCopy)
        await context.capture.emit(.finished(try DictationTranscript(text: "Final words.", containsProvisionalText: false), reachedDurationLimit: false), id: request.id, terminal: true)
        await model.waitForCaptureForTesting()
        #expect(model.phase == .idle); #expect(model.reviewText == "Final words.")
        #expect(await context.capture.finishes == [request.id])
        #expect(await context.history.saves == 0); #expect(await context.pasteboard.values.isEmpty)
        model.languageID = "es-ES"; await model.waitForLoadingForTesting()
        model.saveToHistory(); await model.waitForSaveForTesting()
        let saved = await context.history.entries
        #expect(saved.first?.languageID == "en-US")
        model.copy(); await model.waitForCopyForTesting()
        #expect(await context.pasteboard.values == ["Final words."])
        model.stop()
    }
    @Test func cancelNewRecordingRestoresSavedDraftIdentityAndLanguage() async throws {
        let context = DictationTestContext(); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.reviewText = "Saved original"
        model.saveToHistory(); await model.waitForSaveForTesting()
        let originalID = await context.history.entries.first?.id
        #expect(model.statusMessage != nil)
        model.languageID = "es-ES"; await model.waitForLoadingForTesting()
        model.beginRecording(); await waitForDictationPhase(model, .recording)
        #expect(model.statusMessage == nil)
        model.cancelRecording(); await model.waitForStopForTesting()
        #expect(model.reviewText == "Saved original"); #expect(!model.canSave)
        model.reviewText += " edited"; model.saveToHistory(); await model.waitForSaveForTesting()
        let saved = await context.history.entries
        #expect(saved.count == 1); #expect(saved.first?.id == originalID)
        #expect(saved.first?.languageID == "en-US")
        model.stop()
    }
    @Test func terminalFailureCarriesLatestSnapshotAndUnexpectedEOFRecovers() async throws {
        let context = DictationTestContext(); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.requestRecording(); await waitForDictationPhase(model, .recording)
        let request = try #require(await context.capture.requests.first)
        await context.capture.emit(.failed(.interrupted, transcript: try DictationTranscript(text: "Latest available text", containsProvisionalText: true)), id: request.id, terminal: true)
        await model.waitForCaptureForTesting()
        #expect(model.reviewText == "Latest available text"); #expect(model.hasProvisionalText); #expect(model.canCopy)
        model.beginRecording(); await waitForDictationPhase(model, .recording)
        let second = try #require(await context.capture.requests.last)
        await context.capture.disconnectWithoutTerminal(id: second.id); await model.waitForCaptureForTesting()
        #expect(model.phase == .idle); #expect(model.errorMessage == DictationError.recognitionFailed.errorDescription)
        model.stop()
    }
    @Test func leavingWhileRecordingStopsAndRejectsLateText() async throws {
        let context = DictationTestContext(); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.requestRecording(); await waitForDictationPhase(model, .recording)
        let request = try #require(await context.capture.requests.first)
        model.stop(); await model.waitForStopForTesting()
        await context.capture.emit(.finished(try DictationTranscript(text: "Late private text", containsProvisionalText: false), reachedDurationLimit: false), id: request.id, terminal: true)
        #expect(model.reviewText.isEmpty)
        #expect(await context.capture.cancellations.contains(request.id))
    }
    @Test func inputFailureRetainsDraftAndCanRetryAfterRecovery() async {
        let context = DictationTestContext(capture: .init(startFailure: .microphoneUnavailable)); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.reviewText = "Preserve this"
        model.beginRecording(); await model.waitForCaptureForTesting()
        #expect(model.reviewText == "Preserve this"); #expect(model.canStart)
        await context.capture.setStartFailure(nil); model.beginRecording(); await waitForDictationPhase(model, .recording)
        model.cancelRecording(); await model.waitForStopForTesting(); #expect(model.reviewText == "Preserve this")
        model.stop()
    }
    @Test func styleRequiresExplicitRequestAndUseAndRejectsChangedText() async {
        let context = DictationTestContext(); let model = context.model()
        model.load(); await model.waitForLoadingForTesting(); model.reviewText = "Original wording"
        #expect(await context.style.requests.isEmpty)
        model.styles.rewrite(model.reviewText); await context.style.waitForRequest()
        await context.style.complete("Rewritten wording"); await model.styles.waitForRewriteForTesting()
        #expect(model.reviewText == "Original wording")
        model.useStylePreview(); #expect(model.reviewText == "Rewritten wording")
        model.styles.rewrite(model.reviewText); await context.style.waitForRequest()
        let pending = model.styles.pendingRewriteForTesting
        model.reviewText = "New user edit"
        await context.style.complete("Stale rewrite"); await pending?.value
        model.useStylePreview(); #expect(model.reviewText == "New user edit")
        #expect(model.styles.proposedText.isEmpty)
        model.stop()
    }
}
