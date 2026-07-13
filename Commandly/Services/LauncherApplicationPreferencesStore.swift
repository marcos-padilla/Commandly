import CommandKit
import Foundation

/// Persisted user overrides for one registered launcher application.
struct LauncherApplicationPreferences: Codable, Equatable, Sendable {
    var alias: String?
    var hotKey: LauncherHotKey?
    var hasHotKeyOverride: Bool
    var isEnabled: Bool?
    var configuration: [String: LauncherConfigurationValue]

    static let empty = LauncherApplicationPreferences(
        alias: nil,
        hotKey: nil,
        hasHotKeyOverride: false,
        isEnabled: nil,
        configuration: [:]
    )

    init(
        alias: String?,
        hotKey: LauncherHotKey?,
        hasHotKeyOverride: Bool = false,
        isEnabled: Bool?,
        configuration: [String: LauncherConfigurationValue]
    ) {
        self.alias = alias
        self.hotKey = hotKey
        self.hasHotKeyOverride = hasHotKeyOverride
        self.isEnabled = isEnabled
        self.configuration = configuration
    }
}

protocol LauncherApplicationPreferencesStoring: Sendable {
    func preferences(for id: CommandID) -> LauncherApplicationPreferences
    func save(_ preferences: LauncherApplicationPreferences, for id: CommandID)
    func resetPreferences(for id: CommandID)
}

/// UserDefaults-backed storage for non-secret application configuration.
///
/// `@unchecked Sendable` is justified because all encoder, decoder, and defaults access is
/// serialized by `lock`. Configuration schemas must never declare secret values.
final class UserDefaultsLauncherApplicationPreferencesStore: LauncherApplicationPreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedValues: [String: LauncherApplicationPreferences]?

    init(
        defaults: UserDefaults = .standard,
        key: String = "launcher.application.preferences.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func preferences(for id: CommandID) -> LauncherApplicationPreferences {
        lock.withLock {
            loadAll()[id.rawValue] ?? .empty
        }
    }

    func save(_ preferences: LauncherApplicationPreferences, for id: CommandID) {
        lock.withLock {
            var values = loadAll()
            values[id.rawValue] = preferences
            do {
                defaults.set(try encoder.encode(values), forKey: key)
                cachedValues = values
            } catch {
                assertionFailure("Launcher application preferences could not be encoded: \(error)")
            }
        }
    }

    func resetPreferences(for id: CommandID) {
        lock.withLock {
            var values = loadAll()
            values[id.rawValue] = nil
            do {
                defaults.set(try encoder.encode(values), forKey: key)
                cachedValues = values
            } catch {
                assertionFailure("Launcher application preferences could not be encoded: \(error)")
            }
        }
    }

    private func loadAll() -> [String: LauncherApplicationPreferences] {
        if let cachedValues { return cachedValues }
        guard let data = defaults.data(forKey: key) else {
            cachedValues = [:]
            return [:]
        }
        do {
            let values = try decoder.decode(
                [String: LauncherApplicationPreferences].self,
                from: data
            )
            cachedValues = values
            return values
        } catch {
            // A corrupt or obsolete preference payload safely falls back to definition defaults.
            cachedValues = [:]
            return [:]
        }
    }
}

/// Lock-protected deterministic store used by tests and previews.
///
/// `@unchecked Sendable` is justified because every read and mutation of `values` uses `lock`.
final class InMemoryLauncherApplicationPreferencesStore: LauncherApplicationPreferencesStoring, @unchecked Sendable {
    private var values: [CommandID: LauncherApplicationPreferences]
    private let lock = NSLock()

    init(values: [CommandID: LauncherApplicationPreferences] = [:]) {
        self.values = values
    }

    func preferences(for id: CommandID) -> LauncherApplicationPreferences {
        lock.withLock { values[id] ?? .empty }
    }

    func save(_ preferences: LauncherApplicationPreferences, for id: CommandID) {
        lock.withLock { values[id] = preferences }
    }

    func resetPreferences(for id: CommandID) {
        lock.withLock { values[id] = nil }
    }
}
