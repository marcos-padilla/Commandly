import Foundation

/// Configuration for a persistence backend.
public struct PersistenceConfiguration: Sendable, Equatable {
    /// Logical store name.
    public let storeName: String
    /// Expected migration version.
    public let migrationVersion: MigrationVersion

    /// Creates a persistence configuration.
    public init(storeName: String, migrationVersion: MigrationVersion) {
        self.storeName = storeName
        self.migrationVersion = migrationVersion
    }
}

/// Identifies a persistence schema migration version.
public struct MigrationVersion: Sendable, Equatable, Comparable, Codable {
    public let rawValue: Int

    /// Creates a migration version.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MigrationVersion, rhs: MigrationVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Key-value persistence store contract.
public protocol PersistenceStore: Sendable {
    /// Reads a value for a key.
    func read(key: String) async throws -> Data?
    /// Writes a value for a key.
    func write(key: String, value: Data) async throws
    /// Removes a value for a key.
    func remove(key: String) async throws
    /// Removes all values.
    func removeAll() async throws
}

/// Generic repository contract.
public protocol Repository<Item>: Sendable {
    associatedtype Item: Sendable
    associatedtype ID: Hashable & Sendable

    /// Loads an item by identifier.
    func fetch(id: ID) async throws -> Item?
    /// Persists an item.
    func save(_ item: Item) async throws
    /// Deletes an item by identifier.
    func delete(id: ID) async throws
}

/// In-memory persistence store for tests and early development.
public actor InMemoryPersistenceStore: PersistenceStore {
    private var storage: [String: Data] = [:]

    /// Creates an empty in-memory store.
    public init() {}

    public func read(key: String) async throws -> Data? {
        storage[key]
    }

    public func write(key: String, value: Data) async throws {
        storage[key] = value
    }

    public func remove(key: String) async throws {
        storage.removeValue(forKey: key)
    }

    public func removeAll() async throws {
        storage.removeAll()
    }
}
