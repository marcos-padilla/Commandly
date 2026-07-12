import Foundation

/// Visual grouping inside the launcher list.
enum LauncherSectionKind: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted
    case suggestions
    case commands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .suggestions: return "Suggestions"
        case .commands: return "Commands"
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

    var title: String {
        switch self {
        case .walkthrough: return "Tour"
        case .application: return "Application"
        case .command: return "Command"
        case .settings: return "Settings"
        case .placeholder: return "Soon"
        }
    }
}

/// What happens when a launcher row is confirmed (frontend placeholders for now).
enum LauncherItemAction: Sendable, Equatable {
    case openSettings
    case dismiss
    case placeholder(message: String)
}

/// A single row in the launcher. Placeholder-backed until real commands ship.
struct LauncherItem: Identifiable, Sendable, Equatable {
    let id: String
    let section: LauncherSectionKind
    let title: String
    let subtitle: String?
    let systemImage: String
    let badge: LauncherItemBadge
    let keywords: [String]
    let action: LauncherItemAction

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        let haystacks = ([title, subtitle].compactMap { $0 } + keywords)
            .map { $0.lowercased() }
        let needle = trimmed.lowercased()
        return haystacks.contains { $0.contains(needle) }
    }
}

enum LauncherPlaceholderCatalog {
    /// Static frontend catalog. Not wired to real execution.
    static let items: [LauncherItem] = [
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
            id: "open-settings",
            section: .suggestions,
            title: "Open Settings",
            subtitle: "Preferences, permissions, and about",
            systemImage: "gearshape",
            badge: .settings,
            keywords: ["preferences", "general"],
            action: .openSettings
        ),
        LauncherItem(
            id: "search-files",
            section: .suggestions,
            title: "Search Files",
            subtitle: "Find documents on your Mac",
            systemImage: "doc.text.magnifyingglass",
            badge: .command,
            keywords: ["files", "finder", "documents"],
            action: .placeholder(message: "File search is not implemented yet.")
        ),
        LauncherItem(
            id: "clipboard-history",
            section: .suggestions,
            title: "Clipboard History",
            subtitle: "Browse recent copies",
            systemImage: "clipboard",
            badge: .command,
            keywords: ["paste", "history"],
            action: .placeholder(message: "Clipboard history is not implemented yet.")
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
            id: "color-meter",
            section: .suggestions,
            title: "Digital Color Meter",
            subtitle: nil,
            systemImage: "eyedropper",
            badge: .application,
            keywords: ["color", "picker"],
            action: .placeholder(message: "App launching is not implemented yet.")
        ),
        LauncherItem(
            id: "snip-link",
            section: .commands,
            title: "Create Quick Link",
            subtitle: "Save a URL for later",
            systemImage: "link",
            badge: .command,
            keywords: ["bookmark", "url"],
            action: .placeholder(message: "Quick links are not implemented yet.")
        ),
        LauncherItem(
            id: "window-left",
            section: .commands,
            title: "Move Window Left",
            subtitle: "Requires Accessibility later",
            systemImage: "rectangle.split.2x1",
            badge: .placeholder,
            keywords: ["window", "tile"],
            action: .placeholder(message: "Window management is not implemented yet.")
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
}
