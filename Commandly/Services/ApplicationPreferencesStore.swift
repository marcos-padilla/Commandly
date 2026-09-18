import Foundation

/// Per-app open ranking used to boost launcher search.
struct AppUsageRanking: Equatable, Sendable, Codable, Hashable {
    var openCount: Int
    var lastOpenedAt: Date?

    nonisolated static let empty = AppUsageRanking(openCount: 0, lastOpenedAt: nil)
}

/// Non-secret preferences for installed applications (favorites, disable, auto-quit, ranking, aliases, shortcuts).
struct ApplicationPreferences: Equatable, Sendable {
    var favoriteBundleIDs: Set<String>
    var disabledBundleIDs: Set<String>
    var autoQuitBundleIDs: Set<String>
    var ranking: [String: AppUsageRanking]
    var aliases: [String: String] = [:]
    var hotKeys: [String: LauncherHotKey] = [:]

    nonisolated static let `default` = ApplicationPreferences(
        favoriteBundleIDs: [],
        disabledBundleIDs: [],
        autoQuitBundleIDs: [],
        ranking: [:]
    )

    nonisolated func isFavorite(_ bundleIdentifier: String) -> Bool {
        favoriteBundleIDs.contains(bundleIdentifier)
    }

    nonisolated func isDisabled(_ bundleIdentifier: String) -> Bool {
        disabledBundleIDs.contains(bundleIdentifier)
    }

    nonisolated func isAutoQuitEnabled(_ bundleIdentifier: String) -> Bool {
        autoQuitBundleIDs.contains(bundleIdentifier)
    }

    nonisolated func ranking(for bundleIdentifier: String) -> AppUsageRanking {
        ranking[bundleIdentifier] ?? .empty
    }

    nonisolated func alias(for bundleIdentifier: String) -> String? {
        aliases[bundleIdentifier]
    }
}

/// Persists application preference sets.
protocol ApplicationPreferencesStoring: AnyObject, Sendable {
    func load() -> ApplicationPreferences
    func save(_ preferences: ApplicationPreferences)
}

/// UserDefaults-backed store for application preferences.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set.
final class UserDefaultsApplicationPreferencesStore: ApplicationPreferencesStoring, @unchecked Sendable {
    private enum Key {
        static let favorites = "apps.favoriteBundleIDs"
        static let disabled = "apps.disabledBundleIDs"
        static let autoQuit = "apps.autoQuitBundleIDs"
        static let ranking = "apps.ranking"
        static let aliases = "apps.aliases"
        static let hotKeys = "apps.hotKeys"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ApplicationPreferences {
        ApplicationPreferences(
            favoriteBundleIDs: Set(defaults.stringArray(forKey: Key.favorites) ?? []),
            disabledBundleIDs: Set(defaults.stringArray(forKey: Key.disabled) ?? []),
            autoQuitBundleIDs: Set(defaults.stringArray(forKey: Key.autoQuit) ?? []),
            ranking: loadRanking(),
            aliases: loadAliases(),
            hotKeys: loadHotKeys()
        )
    }

    func save(_ preferences: ApplicationPreferences) {
        defaults.set(Array(preferences.favoriteBundleIDs).sorted(), forKey: Key.favorites)
        defaults.set(Array(preferences.disabledBundleIDs).sorted(), forKey: Key.disabled)
        defaults.set(Array(preferences.autoQuitBundleIDs).sorted(), forKey: Key.autoQuit)
        defaults.set(preferences.aliases, forKey: Key.aliases)
        if let data = try? JSONEncoder().encode(preferences.hotKeys) {
            defaults.set(data, forKey: Key.hotKeys)
        }
        if let data = try? JSONEncoder().encode(preferences.ranking) {
            defaults.set(data, forKey: Key.ranking)
        }
    }

    private func loadRanking() -> [String: AppUsageRanking] {
        guard let data = defaults.data(forKey: Key.ranking) else { return [:] }
        return (try? JSONDecoder().decode([String: AppUsageRanking].self, from: data)) ?? [:]
    }

    private func loadHotKeys() -> [String: LauncherHotKey] {
        guard let data = defaults.data(forKey: Key.hotKeys), data.count <= 128 * 1024,
              let stored = try? JSONDecoder().decode([String: LauncherHotKey].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.sorted { $0.key < $1.key }.filter {
            InstalledApplicationShortcuts.isValidBundleIdentifier($0.key)
                && InstalledApplicationShortcuts.isSupported($0.value)
        }.prefix(128).map { ($0.key, $0.value) })
    }

    private func loadAliases() -> [String: String] {
        let stored = defaults.dictionary(forKey: Key.aliases) as? [String: String] ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            if let alias = try? ApplicationAlias.normalized(entry.value) {
                result[entry.key] = alias
            }
        }
    }
}

/// In-memory application preferences for tests and previews.
///
/// `@unchecked Sendable`: mutated from `@MainActor` app/test code.
final class InMemoryApplicationPreferencesStore: ApplicationPreferencesStoring, @unchecked Sendable {
    private var preferences: ApplicationPreferences

    init(preferences: ApplicationPreferences = .default) {
        self.preferences = preferences
    }

    func load() -> ApplicationPreferences {
        preferences
    }

    func save(_ preferences: ApplicationPreferences) {
        self.preferences = preferences
    }
}
