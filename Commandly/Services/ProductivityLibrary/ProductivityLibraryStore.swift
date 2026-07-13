import Foundation

/// Local persistence boundary for reusable productivity-library items.
nonisolated protocol ProductivityLibraryPersisting: Sendable {
    func loadItems() async throws -> [ProductivityLibraryItem]
    func saveItems(_ items: [ProductivityLibraryItem]) async throws
}

/// Store failures intentionally contain no file paths or user-authored contents.
enum ProductivityLibraryPersistenceError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case unsupportedVersion
    case readFailed
    case writeFailed
}

/// Actor-confined, versioned JSON storage in the user's Application Support directory.
///
/// The file contains private user-authored snippets and notes. Callers must never log the payload,
/// decoded items, or the resolved storage URL.
actor JSONProductivityLibraryStore: ProductivityLibraryPersisting {
    private struct Envelope: Codable {
        let version: Int
        let items: [ProductivityLibraryItem]
    }

    private nonisolated static let currentVersion = 1
    private let explicitFileURL: URL?

    /// Creates the production store, or a store at an injected URL for deterministic tests.
    init(fileURL: URL? = nil) {
        self.explicitFileURL = fileURL
    }

    func loadItems() async throws -> [ProductivityLibraryItem] {
        try Task.checkCancellation()
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try Task.checkCancellation()
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == Self.currentVersion else {
                throw ProductivityLibraryPersistenceError.unsupportedVersion
            }
            return envelope.items
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProductivityLibraryPersistenceError {
            throw error
        } catch {
            throw ProductivityLibraryPersistenceError.readFailed
        }
    }

    func saveItems(_ items: [ProductivityLibraryItem]) async throws {
        try Task.checkCancellation()
        let fileURL = try resolvedFileURL()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                Envelope(version: Self.currentVersion, items: items)
            )
            try Task.checkCancellation()
            try data.write(to: fileURL, options: [.atomic])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProductivityLibraryPersistenceError.writeFailed
        }
    }

    private func resolvedFileURL() throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ProductivityLibraryPersistenceError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Commandly", isDirectory: true)
            .appendingPathComponent("ProductivityLibrary.json", isDirectory: false)
    }
}

/// Actor-backed deterministic persistence used by tests and previews.
actor InMemoryProductivityLibraryStore: ProductivityLibraryPersisting {
    private var items: [ProductivityLibraryItem]
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    init(items: [ProductivityLibraryItem] = []) {
        self.items = items
    }

    func loadItems() async throws -> [ProductivityLibraryItem] {
        try Task.checkCancellation()
        loadCount += 1
        return items
    }

    func saveItems(_ items: [ProductivityLibraryItem]) async throws {
        try Task.checkCancellation()
        self.items = items
        saveCount += 1
    }

    func snapshot() -> [ProductivityLibraryItem] {
        items
    }
}
