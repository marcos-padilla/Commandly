import Foundation
import Infrastructure
import SecurityKit

/// One bounded Keychain record atomically retains independent internal-app workspace credentials.
actor SlackEmojiCredentialStore {
    private struct Entry: Codable, Sendable { let workspace: SlackEmojiWorkspace; let token: String }
    private struct Document: Codable, Sendable { let version: Int; let entries: [Entry] }
    private let secureStore: any SecureStoring
    private let key = SecureStoreKey(rawValue: "slack-custom-emoji.connections.v1")
    private var entries: [Entry] = []
    private var loaded = false
    private var generation = UUID()
    private var mutation = false
    private var readTask: Task<[Entry], Error>?
    init(secureStore: any SecureStoring) { self.secureStore = secureStore }
    func workspaces() async throws -> [SlackEmojiWorkspace] { try await load(); return entries.map(\.workspace).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    func token(for workspace: SlackEmojiWorkspace) async throws -> String {
        try await load()
        guard let entry = entries.first(where: { $0.workspace.id == workspace.id }), entry.workspace.revision == workspace.revision else { throw SlackEmojiError.changedConnection }
        return entry.token
    }
    func save(_ workspace: SlackEmojiWorkspace, token: String, replacing: SlackEmojiWorkspace?) async throws {
        try await load(); guard !mutation else { throw SlackEmojiError.changedConnection }
        guard Self.validToken(token) else { throw SlackEmojiError.invalidToken }
        var updated = entries
        if let replacing {
            guard workspace.id == replacing.id, let index = updated.firstIndex(where: { $0.workspace.id == replacing.id && $0.workspace.revision == replacing.revision }) else { throw SlackEmojiError.changedConnection }
            updated[index] = Entry(workspace: workspace, token: token)
        } else {
            guard !updated.contains(where: { $0.workspace.id == workspace.id }) else { throw SlackEmojiError.alreadyConnected }
            guard updated.count < 8 else { throw SlackEmojiError.tooManyConnections }
            updated.append(.init(workspace: workspace, token: token))
        }
        try await commit(updated)
    }
    func remove(_ workspace: SlackEmojiWorkspace) async throws {
        try await load(); guard !mutation else { throw SlackEmojiError.changedConnection }
        guard entries.contains(where: { $0.workspace.id == workspace.id && $0.workspace.revision == workspace.revision }) else { throw SlackEmojiError.changedConnection }
        try await commit(entries.filter { $0.workspace.id != workspace.id })
    }
    private func commit(_ updated: [Entry]) async throws {
        try Task.checkCancellation(); mutation = true; generation = UUID(); readTask?.cancel(); readTask = nil
        defer { mutation = false }
        do {
            if updated.isEmpty { try await secureStore.delete(key) }
            else {
                let data = try JSONEncoder().encode(Document(version: 1, entries: updated))
                guard data.count <= 64 * 1_024 else { throw SlackEmojiError.credentialsUnavailable }
                try await secureStore.write(key, value: data)
            }
            entries = updated; loaded = true // An authorized committed Keychain write is not rolled back by late UI cancellation.
        } catch { entries = []; loaded = false; throw SlackEmojiError.credentialsUnavailable }
    }
    private func load() async throws {
        try Task.checkCancellation(); guard !mutation else { throw SlackEmojiError.changedConnection }; if loaded { return }
        let id = generation; let task: Task<[Entry], Error>
        if let readTask { task = readTask }
        else {
            task = Task { [secureStore, key] in
                guard let data = try await secureStore.read(key) else { return [] }
                try Task.checkCancellation(); guard data.count <= 64 * 1_024 else { throw SlackEmojiError.credentialsUnavailable }
                let document = try JSONDecoder().decode(Document.self, from: data)
                guard document.version == 1, document.entries.count <= 8, Set(document.entries.map { $0.workspace.id }).count == document.entries.count,
                      document.entries.allSatisfy({ Self.validToken($0.token) && SlackEmojiIdentity.valid($0.workspace) }) else { throw SlackEmojiError.credentialsUnavailable }
                return document.entries
            }; readTask = task
        }
        do {
            let result = try await task.value; try Task.checkCancellation()
            guard !mutation, generation == id else { throw SlackEmojiError.changedConnection }
            if !loaded { entries = result; loaded = true }; readTask = nil
        } catch is CancellationError { if generation == id { readTask = nil }; throw CancellationError() }
        catch let error as SlackEmojiError { if generation == id { readTask = nil }; throw error }
        catch { if generation == id { readTask = nil }; throw SlackEmojiError.credentialsUnavailable }
    }
    static func validToken(_ token: String) -> Bool {
        (token.hasPrefix("xoxb-") || token.hasPrefix("xoxe.xoxb-")) && token.utf8.count >= 12 && token.utf8.count <= 4_096
            && token.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 }
    }
}
nonisolated enum SlackEmojiIdentity {
    static func parse(_ data: Data) throws -> SlackEmojiWorkspace {
        let value: Response
        do { value = try JSONDecoder().decode(Response.self, from: data) } catch { throw SlackEmojiError.invalidResponse }
        try SlackEmojiAPIValidation.check(ok: value.ok, error: value.error)
        guard let id = value.team_id, let name = value.team, let text = value.url, let url = URL(string: text), let botID = value.bot_id else { throw SlackEmojiError.invalidIdentity }
        let workspace = SlackEmojiWorkspace(id: id, name: name, url: url, botID: botID, enterpriseID: value.enterprise_id, revision: UUID())
        guard valid(workspace) else { throw SlackEmojiError.invalidIdentity }; return workspace
    }
    static func valid(_ value: SlackEmojiWorkspace) -> Bool {
        identifier(value.id, prefix: "T") && identifier(value.botID, prefix: "B") && !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.name.utf8.count <= 512 && SlackEmojiURLPolicy.workspace(value.url)
            && (value.enterpriseID == nil || value.enterpriseID.map { identifier($0, prefix: "E") } == true)
    }
    private static func identifier(_ value: String, prefix: Character) -> Bool {
        value.first == prefix && (2...64).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }
    private struct Response: Decodable { let ok: Bool; let error: String?; let team_id: String?; let team: String?; let url: String?; let bot_id: String?; let enterprise_id: String? }
}
