import Foundation
import Infrastructure

/// Fixed identifiers verified against Apple's installed bundle metadata. No subpane anchors,
/// arbitrary destinations, default URL handlers or private settings-navigation scheme are used.
nonisolated struct SystemSettingsPaneRoute: Equatable, Sendable {
    let title: String
    let extensionName: String
    let bundleIdentifier: String

    var url: URL? { Self.url(bundleIdentifier: bundleIdentifier) }

    static func url(bundleIdentifier: String) -> URL? {
        let bytes = Array(bundleIdentifier.utf8.prefix(161))
        guard !bytes.isEmpty, bytes.count <= 160,
              bundleIdentifier.hasPrefix("com.apple."),
              !bundleIdentifier.hasSuffix("."), !bundleIdentifier.contains(".."),
              bytes.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else { return nil }
        var parts = URLComponents()
        parts.scheme = "x-apple.systempreferences"
        parts.path = bundleIdentifier
        return parts.url
    }

    static func forPane(_ pane: SystemSettingsPane) -> Self {
        switch pane {
        case .displays: .init(title: "Displays", extensionName: "DisplaysExt.appex", bundleIdentifier: "com.apple.Displays-Settings.extension")
        case .appearance: .init(title: "Appearance", extensionName: "Appearance.appex", bundleIdentifier: "com.apple.Appearance-Settings.extension")
        case .wifi: .init(title: "Wi-Fi", extensionName: "Wi-Fi.appex", bundleIdentifier: "com.apple.wifi-settings-extension")
        case .bluetooth: .init(title: "Bluetooth", extensionName: "Bluetooth.appex", bundleIdentifier: "com.apple.BluetoothSettings")
        case .network: .init(title: "Network", extensionName: "Network.appex", bundleIdentifier: "com.apple.Network-Settings.extension")
        case .sound: .init(title: "Sound", extensionName: "Sound.appex", bundleIdentifier: "com.apple.Sound-Settings.extension")
        case .keyboard: .init(title: "Keyboard", extensionName: "KeyboardSettings.appex", bundleIdentifier: "com.apple.Keyboard-Settings.extension")
        case .trackpad: .init(title: "Trackpad", extensionName: "TrackpadExtension.appex", bundleIdentifier: "com.apple.Trackpad-Settings.extension")
        case .mouse: .init(title: "Mouse", extensionName: "MouseExtension.appex", bundleIdentifier: "com.apple.Mouse-Settings.extension")
        case .accessibility: .init(title: "Accessibility", extensionName: "AccessibilitySettingsExtension.appex", bundleIdentifier: "com.apple.Accessibility-Settings.extension")
        case .privacySecurity: .init(title: "Privacy & Security", extensionName: "SecurityPrivacyExtension.appex", bundleIdentifier: "com.apple.settings.PrivacySecurity.extension")
        case .notifications: .init(title: "Notifications", extensionName: "NotificationsSettings.appex", bundleIdentifier: "com.apple.Notifications-Settings.extension")
        case .focus: .init(title: "Focus", extensionName: "FocusSettingsExtension.appex", bundleIdentifier: "com.apple.Focus-Settings.extension")
        case .battery: .init(title: "Battery", extensionName: "PowerPreferences.appex", bundleIdentifier: "com.apple.Battery-Settings.extension")
        case .general: .init(title: "General", extensionName: "GeneralSettings.appex", bundleIdentifier: "com.apple.systempreferences.GeneralSettings")
        case .softwareUpdate: .init(title: "Software Update", extensionName: "SoftwareUpdateSettingsExtension.appex", bundleIdentifier: "com.apple.Software-Update-Settings.extension")
        case .storage: .init(title: "Storage", extensionName: "Storage.appex", bundleIdentifier: "com.apple.settings.Storage")
        case .loginItems: .init(title: "Login Items & Extensions", extensionName: "LoginItems.appex", bundleIdentifier: "com.apple.LoginItems-Settings.extension")
        case .dateTime: .init(title: "Date & Time", extensionName: "DateAndTime Extension.appex", bundleIdentifier: "com.apple.Date-Time-Settings.extension")
        case .languageRegion: .init(title: "Language & Region", extensionName: "Localization.appex", bundleIdentifier: "com.apple.Localization-Settings.extension")
        case .printers: .init(title: "Printers & Scanners", extensionName: "PrinterScannerSettings.appex", bundleIdentifier: "com.apple.Print-Scan-Settings.extension")
        case .timeMachine: .init(title: "Time Machine", extensionName: "TimeMachineSettings.appex", bundleIdentifier: "com.apple.Time-Machine-Settings.extension")
        }
    }
}

nonisolated struct SystemSettingsNavigationPlan: Sendable, Equatable {
    let applicationURL: URL
    let paneURL: URL?
}

nonisolated protocol SystemSettingsResolving: Sendable {
    func resolve(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationPlan
}

@MainActor protocol SystemSettingsWorkspaceOpening: AnyObject {
    func openPane(_ url: URL, applicationURL: URL) async throws
    func openApplication(_ applicationURL: URL) async throws
}
