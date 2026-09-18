import Darwin
import Dispatch
import Foundation
import Infrastructure

/// Only explicit favorite identity paths are stored; no menu labels, snapshots, handles, queries or history.
public nonisolated protocol CompanionMenuFavoritesStoring: Sendable {
    func load() async throws -> Set<CompanionMenuIdentity>
    func save(_ favorites: Set<CompanionMenuIdentity>) async throws
}
/// All disk work is actor-isolated away from the main actor; URL is owned app support storage.
public actor FileCompanionMenuFavoritesStore: CompanionMenuFavoritesStoring {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.menu-favorites", qos: .utility)
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private nonisolated struct Document: Codable { let version: Int; let favorites: [CompanionMenuIdentity] }
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Set<CompanionMenuIdentity> {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return [] }
            throw CompanionAppMenuError.persistence
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= 262_144 else { throw CompanionAppMenuError.persistence }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let length = bytes.count
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress?.advanced(by: offset), length - offset)
            }
            guard count > 0 else { throw CompanionAppMenuError.persistence }; offset += count
        }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(bytes))
            let result = Set(document.favorites)
            guard document.version == 1, result.count == document.favorites.count, result.count <= 100,
                  result.allSatisfy(\.isValid) else { throw CompanionAppMenuError.persistence }
            return result
        } catch { throw CompanionAppMenuError.persistence }
    }
    public func save(_ favorites: Set<CompanionMenuIdentity>) throws {
        guard favorites.count <= 100, favorites.allSatisfy(\.isValid) else { throw CompanionAppMenuError.persistence }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let ordered = try favorites.map { (try encoder.encode($0), $0) }.sorted { $0.0.lexicographicallyPrecedes($1.0) }.map(\.1)
        let data = try encoder.encode(Document(version: 1, favorites: ordered))
        guard data.count <= 262_144 else { throw CompanionAppMenuError.persistence }
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey]
            let properties = try parent.resourceValues(forKeys: keys)
            guard properties.isSymbolicLink != true, properties.isDirectory == true else { throw CompanionAppMenuError.persistence }
            if let properties = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), properties.isSymbolicLink == true {
                throw CompanionAppMenuError.persistence
            }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw CompanionAppMenuError.persistence }
    }
}
