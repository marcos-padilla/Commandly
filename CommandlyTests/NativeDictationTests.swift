import AVFoundation
import CoreMedia
import Foundation
import Infrastructure
import Speech
import Testing
@testable import Commandly

struct NativeDictationTranscriptTests {
    private func range(_ start: Int64, _ duration: Int64) -> CMTimeRange {
        CMTimeRange(start: CMTime(value: start, timescale: 1), duration: CMTime(value: duration, timescale: 1))
    }
    private func attributed(_ text: String, range: CMTimeRange) -> AttributedString {
        var value = AttributedString(text); value.audioTimeRange = range; return value
    }
    @Test func revisedPartialReplacesOnlyMatchingWordTimesAndFinalizes() throws {
        var buffer = NativeDictationTranscriptBuffer()
        let first = range(0, 1); let second = range(1, 1)
        let partial = try buffer.apply(attributed("Hello ", range: first), range: first, finalizationTime: .zero)
        #expect(partial.text == "Hello "); #expect(partial.containsProvisionalText)
        let finalized = try buffer.apply(attributed("Hello, ", range: first), range: first, finalizationTime: first.end)
        #expect(finalized.text == "Hello, "); #expect(!finalized.containsProvisionalText)
        let next = try buffer.apply(attributed("world", range: second), range: second, finalizationTime: first.end)
        #expect(next.text == "Hello, world"); #expect(next.containsProvisionalText)
        let result = try buffer.apply(attributed("world.", range: second), range: second, finalizationTime: second.end)
        #expect(result.text == "Hello, world."); #expect(!result.containsProvisionalText)
    }
    @Test func oversizedUpdateLeavesPreviousTranscriptIntact() throws {
        var buffer = NativeDictationTranscriptBuffer(); let first = range(0, 1)
        _ = try buffer.apply(attributed("Retained ", range: first), range: first, finalizationTime: first.end)
        #expect(throws: DictationError.transcriptLimit) {
            _ = try buffer.apply(attributed(String(repeating: "x", count: 64 * 1_024), range: range(1, 1)), range: range(1, 1), finalizationTime: .zero)
        }
        let result = try buffer.apply(attributed("text", range: range(1, 1)), range: range(1, 1), finalizationTime: range(1, 1).end)
        #expect(result.text == "Retained text")
    }
    @Test func nativeConverterAcceptsGeneratedAudioWithoutDevicesOrModels() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)); buffer.frameLength = 1_600
        let samples = try #require(buffer.floatChannelData)
        for index in 0..<1_600 { samples[0][index] = 0 }
        let output = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let converter = AnalyzerInputConverter(analyzerFormat: output)
        let input = try converter.convert(buffer, at: AVAudioTime(sampleTime: 0, atRate: 16_000)) + converter.flush()
        #expect(!input.isEmpty)
    }
}

@MainActor
struct NativeDictationPermissionTests {
    @MainActor private final class Counter { var prompts = 0; var settings = 0 }
    @Test(arguments: [AVAuthorizationStatus.authorized, .denied, .restricted])
    func determinedGrantNeverPrompts(_ state: AVAuthorizationStatus) async {
        let counter = Counter()
        let permission = NativeDictationMicrophonePermission(preflight: { state }, request: { counter.prompts += 1; return true }, settings: { counter.settings += 1 })
        _ = await permission.authorization(); #expect(counter.prompts == 0)
        _ = await permission.requestAuthorization(); #expect(counter.prompts == 0)
        await permission.openSettings(); #expect(counter.settings == 1)
    }
    @Test func undeterminedPromptRequiresRequestAndCancelledIntentDoesNotPrompt() async {
        let counter = Counter()
        let permission = NativeDictationMicrophonePermission(preflight: { .notDetermined }, request: { counter.prompts += 1; return true }, settings: {})
        #expect(await permission.authorization() == .notDetermined); #expect(counter.prompts == 0)
        #expect(await permission.requestAuthorization() == .authorized); #expect(counter.prompts == 1)
        let task = Task { _ = await permission.requestAuthorization() }; task.cancel(); await task.value
        #expect(counter.prompts == 1)
    }
}
