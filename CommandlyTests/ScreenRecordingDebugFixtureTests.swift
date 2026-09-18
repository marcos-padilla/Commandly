#if DEBUG
import AVFoundation
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Generated recording acceptance fixture", .timeLimit(.minutes(1)))
struct ScreenRecordingDebugFixtureTests {
    @Test
    func generatedVideoIsPlayableAndHasNoAudioTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recording-generated-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeScreenRecordingStore(root: root, freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        let summary = try await ScreenRecordingDebugMovieWriter().write(to: draft)
        let artifact = try await store.finalize(draft, summary: summary, limits: ScreenRecordingLimits())
        #expect(artifact.summary.pixelWidth == 640 && artifact.summary.pixelHeight == 360)
        #expect(artifact.summary.fileBytes > 0 && artifact.summary.duration == 1)
        let asset = AVURLAsset(url: draft.url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.isEmpty)
        try await store.discard(draft)
    }
}
#endif
