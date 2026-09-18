import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

struct GIFAnimationExportTests {
    @Test func nativePreviewPreservesFramesTimingAndOriginalAnimationBytes() async throws {
        let bytes = try await GeneratedGIFData().make(); let decoder = GIFAnimationDecoder()
        try await decoder.validateOriginal(bytes)
        let animation = try await decoder.preview(bytes)
        #expect(animation.frames.count == 4); #expect(animation.originalFrameCount == 4)
        #expect(abs(animation.duration - 0.8) < 0.001)
        #expect(animation.frame(at: 0) === animation.frames[0])
        #expect(animation.frame(at: 0.21) === animation.frames[1])
        #expect(animation.frame(at: 0.81) === animation.frames[0])
        #expect(animation.frame(at: -1) === animation.frames[0])
    }
    @Test func staticAndMalformedContentNeverBecomeAnimatedGIFExports() async throws {
        let decoder = GIFAnimationDecoder(); let still = try await GeneratedGIFData().make(frameCount: 1)
        await #expect(throws: GIFSearchError.notAnimated) { try await decoder.validateOriginal(still) }
        await #expect(throws: GIFSearchError.invalidGIF) { try await decoder.validateOriginal(Data("not a GIF".utf8)) }
        let large = Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)
        await #expect(throws: GIFSearchError.previewTooLarge) { _ = try await decoder.preview(large) }
    }
    @Test func previewBoundsFrameCountWithoutChangingOriginal() async throws {
        let data = try await GeneratedGIFData().make(frameCount: 401, width: 10, height: 10); let decoder = GIFAnimationDecoder()
        try await decoder.validateOriginal(data)
        await #expect(throws: GIFSearchError.previewTooLarge) { _ = try await decoder.preview(data) }
    }
    @Test func previewRejectsExcessDecodedPixelStorage() async throws {
        let data = try await GeneratedGIFData().make(frameCount: 110, width: 360, height: 360)
        await #expect(throws: GIFSearchError.previewTooLarge) { _ = try await GIFAnimationDecoder().preview(data) }
    }
    @MainActor @Test func nativeCopyWritesExactAnimatedBytesAndCancellationDoesNotWrite() async throws {
        let bytes = try await GeneratedGIFData().make(); let capture = GIFExportCapture()
        let exporter = NativeGIFExporter(pasteboard: { capture.copied.append($0); return true }, chooseDestination: { _ in nil })
        try await exporter.copy(bytes); #expect(capture.copied == [bytes])
        #expect(try await exporter.save(bytes, suggestedName: "Fixture.gif") == false)
        let task = Task { try await exporter.copy(bytes) }; task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(capture.copied.count == 1)
    }
    @MainActor @Test func nativeSaveWritesChosenGIFOnlyAndReopensWithMultipleFrames() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let bytes = try await GeneratedGIFData().make(); let destination = parent.appendingPathComponent("Chosen.gif")
        let exporter = NativeGIFExporter(pasteboard: { _ in false }, chooseDestination: { _ in destination })
        #expect(try await exporter.save(bytes, suggestedName: "Fixture.gif"))
        #expect(try Data(contentsOf: destination) == bytes)
        let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 4)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["Chosen.gif"])
    }
    @Test func failedCoordinatedReplacementPreservesDestinationAndCleansOwnedStage() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("Existing.gif"); let initial = Data("Prior selected content".utf8)
        try initial.write(to: destination)
        let replacement = parent.appendingPathComponent("OwnedReplacement", isDirectory: true)
        let writer = NativeGIFFileWriter(files: GIFExportFailureFiles(replacement: replacement))
        await #expect(throws: GIFSearchError.exportFailed) { try await writer.write(Data("Replacement bytes".utf8), to: destination) }
        #expect(try Data(contentsOf: destination) == initial)
        #expect(!FileManager.default.fileExists(atPath: replacement.path))
    }
    @Test func nativeExistingGIFReplacementReopensOriginalAnimationBytes() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("Existing.gif")
        let initial = try await GeneratedGIFData().make(frameCount: 2)
        try initial.write(to: destination)
        let replacement = try await GeneratedGIFData().make(frameCount: 4)
        try await NativeGIFFileWriter().write(replacement, to: destination)
        #expect(try Data(contentsOf: destination) == replacement)
        let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 4)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["Existing.gif"])
    }
    @Test func destinationChangeDuringCoordinationPreservesNewExternalContent() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("Existing.gif")
        try Data("Original".utf8).write(to: destination)
        let changed = Data("New external edit while save was preparing".utf8)
        let writer = NativeGIFFileWriter(files: GIFExportChangingFiles(replacement: parent.appendingPathComponent("OwnedReplacement"), changed: changed))
        await #expect(throws: GIFSearchError.exportFailed) { try await writer.write(Data("Do not overwrite the new edit".utf8), to: destination) }
        #expect(try Data(contentsOf: destination) == changed)
    }
    @Test func cleanupFailureReportsCommittedOutputWithoutClaimingItWasUndone() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("Committed.gif")
        let replacement = parent.appendingPathComponent("OwnedReplacement", isDirectory: true)
        let writer = NativeGIFFileWriter(files: GIFExportCleanupFailureFiles(replacement: replacement))
        let bytes = try await GeneratedGIFData().make()
        await #expect(throws: GIFSearchError.exportCleanupFailed) { try await writer.write(bytes, to: destination) }
        #expect(try Data(contentsOf: destination) == bytes)
    }
    @Test func refusesSymlinkDestinationWithoutChangingItsTarget() async throws {
        let parent = try directory(); defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("target"); let original = Data("Unrelated fixture".utf8); try original.write(to: target)
        let link = parent.appendingPathComponent("link.gif"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let writer = NativeGIFFileWriter()
        await #expect(throws: GIFSearchError.exportFailed) { try await writer.write(Data("New bytes".utf8), to: link) }
        #expect(try Data(contentsOf: target) == original)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-gif-export-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
@MainActor private final class GIFExportCapture { var copied: [Data] = [] }
nonisolated private struct GIFExportFailureFiles: GIFExportFileAccess {
    let replacement: URL
    func replacementDirectory(for destination: URL) throws -> URL { try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false); return replacement }
    func coordinate(at destination: URL, accessor: (URL) throws -> Void) throws { try accessor(destination) }
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws { throw GIFSearchError.exportFailed }
    func removeReplacementDirectory(_ directory: URL) throws { try FileManager.default.removeItem(at: directory) }
}

nonisolated private struct GIFExportCleanupFailureFiles: GIFExportFileAccess {
    let replacement: URL
    func replacementDirectory(for destination: URL) throws -> URL { try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false); return replacement }
    func coordinate(at destination: URL, accessor: (URL) throws -> Void) throws { try accessor(destination) }
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws { try FileManager.default.moveItem(at: staged, to: destination) }
    func removeReplacementDirectory(_ directory: URL) throws { throw GIFSearchError.exportFailed }
}

nonisolated private struct GIFExportChangingFiles: GIFExportFileAccess {
    let replacement: URL
    let changed: Data
    func replacementDirectory(for destination: URL) throws -> URL { try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false); return replacement }
    func coordinate(at destination: URL, accessor: (URL) throws -> Void) throws { try changed.write(to: destination); try accessor(destination) }
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws { throw GIFSearchError.exportFailed }
    func removeReplacementDirectory(_ directory: URL) throws { try FileManager.default.removeItem(at: directory) }
}
