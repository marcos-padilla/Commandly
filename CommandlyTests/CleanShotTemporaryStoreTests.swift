import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("CleanShot temporary files", .timeLimit(.minutes(1)))
struct CleanShotTemporaryStoreTests {
    @Test
    func explicitStagingPreservesExactPNGWithPrivateUniqueFilesAndExpiry() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock)
        #expect(FileManager.default.fileExists(atPath: store.rootURL.path) == false)
        let image = try await CleanShotTestImageFactory().image()
        let first = try await store.stage(image), second = try await store.stage(image)
        #expect(first.fileURL != second.fileURL && first.id != second.id)
        #expect(try temporary.permissions(store.rootURL) == 0o700 && temporary.permissions(first.fileURL) == 0o600)
        #expect(try temporary.content(first.fileURL) == image.pngData && temporary.content(second.fileURL) == image.pngData)
        await clock.waitUntilScheduled()
        clock.advance(by: 600)
        await store.waitForRetirementForTesting(first); await store.waitForRetirementForTesting(second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path).isEmpty)
    }

    @Test
    func liveLeaseQuotaRejectsMoreFilesWithoutDeletingUnexpiredHandoffs() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let image = try await CleanShotTestImageFactory().image()
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock, maximumFiles: 2)
        let first = try await store.stage(image), second = try await store.stage(image)
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFull) { try await store.stage(image) }
        #expect(try temporary.content(first.fileURL) == image.pngData && temporary.content(second.fileURL) == image.pngData)
        try await store.remove(first)
        let third = try await store.stage(image)
        #expect(third.id != first.id)
    }

    @Test
    func byteQuotaAndMalformedOrMismatchedPNGFailBeforeWriting() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let image = try await CleanShotTestImageFactory().image()
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, maximumBytes: image.pngData.count - 1)
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFull) { try await store.stage(image) }
        let malformed = try ScreenshotImage(pngData: Data([1, 2]), previewPNGData: Data([3]), kind: .window, pixelWidth: 40, pixelHeight: 20)
        let mismatch = try ScreenshotImage(pngData: image.pngData, previewPNGData: image.previewPNGData, kind: .window, pixelWidth: 41, pixelHeight: 20)
        for invalid in [malformed, mismatch] {
            await #expect(throws: ScreenshotAnnotationError.invalidImage) { try await store.stage(invalid) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path).isEmpty)
    }

    @Test
    func staleOwnedFilesAreRemovedOnNextExplicitUseAndSymlinksAreRejected() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock)
        try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let stale = store.rootURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        #expect(FileManager.default.createFile(atPath: stale.path, contents: Data([1]), attributes: [.posixPermissions: 0o600]))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-601)], ofItemAtPath: stale.path)
        let image = try await CleanShotTestImageFactory().image()
        let lease = try await store.stage(image)
        #expect(FileManager.default.fileExists(atPath: stale.path) == false)
        try await store.remove(lease)
        let outside = temporary.directory.appendingPathComponent("outside.png")
        try image.pngData.write(to: outside)
        let link = store.rootURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFailed) { try await store.stage(image) }
        #expect(try temporary.content(outside) == image.pngData)
    }

    @Test
    func substitutedRootAndForgedLeaseCannotDeleteOutsideFile() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock)
        let image = try await CleanShotTestImageFactory().image()
        let lease = try await store.stage(image)
        let outside = temporary.directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let outsideImage = outside.appendingPathComponent(lease.fileURL.lastPathComponent)
        try image.pngData.write(to: outsideImage)
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFailed) {
            try await store.remove(CleanShotFileLease(id: lease.id, fileURL: outsideImage))
        }
        try FileManager.default.removeItem(at: store.rootURL)
        try FileManager.default.createSymbolicLink(at: store.rootURL, withDestinationURL: outside)
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFailed) { try await store.remove(lease) }
        await #expect(throws: ScreenshotAnnotationError.temporaryStorageFailed) { try await store.stage(image) }
        #expect(try temporary.content(outsideImage) == image.pngData)
    }
}
