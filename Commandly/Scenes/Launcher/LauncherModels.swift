import Foundation
import CommandKit

/// Visual grouping inside the launcher list.
enum LauncherSectionKind: String, CaseIterable, Identifiable, Sendable {
    case calculator
    case gettingStarted
    case suggestions
    case commands
    case applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculator: return "Calculator"
        case .gettingStarted: return "Getting Started"
        case .suggestions: return "Suggestions"
        case .commands: return "Commands"
        case .applications: return "Applications"
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
    case favorite
    case disabled

    var title: String {
        switch self {
        case .walkthrough: return "Tour"
        case .application: return "Application"
        case .command: return "Command"
        case .settings: return "Settings"
        case .placeholder: return "Soon"
        case .calculator: return "Calculator"
        case .favorite: return "Favorite"
        case .disabled: return "Disabled"
        }
    }
}

/// What happens when a launcher row is confirmed.
enum LauncherItemAction: Sendable, Equatable {
    case openSettings
    case dismiss
    case launchApplication(CommandID)
    case openInstalledApplication(bundleIdentifier: String)
    case placeholder(message: String)
    case copyText(String)
    case calculatorPrimary(resultID: String)
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
            id: "my-schedule",
            section: .suggestions,
            title: "My Schedule",
            subtitle: "Upcoming calendar events",
            systemImage: "calendar",
            badge: .command,
            keywords: ["calendar", "meetings"],
            action: .placeholder(message: "Calendar commands are not implemented yet.")
        ),
        LauncherItem(
            id: "quit-commandly",
            section: .commands,
            title: "Quit Commandly",
            subtitle: "Stop the menu bar agent",
            systemImage: "power",
            badge: .command,
            keywords: ["exit", "stop"],
            action: .placeholder(message: "Use Quit Commandly from the menu bar for now.")
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
                section: item.section,
                message: {
                    if case .placeholder(let message) = item.action { return message }
                    return "Not implemented yet."
                }()
            )
        }
    }
}
