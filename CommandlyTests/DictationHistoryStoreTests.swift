import Darwin
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct DictationHistoryStoreTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-dictation-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func entry(id: UUID = UUID(), text: String = "Generated test transcript", date: Double = 100) -> DictationHistoryEntry {
        .init(id: id, createdAt: Date(timeIntervalSince1970: date), text: text, languageID: "en-US", languageName: "English", durationSeconds: 12)
    }
    @Test func loadDoesNotCreateStorageAndIndependentSavesPersistWithoutLoss() async throws {
        let parent = try fixture(); defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("private/history.json"); let store = JSONDictationHistoryStore(fileURL: url)
        #expect(try await store.load().isEmpty); #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        let first = entry(date: 100); let second = entry(date: 200)
        async let a = store.save(first); async let b = store.save(second)
        _ = try await (a, b)
        let reloaded = JSONDictationHistoryStore(fileURL: url)
        #expect(try await reloaded.load() == [second, first])
        let edited = entry(id: first.id, text: "Edited generated text")
        #expect(try await store.save(edited).count == 2)
        #expect(try await store.delete(id: second.id) == [edited])
        try await store.clear(); #expect(try await store.load().isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(contents == ["history.json"])
    }
    @Test func fullHistoryNeverEvictsEarlierTextAndUpdatesStillWork() async throws {
        let parent = try fixture(); defer { try? FileManager.default.removeItem(at: parent) }
        let store = JSONDictationHistoryStore(fileURL: parent.appendingPathComponent("history.json"))
        let values = (0..<50).map { entry(date: Double($0)) }
        for value in values { _ = try await store.save(value) }
        await #expect(throws: DictationError.historyFull) { _ = try await store.save(entry()) }
        #expect(try await store.load().count == 50)
        let first = try #require(values.first)
        _ = try await store.save(entry(id: first.id, text: "Updated without eviction"))
        #expect(try await store.load().count == 50)
    }
    @Test func rejectsCorruptOversizeAndSymlinkReadsAndClearCanRecover() async throws {
        let parent = try fixture(); defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("history.json"); let store = JSONDictationHistoryStore(fileURL: url)
        try Data("broken JSON".utf8).write(to: url)
        await #expect(throws: DictationError.historyCorrupt) { _ = try await store.load() }
        try await store.clear(); #expect(try await store.load().isEmpty)
        try Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1).write(to: url)
        await #expect(throws: DictationError.historyCorrupt) { _ = try await store.load() }
        try FileManager.default.removeItem(at: url)
        let other = parent.appendingPathComponent("other.txt"); let secret = Data("Unrelated generated fixture".utf8)
        try secret.write(to: other); try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        await #expect(throws: DictationError.historyUnavailable) { _ = try await store.load() }
        try await store.clear()
        #expect(try Data(contentsOf: other) == secret)
        #expect(try await store.load().isEmpty)
    }
    @Test func rejectsSymlinkDirectoryAndOversizedEntryWithoutWriting() async throws {
        let parent = try fixture(); defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = JSONDictationHistoryStore(fileURL: link.appendingPathComponent("history.json"))
        await #expect(throws: DictationError.historyUnavailable) { _ = try await linked.save(entry()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        let normal = JSONDictationHistoryStore(fileURL: parent.appendingPathComponent("history.json"))
        await #expect(throws: DictationError.historyUnavailable) { _ = try await normal.save(entry(text: String(repeating: "a", count: 64 * 1_024 + 1))) }
        #expect(try await normal.load().isEmpty)
    }
}
