import CommandKit
import Foundation
import Infrastructure

nonisolated struct SystemSettingsCatalogItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let pane: SystemSettingsPane
    let systemImage: String
    let detail: String
    let keywords: [String]
    var toolID: CommandID { CommandID(rawValue: "system.settings-catalog.\(id)") }
    var destinationTitle: String { SystemSettingsPaneRoute.forPane(pane).title }
    var subtitle: String { "Opens \(destinationTitle) in System Settings" }
}

/// Static discovery metadata: searching never reads preferences, device state or the filesystem.
nonisolated enum SystemSettingsCatalog {
    static let items: [SystemSettingsCatalogItem] = [
        .init(id: "display", title: "Display Settings", pane: .displays, systemImage: "display", detail: "Choose a display and review its available options. This opens the Displays page.", keywords: ["screen", "monitor", "display", "arrangement"]),
        .init(id: "display-brightness", title: "Display Brightness Settings", pane: .displays, systemImage: "sun.max", detail: "Opens the same Displays page. Brightness and automatic brightness controls depend on the display and Mac.", keywords: ["screen", "light", "dim", "brightness"]),
        .init(id: "display-color-profile", title: "Display Color Profile Settings", pane: .displays, systemImage: "paintpalette", detail: "Opens the same Displays page. Select your display to review its color profile or available presets.", keywords: ["colour", "color", "profile", "monitor"]),
        .init(id: "display-orientation", title: "Display Orientation Settings", pane: .displays, systemImage: "rotate.right", detail: "Opens the same Displays page. Rotation appears only for compatible displays; this command does not rotate the screen.", keywords: ["rotate", "rotation", "portrait", "landscape", "orientation"]),
        .init(id: "display-resolution", title: "Display Resolution Settings", pane: .displays, systemImage: "arrow.up.left.and.arrow.down.right", detail: "Opens the same Displays page so you can choose a resolution in macOS. This command does not apply a display mode.", keywords: ["resolution", "pixels", "retina", "hidpi"]),
        .init(id: "display-scale", title: "Display Scaling Settings", pane: .displays, systemImage: "textformat.size", detail: "Opens the same Displays page. Use the text-size or resolution choices available for your display.", keywords: ["scale", "scaling", "larger text", "more space", "display size"]),
        item("appearance", "Appearance Settings", .appearance, "circle.lefthalf.filled", "Review light or dark appearance and available interface colors.", ["dark", "light", "accent", "color"]),
        item("wifi", "Wi-Fi Settings", .wifi, "wifi", "Review wireless networks and their macOS controls.", ["wireless", "wifi", "wi fi", "internet"]),
        item("bluetooth", "Bluetooth Settings", .bluetooth, "antenna.radiowaves.left.and.right", "Review Bluetooth devices and connection options.", ["pair", "wireless", "devices"]),
        item("network", "Network Settings", .network, "network", "Review network services in macOS.", ["ethernet", "internet", "connection", "ip"]),
        item("sound", "Sound Settings", .sound, "speaker.wave.2", "Review input, output and sound options.", ["audio", "volume", "microphone", "speaker"]),
        item("keyboard", "Keyboard Settings", .keyboard, "keyboard", "Review typing, keyboard shortcuts and input options.", ["typing", "shortcuts", "dictation", "input"]),
        item("trackpad", "Trackpad Settings", .trackpad, "rectangle.and.hand.point.up.left", "Review gestures and pointing options available on this Mac.", ["gesture", "click", "scroll", "pointer"]),
        item("mouse", "Mouse Settings", .mouse, "computermouse", "Review options for a connected mouse.", ["pointer", "click", "scroll"]),
        item("accessibility", "Accessibility Settings", .accessibility, "accessibility", "Review macOS accessibility features. No permission is requested by this navigation command.", ["voiceover", "zoom", "vision", "hearing"]),
        item("privacy-security", "Privacy & Security Settings", .privacySecurity, "hand.raised", "Review privacy and security categories, then choose the relevant category yourself.", ["permission", "permissions", "camera", "screen recording", "security"]),
        item("notifications", "Notification Settings", .notifications, "bell", "Review app notification preferences.", ["notifications", "alerts", "banners"]),
        item("focus", "Focus Settings", .focus, "moon", "Review Focus modes and their options.", ["do not disturb", "dnd", "concentration"]),
        item("battery", "Battery Settings", .battery, "battery.100", "Review available battery and power options. Controls vary by Mac model.", ["energy", "power", "charging", "low power"]),
        item("general", "General Settings", .general, "gearshape", "Review the General section of System Settings.", ["system", "about", "mac"]),
        item("software-update", "Software Update Settings", .softwareUpdate, "arrow.triangle.2.circlepath", "Open macOS update settings. Commandly does not start an update or change update preferences.", ["macos", "updates", "upgrade"]),
        item("storage", "Storage Settings", .storage, "internaldrive", "Review macOS storage information and its available recommendations.", ["disk", "space", "capacity"]),
        item("login-items", "Login Items & Extensions Settings", .loginItems, "list.bullet.rectangle", "Review login items and extensions in macOS. No registration or toggle occurs here.", ["startup", "background", "launch", "extensions"]),
        item("date-time", "Date & Time Settings", .dateTime, "calendar", "Review date, time and time-zone settings.", ["clock", "timezone", "time zone"]),
        item("language-region", "Language & Region Settings", .languageRegion, "globe", "Review languages, regional formats and related macOS options.", ["locale", "translation", "language", "region"]),
        item("printers", "Printers & Scanners Settings", .printers, "printer", "Review available printers and scanners.", ["print", "scanner", "printer"]),
        item("time-machine", "Time Machine Settings", .timeMachine, "clock.arrow.circlepath", "Review Time Machine settings. Commandly does not start or configure a backup.", ["backup", "restore", "time machine"])
    ]

    static func item(toolID: CommandID) -> SystemSettingsCatalogItem? { items.first { $0.toolID == toolID } }
    static func matching(_ query: String) -> [SystemSettingsCatalogItem] {
        let bytes = Array(query.utf8.prefix(257))
        guard bytes.count <= 256 else { return [] }
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return items }
        return items.filter { item in
            let searchable = ([item.title, item.destinationTitle] + item.keywords).joined(separator: " ").lowercased()
            return tokens.allSatisfy { searchable.contains($0) }
        }
    }

    private static func item(_ id: String, _ title: String, _ pane: SystemSettingsPane, _ symbol: String, _ detail: String, _ keywords: [String]) -> SystemSettingsCatalogItem {
        .init(id: id, title: title, pane: pane, systemImage: symbol, detail: detail, keywords: keywords)
    }
}

nonisolated enum SystemSettingsNavigationFeedback {
    static func message(_ result: SystemSettingsNavigationResult) -> String {
        switch result {
        case .requestedPane(let pane): "Requested \(SystemSettingsPaneRoute.forPane(pane).title) in System Settings."
        case .openedApplication(fallbackFor: nil): "System Settings opened."
        case .openedApplication(fallbackFor: let pane?):
            "The destination couldn’t be opened directly. System Settings opened; choose \(SystemSettingsPaneRoute.forPane(pane).title) in its sidebar or search."
        }
    }
}
