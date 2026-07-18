import CommandKit
import Foundation

/// The semantic role a registered launcher application plays in the application tree.
enum LauncherApplicationKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case group
    case aiExtension
    case `extension`
    case command
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: return "Group"
        case .aiExtension: return "AI Extension"
        case .extension: return "Extension"
        case .command: return "Command"
        case .application: return "Application"
        }
    }

    var systemImage: String {
        switch self {
        case .group: return "folder"
        case .aiExtension: return "sparkles"
        case .extension: return "puzzlepiece.extension"
        case .command: return "terminal"
        case .application: return "app"
        }
    }
}

/// A non-secret value supplied to an application's declared configuration field.
enum LauncherConfigurationValue: Codable, Equatable, Sendable {
    case text(String)
    case boolean(Bool)
    case integer(Int)
    case decimal(Double)

    var textValue: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }

    var booleanValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var decimalValue: Double? {
        guard case .decimal(let value) = self else { return nil }
        return value
    }
}

enum LauncherConfigurationFieldKind: String, Codable, Sendable {
    case text
    case toggle
    case integer
    case decimal
    case selection

    func accepts(_ value: LauncherConfigurationValue) -> Bool {
        switch (self, value) {
        case (.text, .text), (.toggle, .boolean), (.integer, .integer),
             (.decimal, .decimal), (.selection, .text):
            return true
        default:
            return false
        }
    }
}

struct LauncherConfigurationOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?

    init(id: String, title: String, description: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
    }
}

/// Schema for a setting rendered by the generic Applications settings screen.
struct LauncherConfigurationField: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let variable: String
    let title: String
    let description: String?
    let placeholder: String?
    let kind: LauncherConfigurationFieldKind
    let defaultValue: LauncherConfigurationValue
    let options: [LauncherConfigurationOption]

    init(
        id: String,
        variable: String,
        title: String,
        description: String? = nil,
        placeholder: String? = nil,
        kind: LauncherConfigurationFieldKind,
        defaultValue: LauncherConfigurationValue,
        options: [LauncherConfigurationOption] = []
    ) {
        self.id = id
        self.variable = variable
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.kind = kind
        self.defaultValue = defaultValue
        self.options = options
    }
}

/// Cross-platform modifier representation. The Carbon adapter translates these flags.
nonisolated struct LauncherHotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = LauncherHotKeyModifiers(rawValue: 1 << 0)
    static let option = LauncherHotKeyModifiers(rawValue: 1 << 1)
    static let control = LauncherHotKeyModifiers(rawValue: 1 << 2)
    static let shift = LauncherHotKeyModifiers(rawValue: 1 << 3)
}

/// A hardware-key shortcut suitable for system-wide registration.
nonisolated struct LauncherHotKey: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: LauncherHotKeyModifiers

    var displayTitle: String {
        var title = ""
        if modifiers.contains(.control) { title += "⌃" }
        if modifiers.contains(.option) { title += "⌥" }
        if modifiers.contains(.shift) { title += "⇧" }
        if modifiers.contains(.command) { title += "⌘" }
        return title + Self.keyTitle(for: keyCode)
    }

    nonisolated var isValid: Bool {
        modifiers.isEmpty == false && Self.knownKeyTitle(for: keyCode) != nil
    }

    private static func keyTitle(for keyCode: UInt16) -> String {
        return knownKeyTitle(for: keyCode) ?? "Key \(keyCode)"
    }

    private nonisolated static func knownKeyTitle(for keyCode: UInt16) -> String? {
        let titles: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
            25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
            33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space",
            50: "`", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return titles[keyCode]
    }
}

/// Immutable metadata used by discovery, hierarchy, settings, and launch composition.
struct LauncherApplicationDefinition: Identifiable, Sendable {
    let id: CommandID
    let parentID: CommandID?
    let kind: LauncherApplicationKind
    let title: String
    let subtitle: String?
    let systemImage: String
    let order: Int
    let isEnabledByDefault: Bool
    let defaultHotKey: LauncherHotKey?
    let configurationFields: [LauncherConfigurationField]
    let commandManifest: CommandManifest?
    let documentation: LauncherApplicationDocumentation?

    init(
        id: CommandID,
        parentID: CommandID? = nil,
        kind: LauncherApplicationKind,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        order: Int = 0,
        isEnabledByDefault: Bool = true,
        defaultHotKey: LauncherHotKey? = nil,
        configurationFields: [LauncherConfigurationField] = [],
        commandManifest: CommandManifest? = nil,
        documentation: LauncherApplicationDocumentation? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.order = order
        self.isEnabledByDefault = isEnabledByDefault
        self.defaultHotKey = defaultHotKey
        self.configurationFields = configurationFields
        self.commandManifest = commandManifest
        self.documentation = documentation
    }

    init(
        manifest: CommandManifest,
        parentID: CommandID? = nil,
        kind: LauncherApplicationKind,
        order: Int = 0,
        isEnabledByDefault: Bool = true,
        defaultHotKey: LauncherHotKey? = nil,
        configurationFields: [LauncherConfigurationField] = [],
        documentation: LauncherApplicationDocumentation
    ) {
        self.init(
            id: manifest.id,
            parentID: parentID,
            kind: kind,
            title: manifest.title,
            subtitle: manifest.subtitle,
            systemImage: manifest.systemImage,
            order: order,
            isEnabledByDefault: isEnabledByDefault,
            defaultHotKey: defaultHotKey,
            configurationFields: configurationFields,
            commandManifest: manifest,
            documentation: documentation
        )
    }

    static func group(
        id: CommandID,
        parentID: CommandID? = nil,
        title: String,
        subtitle: String? = nil,
        systemImage: String = "folder",
        order: Int = 0
    ) -> LauncherApplicationDefinition {
        LauncherApplicationDefinition(
            id: id,
            parentID: parentID,
            kind: .group,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            order: order
        )
    }
}

/// User values resolved against a definition's defaults.
struct LauncherApplicationResolvedSettings: Equatable, Sendable {
    let alias: String
    let hotKey: LauncherHotKey?
    let isEnabled: Bool
    let configuration: [String: LauncherConfigurationValue]

    func value(for variable: String) -> LauncherConfigurationValue? {
        configuration[variable]
    }
}
