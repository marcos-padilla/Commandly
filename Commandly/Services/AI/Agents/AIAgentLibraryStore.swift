import AIKit
import Darwin
import Dispatch
import Foundation

nonisolated protocol AIAgentLibraryStoring: Sendable {
    func load() async throws -> AIAgentLibraryDocument
    func save(_ value: AIAgentLibraryDocument, replacing revision: UUID) async throws
    func importSkill(from url: URL) async throws -> AIAgentSkill
}
/// Serial bounded file persistence; paths/content never enter logs. Files have owner-only permissions.
actor LocalAIAgentLibraryStore: AIAgentLibraryStoring {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.ai-agent-library", qos: .utility)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private let directory: URL
    private var current: AIAgentLibraryDocument?
    private static let maximumBytes = 5 * 1_024 * 1_024
    init(directory: URL) { self.directory = directory }
    static func applicationStore() -> LocalAIAgentLibraryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return LocalAIAgentLibraryStore(directory: support.appendingPathComponent("Commandly/AI Agents", isDirectory: true))
    }
    func load() throws -> AIAgentLibraryDocument {
        if let current { return current }
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("library-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            let empty = AIAgentLibraryDocument(); current = empty; return empty
        }
        do {
            let bytes = try read(url, maximum: Self.maximumBytes)
            let value = try JSONDecoder().decode(AIAgentLibraryDocument.self, from: bytes)
            try value.validate(); current = value; return value
        } catch is CancellationError { throw CancellationError() }
        catch { throw AIAgentLibraryError.unreadable }
    }
    func save(_ value: AIAgentLibraryDocument, replacing revision: UUID) throws {
        try Task.checkCancellation(); try value.validate()
        guard try load().revision == revision else { throw AIAgentLibraryError.changed }
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= Self.maximumBytes else { throw AIAgentLibraryError.tooLarge }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dir >= 0 else { throw AIAgentLibraryError.writeFailed }
            defer { close(dir) }
            let temporary = "save-" + UUID().uuidString + ".tmp"
            let fd = openat(dir, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw AIAgentLibraryError.writeFailed }
            defer { close(fd); unlinkat(dir, temporary, 0) }
            try bytes.withUnsafeBytes { buffer in
                guard let start = buffer.baseAddress else { throw AIAgentLibraryError.writeFailed }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, start.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw AIAgentLibraryError.writeFailed }
                    offset += count
                }
            }
            guard fsync(fd) == 0 else { throw AIAgentLibraryError.writeFailed }
            try Task.checkCancellation()
            guard renameat(dir, temporary, dir, "library-v1.json") == 0 else { throw AIAgentLibraryError.writeFailed }
            current = value
        } catch is CancellationError { throw CancellationError() }
        catch { throw AIAgentLibraryError.writeFailed }
    }
    func importSkill(from url: URL) throws -> AIAgentSkill {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try read(url, maximum: 32_768)
            return try JSONDecoder().decode(AIAgentSkillFile.self, from: data).importedSkill()
        } catch is CancellationError { throw CancellationError() }
        catch { throw AIAgentLibraryError.invalidData }
    }
    private func read(_ url: URL, maximum: Int) throws -> Data {
        try Task.checkCancellation()
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw AIAgentLibraryError.unreadable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximum else { throw AIAgentLibraryError.tooLarge }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while result.count <= maximum {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximum + 1 - result.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw AIAgentLibraryError.unreadable }
            if count == 0 { return result }
            result.append(contentsOf: buffer.prefix(count)); try Task.checkCancellation()
        }
        throw AIAgentLibraryError.tooLarge
    }
}
actor InMemoryAIAgentLibraryStore: AIAgentLibraryStoring {
    private var value: AIAgentLibraryDocument
    init(_ value: AIAgentLibraryDocument = .init()) { self.value = value }
    func load() -> AIAgentLibraryDocument { value }
    func save(_ value: AIAgentLibraryDocument, replacing revision: UUID) throws {
        guard self.value.revision == revision else { throw AIAgentLibraryError.changed }
        try value.validate(); self.value = value
    }
    func importSkill(from url: URL) throws -> AIAgentSkill { throw AIAgentLibraryError.unavailable }
}
