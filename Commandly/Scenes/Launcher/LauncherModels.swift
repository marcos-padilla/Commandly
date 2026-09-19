import Foundation
import CommandKit

/// Visual grouping inside the launcher list.
enum LauncherSectionKind: String, CaseIterable, Identifiable, Sendable {
    case calculator
    case color
    case gettingStarted
    case suggestions
    case commands
    case applications
    case tools
    case clipboard
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculator: return "Calculator"
        case .color: return "Color"
        case .gettingStarted: return "Getting Started"
        case .suggestions: return "Suggestions"
        case .commands: return "Commands"
        case .applications: return "Applications"
        case .tools: return "Tools"
        case .clipboard: return "Clipboard History"
        case .files: return "Files"
        }
    }
}

/// Kind of accessory label shown on the trailing edge of a row.
enum LauncherItemBadge: String, Sendable, Equatable {
    case walkthrough
    case application
    case command
    case settings
    case placeholder
    case calculator
    case color
    case favorite
    case disabled
    case tool
    case clipboard
    case file

    var title: String {
        switch self {
        case .walkthrough: return "Tour"
        case .application: return "Application"
        case .command: return "Command"
        case .settings: return "Settings"
        case .placeholder: return "Soon"
        case .calculator: return "Calculator"
        case .color: return "Color"
        case .favorite: return "Favorite"
        case .disabled: return "Disabled"
        case .tool: return "Tool"
        case .clipboard: return "Clipboard"
        case .file: return "File"
        }
    }
}

/// What happens when a launcher row is confirmed.
enum LauncherItemAction: Sendable, Equatable {
    case openSettings
    case openFileSearchPermissions
    case dismiss
    case launchApplication(CommandID)
    case executeCommand(CommandReference)
    case openInstalledApplication(bundleIdentifier: String)
    case placeholder(message: String)
    /// Quits Commandly through the app's normal termination path, so unsaved-work review runs.
    case quitApplication
    case copyText(String)
    case calculatorPrimary(resultID: String)
    case colorPrimary(resultID: String)
    case copyClipboardEntry(UUID)
    case openFile(URL)
}

/// Visual icon for a launcher row.
enum LauncherItemIcon: Sendable, Equatable {
    case system(String)
    /// Absolute `.app` bundle path for `NSWorkspace` icon lookup.
    case application(path: String)
}

/// A single row in the launcher.
struct LauncherItem: Identifiable, Sendable, Equatable {
    let id: String
    let section: LauncherSectionKind
    let title: String
    let subtitle: String?
    let icon: LauncherItemIcon
    let badge: LauncherItemBadge
    let keywords: [String]
    let action: LauncherItemAction

    /// Convenience for rows that still use SF Symbols.
    var systemImage: String {
        if case .system(let name) = icon { return name }
        return "app.fill"
    }

    init(
        id: String,
        section: LauncherSectionKind,
        title: String,
        subtitle: String?,
        systemImage: String,
        badge: LauncherItemBadge,
        keywords: [String],
        action: LauncherItemAction
    ) {
        self.init(
            id: id,
            section: section,
            title: title,
            subtitle: subtitle,
            icon: .system(systemImage),
            badge: badge,
            keywords: keywords,
            action: action
        )
    }

    init(
        id: String,
        section: LauncherSectionKind,
        title: String,
        subtitle: String?,
        icon: LauncherItemIcon,
        badge: LauncherItemBadge,
        keywords: [String],
        action: LauncherItemAction
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badge = badge
        self.keywords = keywords
        self.action = action
    }

    func matches(query: String) -> Bool {
        SearchMatchBridge.matches(query: query, title: title, subtitle: subtitle, keywords: keywords)
    }
}

/// Thin bridge so models can share scoring rules with SearchKit without importing it everywhere tests expect.
enum SearchMatchBridge {
    static func matches(query: String, title: String, subtitle: String?, keywords: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        let haystacks = ([title, subtitle].compactMap { $0 } + keywords)
            .map { $0.lowercased() }
        let needle = trimmed.lowercased()
        return haystacks.contains { $0.contains(needle) }
    }
}

enum LauncherPlaceholderCatalog {
    /// Placeholder rows that are not yet backed by registered commands.
    static let nonCommandItems: [LauncherItem] = [
        LauncherItem(
            id: "welcome",
            section: .gettingStarted,
            title: "Welcome to Commandly",
            subtitle: "A quick tour of the keyboard-first launcher",
            systemImage: "sparkles",
            badge: .walkthrough,
            keywords: ["tour", "onboarding", "help", "start"],
            action: .placeholder(message: "Walkthrough will arrive in a later build.")
        ),
        LauncherItem(
            id: "quit-commandly",
            section: .commands,
            title: "Quit Commandly",
            subtitle: "Stop the menu bar agent",
            systemImage: "power",
            badge: .command,
            keywords: ["exit", "stop", "quit"],
            action: .quitApplication
        )
    ]

    static var searchRecords: [PlaceholderSearchRecord] {
        nonCommandItems.map { item in
            PlaceholderSearchRecord(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                keywords: item.keywords,
                systemImage: item.systemImage,
                badge: item.badge,
                section: item.section
            )
        }
    }

    /// The catalog row for a search hit, so a row keeps the action it was declared with.
    static func item(id: String) -> LauncherItem? {
        nonCommandItems.first { $0.id == id }
    }
}
