import Foundation
import Testing
@testable import Commandly

struct MarkdownPreviewFileWatcherTests {
    @Test(.timeLimit(.minutes(1)))
    func watcherSurvivesAnAtomicSaveAndObservesTheReplacementFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Commandly-MarkdownWatcher-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("document.md")
        try Data("# Initial".utf8).write(to: sourceURL)

        let watcher = DispatchSourceMarkdownPreviewFileWatcher()
        let stream = try await watcher.changes(for: sourceURL)
        let recorder = MarkdownPreviewWatcherChangeRecorder()
        let consumer = Task {
            for await change in stream {
                await recorder.append(change)
            }
        }
        defer { consumer.cancel() }

        try overwriteInPlace("# Ordinary write", at: sourceURL)
        let ordinaryChanges = await recorder.waitForCount(1)
        #expect(ordinaryChanges.last == .contentsChanged)

        try Data("# Atomic replacement".utf8).write(to: sourceURL, options: .atomic)
        let replacementChanges = await recorder.waitForCount(ordinaryChanges.count + 1)
        #expect(replacementChanges.last == .contentsChanged)

        // An atomic save changes the inode. This final in-place write is only observed if the
        // watcher reopened its vnode source for the replacement file.
        try overwriteInPlace("# Write after replacement", at: sourceURL)
        let finalChanges = await recorder.waitForCount(replacementChanges.count + 1)
        #expect(finalChanges.last == .contentsChanged)
    }
}

private actor MarkdownPreviewWatcherChangeRecorder {
    private struct Waiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<[MarkdownPreviewFileChange], Never>
    }

    private var changes: [MarkdownPreviewFileChange] = []
    private var waiters: [Waiter] = []

    func append(_ change: MarkdownPreviewFileChange) {
        changes.append(change)
        let ready = waiters.filter { changes.count >= $0.expectedCount }
        waiters.removeAll { changes.count >= $0.expectedCount }
        for waiter in ready {
            waiter.continuation.resume(returning: changes)
        }
    }

    func waitForCount(_ expectedCount: Int) async -> [MarkdownPreviewFileChange] {
        guard changes.count < expectedCount else { return changes }
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(expectedCount: expectedCount, continuation: continuation))
        }
    }
}

private func overwriteInPlace(_ contents: String, at sourceURL: URL) throws {
    let handle = try FileHandle(forWritingTo: sourceURL)
    defer { try? handle.close() }
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data(contents.utf8))
    try handle.synchronize()
}
