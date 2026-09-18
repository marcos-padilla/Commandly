import CommandKit
import Foundation

enum MenuBarShortcutError: Error { case invalidPreferences, saveFailed }

@MainActor
protocol MenuBarShortcutStoring {
    func load() throws -> [CommandID]
    func save(_ ids: [CommandID]) throws
}

enum MenuBarShortcutPolicy {
    static let maximumItems = 8
    static let maximumPreferenceBytes = 8_192

    static func validate(_ values: [String]) throws -> [CommandID] {
        guard values.count <= maximumItems,
              Set(values).count == values.count,
              values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 &&
                  $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }) else {
            throw MenuBarShortcutError.invalidPreferences
        }
        return values.map { CommandID(rawValue: $0) }
    }
}

/// Stores only a bounded list of registered command IDs, never arguments, queries, or content.
@MainActor
final class UserDefaultsMenuBarShortcutStore: MenuBarShortcutStoring {
    private let defaults: UserDefaults
    private let key = "menuBar.shortcuts.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() throws -> [CommandID] {
        guard let object = defaults.object(forKey: key) else { return [] }
        guard let data = object as? Data, data.count <= MenuBarShortcutPolicy.maximumPreferenceBytes,
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            throw MenuBarShortcutError.invalidPreferences
        }
        return try MenuBarShortcutPolicy.validate(ids)
    }
    func save(_ ids: [CommandID]) throws {
        let values = ids.map(\.rawValue)
        _ = try MenuBarShortcutPolicy.validate(values)
        let data = try JSONEncoder().encode(values)
        guard data.count <= MenuBarShortcutPolicy.maximumPreferenceBytes else { throw MenuBarShortcutError.invalidPreferences }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class InMemoryMenuBarShortcutStore: MenuBarShortcutStoring {
    var ids: [CommandID]
    init(ids: [CommandID] = []) { self.ids = ids }
    func load() -> [CommandID] { ids }
    func save(_ ids: [CommandID]) throws {
        self.ids = try MenuBarShortcutPolicy.validate(ids.map(\.rawValue))
    }
}
