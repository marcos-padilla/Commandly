import Foundation
import Testing
@testable import Persistence

struct PersistenceTests {
    @Test func inMemoryStoreRoundTrip() async throws {
        let store = InMemoryPersistenceStore()
        let payload = Data("foundation".utf8)
        try await store.write(key: "greeting", value: payload)
        let loaded = try await store.read(key: "greeting")
        #expect(loaded == payload)
    }

    @Test func inMemoryStoreRemove() async throws {
        let store = InMemoryPersistenceStore()
        try await store.write(key: "temp", value: Data("x".utf8))
        try await store.remove(key: "temp")
        let loaded = try await store.read(key: "temp")
        #expect(loaded == nil)
    }

    @Test func migrationVersionOrdering() {
        let older = MigrationVersion(rawValue: 1)
        let newer = MigrationVersion(rawValue: 2)
        #expect(older < newer)
    }
}
