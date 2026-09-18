import Foundation
import SearchKit
import Testing
@testable import Commandly

@Suite("File index lifecycle")
@MainActor
struct FileIndexLifecycleTests {
    @Test func dismissalStopsMonitoringAndAReopenStartsOneFreshSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyIndexLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root
            .appendingPathComponent("Index", isDirectory: true)
            .appendingPathComponent("FileIndex.sqlite")
        let indexedFile = root.appendingPathComponent("already-indexed.txt")
        try Data("fixture".utf8).write(to: indexedFile)
        let database = FileIndexDatabase(databaseURL: databaseURL)
        try await database.replaceAuthorizedScopes(with: [root.path])
        try await database.upsert([
            FileIndexRecord(
                path: indexedFile.path,
                rootPath: root.path,
                name: indexedFile.lastPathComponent,
                parentPath: root.path,
                kind: .file,
                category: .documents,
                contentTypeIdentifier: "public.plain-text",
                contentTypeDescription: "Plain text",
                byteCount: 7,
                createdAt: .now,
                modifiedAt: .now,
                lastUsedAt: nil,
                tags: [],
                metadataText: "",
                contentText: "",
                scanGeneration: 1
            )
        ])
        try await database.markFullScanCompleted(at: .now)

        let monitor = RecordingFileIndexChangeMonitor()
        let service = PersistentFileSearchService(
            folderAccessStore: InMemoryFolderAccessStore(),
            databaseURL: databaseURL,
            directAuthorizedScopes: [root],
            changeMonitor: monitor
        )

        service.beginFileSearchSession()
        await yieldUntil { monitor.startCount == 1 }
        #expect(monitor.isRunning)

        service.endFileSearchSession()
        #expect(monitor.isRunning == false)
        #expect(monitor.stopCount == 1)

        service.beginFileSearchSession()
        await yieldUntil { monitor.startCount == 2 }
        #expect(monitor.isRunning)

        service.endFileSearchSession()
        #expect(monitor.isRunning == false)
        #expect(monitor.stopCount == 2)
    }

    @Test func eventBurstsDropDescendantsAlreadyCoveredByAParent() {
        let paths = [
            "/Users/example/Documents/Commandly",
            "/Users/example/Documents/Commandly/Sources/App.swift",
            "/Users/example/Documents/Commandly/Tests/AppTests.swift",
            "/Users/example/Documents/Notes.txt",
            "/Users/example/Documents/Notes.txt",
        ]

        let compacted = FileIndexEventProcessor.compact(paths)
        #expect(compacted.count == 2)
        #expect(Set(compacted) == Set([
            "/Users/example/Documents/Notes.txt",
            "/Users/example/Documents/Commandly",
        ]))
    }

    private func yieldUntil(
        _ condition: () -> Bool,
        maximumYields: Int = 10_000
    ) async {
        for _ in 0..<maximumYields {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class RecordingFileIndexChangeMonitor: FileIndexChangeMonitoring {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        paths: [String],
        onChange: @escaping @Sendable ([String]) -> Void
    ) {
        _ = paths
        _ = onChange
        isRunning = true
        startCount += 1
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }
}
