import Foundation

/// Preferred Commandly appearance.
enum AppAppearancePreference: String, CaseIterable, Sendable, Equatable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Preferred UI text density for launcher and settings surfaces.
enum AppTextSizePreference: String, CaseIterable, Sendable, Equatable, Identifiable {
    case standard
    case larger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Default"
        case .larger: return "Larger"
        }
    }
}

/// Non-secret user preferences for Commandly.
struct AppSettings: Equatable, Sendable {
    var opensAtLogin: Bool
    var prefersCommandlyEmojiPicker: Bool
    /// User confirmed ⌥Space as the launcher gesture during onboarding.
    var hasConfirmedOptionSpaceHotkey: Bool
    var showMenuBarIcon: Bool
    var appearance: AppAppearancePreference
    var textSize: AppTextSizePreference

    static let `default` = AppSettings(
        opensAtLogin: false,
        prefersCommandlyEmojiPicker: false,
        hasConfirmedOptionSpaceHotkey: false,
        showMenuBarIcon: true,
        appearance: .system,
        textSize: .standard
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
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let appearance = "settings.appearance"
        static let textSize = "settings.textSize"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let appearanceRaw = defaults.string(forKey: Key.appearance) ?? AppAppearancePreference.system.rawValue
        let textSizeRaw = defaults.string(forKey: Key.textSize) ?? AppTextSizePreference.standard.rawValue
        let hasMenuBarKey = defaults.object(forKey: Key.showMenuBarIcon) != nil

        return AppSettings(
            opensAtLogin: defaults.bool(forKey: Key.opensAtLogin),
            prefersCommandlyEmojiPicker: defaults.bool(forKey: Key.prefersCommandlyEmojiPicker),
            hasConfirmedOptionSpaceHotkey: defaults.bool(forKey: Key.hasConfirmedOptionSpaceHotkey),
            showMenuBarIcon: hasMenuBarKey ? defaults.bool(forKey: Key.showMenuBarIcon) : true,
            appearance: AppAppearancePreference(rawValue: appearanceRaw) ?? .system,
            textSize: AppTextSizePreference(rawValue: textSizeRaw) ?? .standard
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.opensAtLogin, forKey: Key.opensAtLogin)
        defaults.set(settings.prefersCommandlyEmojiPicker, forKey: Key.prefersCommandlyEmojiPicker)
        defaults.set(settings.hasConfirmedOptionSpaceHotkey, forKey: Key.hasConfirmedOptionSpaceHotkey)
        defaults.set(settings.showMenuBarIcon, forKey: Key.showMenuBarIcon)
        defaults.set(settings.appearance.rawValue, forKey: Key.appearance)
        defaults.set(settings.textSize.rawValue, forKey: Key.textSize)
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
