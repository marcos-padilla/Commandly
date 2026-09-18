import CoreGraphics
import Infrastructure
import ScreenCaptureKit
import Testing
@testable import Commandly

@Suite("Native recording configuration and callback ordering")
struct ScreenRecordingNativeTests {
    @Test
    func bothNativeStartSignalsAreRequiredAndPublishedOnce() {
        var state = ScreenRecordingLifecycle()
        let transition1 = state.claimStarted()
        #expect(!transition1)
        state.outputStarted = true
        let transition2 = state.claimStarted()
        #expect(!transition2)
        state.captureStarted = true
        let transition3 = state.claimStarted()
        #expect(transition3)
        let transition4 = state.claimStarted()
        #expect(!transition4)
    }

    @Test(arguments: [true, false])
    func stopAndFinalizationMayArriveInEitherOrderWithoutEarlyReview(outputFirst: Bool) {
        var state = ScreenRecordingLifecycle()
        state.captureStarted = true
        state.outputStarted = true
        state.requestStop(.user)
        if outputFirst { state.outputFinished = true }
        else { _ = state.captureStopCompleted(nil) }
        let transition5 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition5 == nil)
        if outputFirst { _ = state.captureStopCompleted(nil) }
        else { state.outputFinished = true }
        let transition6 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition6 == .finished(RecordingTestFixture.summary))
        let transition7 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition7 == nil)
    }

    @Test
    func cancellationBeforeStartSuppressesStartedAndDiscardsOnlyAfterShutdown() {
        var state = ScreenRecordingLifecycle()
        state.cancelled = true
        state.requestStop(.user)
        state.captureStarted = true
        state.outputStarted = true
        let transition8 = state.claimStarted()
        #expect(!transition8)
        state.outputFinished = true
        let transition9 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition9 == nil)
        _ = state.captureStopCompleted(nil)
        let transition10 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition10 == .cancelled)
    }

    @Test
    func failedStopKeepsCaptureUnconfirmedAndAllowsExplicitRetry() {
        var state = ScreenRecordingLifecycle()
        state.captureStarted = true
        state.outputStarted = true
        state.outputFinished = true
        state.stopIssued = true
        state.requestStop(.user)
        let transition11 = state.captureStopCompleted(.finalizationFailed)
        #expect(transition11)
        let transition12 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(!state.captureStopped && transition12 == nil)
        state.requestStop(.user, retry: true)
        #expect(!state.stopIssued && !state.stopFailed)
        let transition13 = state.captureStopCompleted(nil)
        #expect(!transition13)
        let transition14 = state.claimCompletion(summary: RecordingTestFixture.summary)
        #expect(transition14 == .finished(RecordingTestFixture.summary))
    }

    @Test
    func configurationNeverCapturesMicrophoneAndBoundsEvenDimensions() throws {
        var settings = ScreenRecordingOptions()
        let muted = ScreenRecordingNativeConfiguration.stream(options: settings, width: 1920, height: 1080)
        #expect(!muted.capturesAudio && !muted.captureMicrophone && muted.excludesCurrentProcessAudio)
        settings.audio = .systemAudio
        let audible = ScreenRecordingNativeConfiguration.stream(options: settings, width: 1280, height: 720)
        #expect(audible.capturesAudio && !audible.captureMicrophone && audible.excludesCurrentProcessAudio)
        let large = try ScreenRecordingNativeConfiguration.dimensions(points: CGSize(width: 3024, height: 1964), scale: 2, resolution: .fullHD)
        #expect(large.0 <= 1920 && large.1 <= 1080 && large.0 % 2 == 0 && large.1 % 2 == 0)
        let small = try ScreenRecordingNativeConfiguration.dimensions(points: CGSize(width: 101, height: 99), scale: 1, resolution: .hd720)
        #expect(small.0 == 100 && small.1 == 98)
        #expect(throws: ScreenRecordingError.selectionInvalid) {
            try ScreenRecordingNativeConfiguration.dimensions(points: .zero, scale: 1, resolution: .fullHD)
        }
    }

    @Test
    func conservativeThresholdRequestsStopBeforeFinalArtifactMaximum() {
        let limits = ScreenRecordingLimits()
        #expect(limits.stopFileBytes < limits.maximumArtifactBytes && limits.requiredFreeBytes > limits.maximumArtifactBytes)
        #expect(ScreenRecordingNativeConfiguration.limitReason(progress: .init(duration: 600, fileBytes: 1), limits: limits) == .durationLimit)
        #expect(ScreenRecordingNativeConfiguration.limitReason(progress: .init(duration: 1, fileBytes: limits.stopFileBytes), limits: limits) == .sizeLimit)
        #expect(ScreenRecordingNativeConfiguration.limitReason(progress: .init(duration: 1, fileBytes: 1), limits: limits) == nil)
    }
}
