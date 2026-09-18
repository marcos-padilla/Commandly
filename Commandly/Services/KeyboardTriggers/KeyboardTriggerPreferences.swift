import CommandKit
import Foundation
import Infrastructure

nonisolated enum KeyboardTriggerDestination: Codable, Equatable, Sendable {
    case command(CommandReference)
    case quicklink(UUID)
}
nonisolated struct KeyboardTriggerAssignment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let key: CompanionTriggerKey?
    let doubleTap: CompanionDoubleTapKey?
    let requiresHyper: Bool
    let destination: KeyboardTriggerDestination
}
nonisolated struct KeyboardExpansionAssignment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let itemID: UUID
    let keyword: String
}
nonisolated struct KeyboardTriggerPreferences: Codable, Equatable, Sendable {
    var hyperEnabled = false
    var preserveCapsLockTap = true
    var expansionsEnabled = false
    var assignments: [KeyboardTriggerAssignment] = []
    var expansions: [KeyboardExpansionAssignment] = []
}
nonisolated protocol KeyboardTriggerPreferencesStoring: Sendable {
    func load() async throws -> KeyboardTriggerPreferences
    func save(_ value: KeyboardTriggerPreferences) async throws
}
/// Stores configured bindings, never an enabled flag, typed input, expansion bodies or native target data.
actor JSONKeyboardTriggerPreferencesStore: KeyboardTriggerPreferencesStoring {
    private let file: URL?
    private struct Envelope: Codable { let version: Int; let preferences: KeyboardTriggerPreferences }
    init(file: URL? = nil) { self.file = file }
    private func url() throws -> URL {
        if let file { return file }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CompanionKeyboardError.unavailable
        }
        return base.appendingPathComponent("Commandly/KeyboardTriggers.json")
    }
    func load() throws -> KeyboardTriggerPreferences {
        let file = try url()
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 256 * 1024 else {
            throw CompanionKeyboardError.invalidConfiguration
        }
        let value = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        guard value.version == 1, value.preferences.assignments.count <= 72, value.preferences.expansions.count <= 128 else {
            throw CompanionKeyboardError.invalidConfiguration
        }
        return value.preferences
    }
    func save(_ value: KeyboardTriggerPreferences) throws {
        let data = try JSONEncoder().encode(Envelope(version: 1, preferences: value))
        guard data.count <= 256 * 1024 else { throw CompanionKeyboardError.invalidConfiguration }
        let file = try url()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

actor InMemoryKeyboardTriggerPreferencesStore: KeyboardTriggerPreferencesStoring {
    private var value = KeyboardTriggerPreferences()
    func load() -> KeyboardTriggerPreferences { value }
    func save(_ value: KeyboardTriggerPreferences) { self.value = value }
}
