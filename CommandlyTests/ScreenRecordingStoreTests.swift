import Darwin
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Private recording artifacts", .timeLimit(.minutes(1)))
nonisolated struct ScreenRecordingStoreTests {
    @Test
    func budgetRejectsPreparationWithoutCreatingAnOutputAndAllowsOneOwnedDraft() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let full = NativeScreenRecordingStore(root: root, validator: RecordingValidatorDouble(), freeBytes: { _ in 0 })
        await #expect(throws: ScreenRecordingError.insufficientDiskSpace) {
            try await full.prepare(container: .mp4, limits: ScreenRecordingLimits())
        }
        let store = NativeScreenRecordingStore(root: root, validator: RecordingValidatorDouble(), freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mov, limits: ScreenRecordingLimits())
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
        await #expect(throws: ScreenRecordingError.busy) {
            try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        }
        try await store.discard(draft)
        let next = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        #expect(next.id != draft.id)
        try await store.discard(next)
    }

    @Test
    func exportRequiresReviewedOwnershipAndAtomicallyReplacesOnlyAfterACompleteCopy() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeScreenRecordingStore(root: root.appendingPathComponent("private"), validator: RecordingValidatorDouble(), freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        let destination = root.appendingPathComponent("explicit-export.mp4")
        let original = Data("generated video bytes".utf8)
        let previous = Data("previous destination".utf8)
        try original.write(to: draft.url)
        try previous.write(to: destination)
        let unreviewed = ScreenRecordingArtifact(draft: draft, summary: RecordingTestFixture.summary)
        await #expect(throws: ScreenRecordingError.exportFailed) { try await store.export(unreviewed, to: destination) }
        let artifact = try await store.finalize(draft, summary: RecordingTestFixture.summary, limits: ScreenRecordingLimits())
        #expect(artifact.summary.fileBytes == Int64(original.count))
        try Data("changed source with a different size".utf8).write(to: draft.url)
        await #expect(throws: ScreenRecordingError.exportFailed) { try await store.export(artifact, to: destination) }
        #expect(try Data(contentsOf: destination) == previous)
        try original.write(to: draft.url)
        // Replacing the reviewed bytes invalidates identity even when the size is restored.
        await #expect(throws: ScreenRecordingError.exportFailed) { try await store.export(artifact, to: destination) }
        let reviewedAgain = try await store.finalize(draft, summary: RecordingTestFixture.summary, limits: ScreenRecordingLimits())
        try await store.export(reviewedAgain, to: destination)
        #expect(try Data(contentsOf: destination) == original)
        let permissions = try FileManager.default.attributesOfItem(atPath: draft.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try await store.discard(draft)
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test
    func oversizedAndUnplayableVideoCannotEnterReview() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeScreenRecordingStore(root: root, validator: RecordingValidatorDouble(playable: false), freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        try Data(repeating: 0, count: 20).write(to: draft.url)
        let limits = ScreenRecordingLimits(maximumArtifactBytes: 10)
        await #expect(throws: ScreenRecordingError.artifactTooLarge) {
            try await store.finalize(draft, summary: RecordingTestFixture.summary, limits: limits)
        }
        await #expect(throws: ScreenRecordingError.invalidArtifact) {
            try await store.finalize(draft, summary: RecordingTestFixture.summary, limits: ScreenRecordingLimits())
        }
        try await store.discard(draft)
    }

    @Test
    func forgedDraftAndSymlinkCannotReadOrRemoveAnotherFile() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeScreenRecordingStore(root: root.appendingPathComponent("private"), validator: RecordingValidatorDouble(), freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        let outside = root.appendingPathComponent("outside.txt")
        let content = Data("generated outside fixture".utf8)
        try content.write(to: outside)
        let forged = ScreenRecordingDraft(id: draft.id, url: outside, container: .mp4)
        await #expect(throws: ScreenRecordingError.invalidArtifact) { try await store.discard(forged) }
        try FileManager.default.createSymbolicLink(at: draft.url, withDestinationURL: outside)
        await #expect(throws: ScreenRecordingError.invalidArtifact) {
            try await store.finalize(draft, summary: RecordingTestFixture.summary, limits: ScreenRecordingLimits())
        }
        try await store.discard(draft)
        #expect(try Data(contentsOf: outside) == content)
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
    }

    @Test
    func startupCleanupRemovesOnlyUnlockedOwnedUUIDDirectories() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = root.appendingPathComponent(UUID().uuidString)
        let active = root.appendingPathComponent(UUID().uuidString)
        let unrelated = root.appendingPathComponent("unrelated")
        for directory in [stale, active, unrelated] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("generated fixture".utf8).write(to: directory.appendingPathComponent("recording.mp4"))
        }
        try Data().write(to: stale.appendingPathComponent(".owner"))
        let descriptor = Darwin.open(active.appendingPathComponent(".owner").path, O_CREAT | O_RDWR | O_EXCL, 0o600)
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        let store = NativeScreenRecordingStore(root: root, validator: RecordingValidatorDouble(), freeBytes: { _ in Int64.max })
        let draft = try await store.prepare(container: .mp4, limits: ScreenRecordingLimits())
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        try await store.discard(draft)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("commandly-recording-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

nonisolated private struct RecordingValidatorDouble: ScreenRecordingValidating {
    var playable = true
    func isPlayableVideo(at url: URL) async throws -> Bool { playable }
}
