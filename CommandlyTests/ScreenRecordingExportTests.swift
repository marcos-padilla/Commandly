import Darwin
import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

@Suite("Selected-file recording export", .timeLimit(.minutes(1)))
nonisolated struct ScreenRecordingExportTests {
    @Test(arguments: [false, true])
    func nativeNewAndReplacementExportsUseOSDirectoryAndPreserveSource(replacing: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        if replacing { try fixture.previous.write(to: fixture.destination) }
        let operations = ExportOperationsDouble()
        try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        #expect(try Data(contentsOf: fixture.destination) == fixture.content)
        #expect(try Data(contentsOf: fixture.source) == fixture.content)
        #expect(try FileManager.default.attributesOfItem(atPath: fixture.destination.path)[.posixPermissions] as? Int == 0o600)
        #expect(operations.state.withLock { $0.replacing } == replacing)
        let directory = try #require(operations.state.withLock { $0.directory })
        #expect(directory != fixture.destination.deletingLastPathComponent())
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(operations.state.withLock { $0.stagedWasComplete })
    }

    @Test(arguments: [ExportFailure.coordination, .publication])
    func nativeBoundaryFailurePreservesExistingFileAndCleansStaging(failure: ExportFailure) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.previous.write(to: fixture.destination)
        let operations = ExportOperationsDouble(failure: failure)
        #expect(throws: ExportTestError.injected) {
            try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        }
        #expect(try Data(contentsOf: fixture.destination) == fixture.previous)
        #expect(try Data(contentsOf: fixture.source) == fixture.content)
        let directory = try #require(operations.state.withLock { $0.directory })
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [false, true])
    func cancellationBeforeCopyOrAtCoordinationKeepsDestinationAndCleansStaging(late: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.previous.write(to: fixture.destination)
        let operations = ExportOperationsDouble(cancelDuring: late ? .coordination : .replacementDirectory)
        let work = Task {
            try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        }
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(try Data(contentsOf: fixture.destination) == fixture.previous)
        let directory = try #require(operations.state.withLock { $0.directory })
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(operations.state.withLock { $0.replacing } == nil)
    }

    @Test(arguments: [false, true])
    func sourceAndDestinationSymlinksDoNotTouchTheirTargets(sourceLink: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside.txt")
        try fixture.previous.write(to: outside)
        let linked = sourceLink ? fixture.source : fixture.destination
        if sourceLink { try FileManager.default.removeItem(at: fixture.source) }
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let operations = ExportOperationsDouble()
        #expect(throws: (any Error).self) {
            try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        }
        #expect(try Data(contentsOf: outside) == fixture.previous)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path) == outside.path)
        #expect(operations.state.withLock { $0.directory } == nil)
    }

    @Test(arguments: [ExportChange.source, .destination, .newCollision, .staged])
    func identityChangesWhileCoordinationWaitsNeverPublish(change: ExportChange) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        if change != .newCollision { try fixture.previous.write(to: fixture.destination) }
        let operations = ExportOperationsDouble(beforeCoordinate: { staged in
            let url = switch change {
            case .source: fixture.source
            case .destination, .newCollision: fixture.destination
            case .staged: staged
            }
            try Data("changed generated fixture".utf8).write(to: url, options: .atomic)
        })
        #expect(throws: ScreenRecordingError.exportFailed) {
            try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        }
        let expected = change == .destination || change == .newCollision ? Data("changed generated fixture".utf8) : fixture.previous
        #expect(try Data(contentsOf: fixture.destination) == expected)
        #expect(operations.state.withLock { $0.replacing } == nil)
        let directory = try #require(operations.state.withLock { $0.directory })
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func coordinatorRedirectIsRejectedAndCleanupFailureIsReported() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.previous.write(to: fixture.destination)
        let alternate = fixture.root.appendingPathComponent("unapproved.mp4")
        let operations = ExportOperationsDouble(redirect: alternate, failCleanup: true)
        #expect(throws: ExportTestError.cleanup) {
            try NativeScreenRecordingExporter(files: operations).export(source: fixture.source, identity: fixture.identity, to: fixture.destination)
        }
        #expect(try Data(contentsOf: fixture.destination) == fixture.previous)
        #expect(!FileManager.default.fileExists(atPath: alternate.path))
        let directory = try #require(operations.state.withLock { $0.directory })
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    private struct Fixture: Sendable {
        let root: URL
        let source: URL
        let destination: URL
        let content: Data
        let previous = Data("existing generated destination".utf8)
        let identity: ScreenRecordingFileIdentity
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-recording-export-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            source = root.appendingPathComponent("source.mp4")
            destination = root.appendingPathComponent("selected.mp4")
            content = Data(repeating: 0xA7, count: 3 * 1_024 * 1_024 + 123)
            try content.write(to: source)
            identity = try ScreenRecordingFileIdentity.read(at: source)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

nonisolated private enum ExportTestError: Error { case injected, cleanup }
nonisolated enum ExportFailure: Sendable { case coordination, publication }
nonisolated enum ExportChange: Sendable { case source, destination, newCollision, staged }
nonisolated private enum ExportCancellation: Sendable { case replacementDirectory, coordination }

nonisolated private final class ExportOperationsDouble: ScreenRecordingExportFileAccess, Sendable {
    struct State { var directory: URL?; var replacing: Bool?; var stagedWasComplete = false }
    let state = Mutex(State())
    let failure: ExportFailure?
    let cancelDuring: ExportCancellation?
    let beforeCoordinate: @Sendable (URL) throws -> Void
    let redirect: URL?
    let failCleanup: Bool
    let native = NativeScreenRecordingExportFileAccess()
    init(failure: ExportFailure? = nil, cancelDuring: ExportCancellation? = nil,
         beforeCoordinate: @escaping @Sendable (URL) throws -> Void = { _ in }, redirect: URL? = nil,
         failCleanup: Bool = false) {
        self.failure = failure; self.cancelDuring = cancelDuring; self.beforeCoordinate = beforeCoordinate
        self.redirect = redirect; self.failCleanup = failCleanup
    }
    func replacementDirectory(for destination: URL) throws -> URL {
        let directory = try native.replacementDirectory(for: destination)
        state.withLock { $0.directory = directory }
        if cancelDuring == .replacementDirectory { withUnsafeCurrentTask { $0?.cancel() } }
        return directory
    }
    func coordinateWrite(at destination: URL, accessor: (URL) throws -> Void) throws {
        if failure == .coordination { throw ExportTestError.injected }
        if cancelDuring == .coordination { withUnsafeCurrentTask { $0?.cancel() } }
        let directory = try #require(state.withLock { $0.directory })
        let staged = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try beforeCoordinate(staged)
        if let redirect { try accessor(redirect) }
        else { try native.coordinateWrite(at: destination, accessor: accessor) }
    }
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws {
        state.withLock { $0.replacing = replacing }
        let bytes = try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? Int
        state.withLock { $0.stagedWasComplete = bytes == 3 * 1_024 * 1_024 + 123 }
        if failure == .publication { throw ExportTestError.injected }
        try native.publish(staged, to: destination, replacing: replacing)
    }
    func removeReplacementDirectory(_ directory: URL) throws {
        if failCleanup { throw ExportTestError.cleanup }
        try native.removeReplacementDirectory(directory)
    }
}
