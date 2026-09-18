import Darwin
import Foundation
import Infrastructure

nonisolated struct DictationHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let text: String
    let languageID: String
    let languageName: String
    let durationSeconds: Double
    var title: String { String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(100) ?? "Dictation".prefix(100)) }
    var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 64 * 1_024
            && !languageID.isEmpty && languageID.utf8.count <= 128 && languageName.utf8.count <= 256
            && createdAt.timeIntervalSince1970.isFinite && durationSeconds.isFinite && (0...3_600).contains(durationSeconds)
    }
}
nonisolated protocol DictationHistoryStoring: Sendable {
    func load() async throws -> [DictationHistoryEntry]
    func save(_ entry: DictationHistoryEntry) async throws -> [DictationHistoryEntry]
    func delete(id: UUID) async throws -> [DictationHistoryEntry]
    func clear() async throws
}

/// Only explicit Save writes transcripts. One injected actor serializes mutations; no audio is stored.
actor JSONDictationHistoryStore {
    private let configuredURL: URL?
    private let maximumBytes = 2 * 1_024 * 1_024
    init(fileURL: URL? = nil) { configuredURL = fileURL }
    func load() throws -> [DictationHistoryEntry] {
        try Task.checkCancellation()
        let url = try location()
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if directory < 0 { if errno == ENOENT { return [] }; throw DictationError.historyUnavailable }
        defer { close(directory) }
        let descriptor = openat(directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 { if errno == ENOENT { return [] }; throw DictationError.historyUnavailable }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= maximumBytes else { throw DictationError.historyCorrupt }
        var data = Data(); var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try Task.checkCancellation()
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw DictationError.historyUnavailable }
            guard data.count + count <= maximumBytes else { throw DictationError.historyCorrupt }
            data.append(contentsOf: chunk.prefix(count))
        }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw DictationError.historyCorrupt }
        guard document.version == 1, document.entries.count <= 50,
              document.entries.allSatisfy(\.isValid), Set(document.entries.map(\.id)).count == document.entries.count else { throw DictationError.historyCorrupt }
        return document.entries.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ entry: DictationHistoryEntry) throws -> [DictationHistoryEntry] {
        guard entry.isValid else { throw DictationError.historyUnavailable }
        var values = try load()
        if let index = values.firstIndex(where: { $0.id == entry.id }) { values[index] = entry }
        else { guard values.count < 50 else { throw DictationError.historyFull }; values.insert(entry, at: 0) }
        try write(values)
        return values.sorted { $0.createdAt > $1.createdAt }
    }
    func delete(id: UUID) throws -> [DictationHistoryEntry] {
        var values = try load(); values.removeAll { $0.id == id }; try write(values); return values
    }
    func clear() throws { try write([]) }
    private func location() throws -> URL {
        if let configuredURL { return configuredURL }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw DictationError.historyUnavailable }
        return base.appendingPathComponent("Commandly/Dictation", isDirectory: true).appendingPathComponent("history.json")
    }
    private func write(_ entries: [DictationHistoryEntry]) throws {
        try Task.checkCancellation()
        let data: Data
        do { data = try JSONEncoder().encode(Document(version: 1, entries: entries)) }
        catch { throw DictationError.historyUnavailable }
        guard data.count <= maximumBytes else { throw DictationError.historyFull }
        let url = try location(); let parent = url.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { throw DictationError.historyUnavailable }
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw DictationError.historyUnavailable }
        defer { close(directory) }
        guard fchmod(directory, 0o700) == 0 else { throw DictationError.historyUnavailable }
        let temporary = ".dictation-" + UUID().uuidString
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw DictationError.historyUnavailable }
        defer { close(descriptor); _ = unlinkat(directory, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = Darwin.write(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw DictationError.historyUnavailable }
                guard count > 0 else { throw DictationError.historyUnavailable }; offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw DictationError.historyUnavailable }
        try Task.checkCancellation()
        guard renameat(directory, temporary, directory, url.lastPathComponent) == 0 else { throw DictationError.historyUnavailable }
    }
    private struct Document: Codable { let version: Int; let entries: [DictationHistoryEntry] }
}
extension JSONDictationHistoryStore: DictationHistoryStoring {}
