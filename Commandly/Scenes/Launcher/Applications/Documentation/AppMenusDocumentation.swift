import Foundation

extension RegisteredApplicationDocumentation {
    static let appMenus = LauncherApplicationDocumentation(category: .productivity,
        overview: "Search and invoke accessible commands in the app that was active when App Menus opened. Favorite commands are matched against each fresh menu snapshot.",
        sections: [DocumentationSection(id: "app-menus.use", title: "Use App Menus", blocks: [
            .steps("app-menus.steps", ["Connect the signed companion in System Integration and explicitly enable App Menus.",
                "Activate the app you want, open Commandly, and choose App Menus or Favorite App Menus.",
                "Search, select a command, then press Return to invoke it. Use the star button to save or remove its favorite identity."]),
            .paragraph("app-menus.access", "Accessibility must be enabled for the companion in System Settings. Commandly checks permission without prompting. A menu action can change the target app’s data. Disabled items cannot be invoked.")]),
        DocumentationSection(id: "app-menus.privacy", title: "Privacy and Recovery", blocks: [
            .paragraph("app-menus.limits", "At most 500 menu entries are retained for 30 seconds. App changes, menu changes, disconnection or launcher dismissal invalidate targets. Close and reopen after an app change. Read Menus refreshes an expired snapshot for the same app. A timeout after invocation can mean the command ran; check the app before retrying."),
            .paragraph("app-menus.favorites", "Only bundle identity and hashed menu path components are stored locally. Titles, snapshots, queries, invocation handles and history are not saved. Favorites may stop matching after menu reordering, renaming or language changes; star the current command again.")])],
        keywords: ["menu", "current app", "commands", "favorite", "accessibility", "companion"])
}
