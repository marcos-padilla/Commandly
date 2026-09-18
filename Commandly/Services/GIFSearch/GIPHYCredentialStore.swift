import Foundation
import Infrastructure
import SecurityKit

/// A dedicated Keychain item; API keys never appear in defaults, manifests, error text, or logs.
actor GIPHYCredentialStore {
    private struct Credential: Codable, Sendable { let key: String; let revision: UUID }
    private let secureStore: any SecureStoring
    private let storageKey = SecureStoreKey(rawValue: "gif-search.giphy.api-key.v1")
    private var credential: Credential?
    private var revision = UUID()
    private var loaded = false
    private var loadTask: Task<Credential?, Error>?
    private var isMutating = false
    init(secureStore: any SecureStoring) { self.secureStore = secureStore }
    func state() async throws -> GIFConnectionState {
        try await load()
        return .init(revision: revision, isConfigured: credential != nil)
    }
    func key(matching expected: UUID) async throws -> String {
        try await load()
        guard revision == expected else { throw GIFSearchError.changedConnection }
        guard let credential else { throw GIFSearchError.setupRequired }
        return credential.key
    }
    func configure(_ key: String) async throws -> GIFConnectionState {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(cleaned) else { throw GIFSearchError.invalidKey }
        guard !isMutating else { throw GIFSearchError.credentialsUnavailable }
        invalidate(); isMutating = true
        defer { isMutating = false }
        let value = Credential(key: cleaned, revision: revision)
        do {
            let data = try JSONEncoder().encode(value)
            try await secureStore.write(storageKey, value: data)
            credential = value; loaded = true
            return .init(revision: revision, isConfigured: true)
        } catch { throw GIFSearchError.credentialsUnavailable }
    }
    func disconnect() async throws -> GIFConnectionState {
        guard !isMutating else { throw GIFSearchError.credentialsUnavailable }
        invalidate(); isMutating = true
        defer { isMutating = false }
        do {
            try await secureStore.delete(storageKey); loaded = true
            return .init(revision: revision, isConfigured: false)
        } catch { throw GIFSearchError.credentialsUnavailable }
    }
    private func invalidate() { revision = UUID(); credential = nil; loaded = false; loadTask?.cancel(); loadTask = nil }
    private func load() async throws {
        try Task.checkCancellation()
        guard !isMutating else { throw GIFSearchError.changedConnection }
        if loaded { return }
        let token = revision
        let task: Task<Credential?, Error>
        if let loadTask { task = loadTask }
        else {
            task = Task { [secureStore, storageKey] in
                guard let data = try await secureStore.read(storageKey) else { return nil }
                try Task.checkCancellation()
                guard data.count <= 2_048 else { throw GIFSearchError.credentialsUnavailable }
                let value = try JSONDecoder().decode(Credential.self, from: data)
                guard Self.isValid(value.key) else { throw GIFSearchError.credentialsUnavailable }
                return value
            }
            loadTask = task
        }
        do {
            let value = try await task.value
            try Task.checkCancellation()
            guard !isMutating else { throw GIFSearchError.changedConnection }
            // Another waiter may already have applied this same load. Read current state in that case.
            if loaded { return }
            guard revision == token else { throw GIFSearchError.changedConnection }
            credential = value
            if let value { revision = value.revision }
            loaded = true; loadTask = nil
        } catch is CancellationError { if revision == token { loadTask = nil }; throw CancellationError() }
        catch let error as GIFSearchError { if revision == token { loadTask = nil }; throw error }
        catch { if revision == token { loadTask = nil }; throw GIFSearchError.credentialsUnavailable }
    }
    private static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 256 && key.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}
