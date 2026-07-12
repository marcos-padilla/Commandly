import Foundation

/// Non-secret user preferences for Commandly.
struct AppSettings: Equatable, Sendable {
    var opensAtLogin: Bool
    var prefersCommandlyEmojiPicker: Bool
    /// User confirmed ⌥Space as the launcher gesture during onboarding.
    var hasConfirmedOptionSpaceHotkey: Bool

    static let `default` = AppSettings(
        opensAtLogin: false,
        prefersCommandlyEmojiPicker: false,
        hasConfirmedOptionSpaceHotkey: false
    )
}

/// Persists lightweight app settings.
protocol AppSettingsStoring: AnyObject, Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// UserDefaults-backed settings store for non-secret preferences.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set;
/// this type only reads and writes boolean preference keys.
final class UserDefaultsAppSettingsStore: AppSettingsStoring, @unchecked Sendable {
    private enum Key {
        static let opensAtLogin = "settings.opensAtLogin"
        static let prefersCommandlyEmojiPicker = "settings.prefersCommandlyEmojiPicker"
        static let hasConfirmedOptionSpaceHotkey = "settings.hasConfirmedOptionSpaceHotkey"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        AppSettings(
            opensAtLogin: defaults.bool(forKey: Key.opensAtLogin),
            prefersCommandlyEmojiPicker: defaults.bool(forKey: Key.prefersCommandlyEmojiPicker),
            hasConfirmedOptionSpaceHotkey: defaults.bool(forKey: Key.hasConfirmedOptionSpaceHotkey)
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.opensAtLogin, forKey: Key.opensAtLogin)
        defaults.set(settings.prefersCommandlyEmojiPicker, forKey: Key.prefersCommandlyEmojiPicker)
        defaults.set(settings.hasConfirmedOptionSpaceHotkey, forKey: Key.hasConfirmedOptionSpaceHotkey)
    }
}

/// In-memory settings store for tests and previews.
///
/// `@unchecked Sendable`: mutated from `@MainActor` app/test code in this foundation phase.
final class InMemoryAppSettingsStore: AppSettingsStoring, @unchecked Sendable {
    private var settings: AppSettings

    init(settings: AppSettings = .default) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) {
        self.settings = settings
    }
}
