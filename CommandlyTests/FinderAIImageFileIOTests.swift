import Darwin
import Foundation
import Testing
@testable import Commandly

@Suite("Finder AI descriptor image IO", .timeLimit(.minutes(1)))
struct FinderAIImageFileIOTests {
    @Test
    func descriptorWalkRejectsIntermediateSymlinksWithoutReadingTheirTargets() throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let outside = files.base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.png"))
        try FileManager.default.createSymbolicLink(at: files.root.appendingPathComponent("Link"), withDestinationURL: outside)
        let rootIdentity = try Self.identity(files.root)
        #expect(throws: FinderAIWorkspaceError.itemChangedSincePreview) {
            try FinderAIImageFileIO.read(root: files.root, rootIdentity: rootIdentity, components: ["Link", "secret.png"], maximumBytes: 1024, validate: { _ in })
        }
    }

    @Test
    func exclusiveCommitPreservesExistingOutputAndCleansItsStagingFile() throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let output = files.destination.appendingPathComponent("same.png")
        let existing = Data("existing approved-folder file".utf8)
        try existing.write(to: output)
        let rootIdentity = try Self.identity(files.root)
        #expect(throws: FinderAIWorkspaceError.collision) {
            try FinderAIImageFileIO.write(files.sourceData, root: files.root, rootIdentity: rootIdentity,
                directoryComponents: ["Output"], name: "same.png", validateDirectory: { _ in })
        }
        #expect(try Data(contentsOf: output) == existing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path) == ["same.png"])
    }

    @Test
    func movingOpenedDestinationBeforeCommitCannotPublishOutsideApprovedRoot() throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let moved = files.base.appendingPathComponent("MovedOutside", isDirectory: true)
        var validations = 0
        let rootIdentity = try Self.identity(files.root)
        #expect(throws: FinderAIWorkspaceError.itemChangedSincePreview) {
            try FinderAIImageFileIO.write(files.sourceData, root: files.root, rootIdentity: rootIdentity,
                directoryComponents: ["Output"], name: "converted.png") { _ in
                    validations += 1
                    if validations == 2 { try FileManager.default.moveItem(at: files.destination, to: moved) }
                }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test
    func cancelledWriteCreatesNoOutputOrTemporaryFile() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let rootIdentity = try Self.identity(files.root)
        let task = Task {
            try FinderAIImageFileIO.write(files.sourceData, root: files.root, rootIdentity: rootIdentity,
                directoryComponents: ["Output"], name: "converted.png", validateDirectory: { _ in })
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
    }

    private static func identity(_ url: URL) throws -> FinderAIImageDirectoryIdentity {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(descriptor >= 0)
        defer { _ = Darwin.close(descriptor) }
        return try FinderAIImageFileIO.identity(ofDirectory: descriptor)
    }
}
