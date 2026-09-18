import Foundation

extension RegisteredApplicationDocumentation {
    static var systemSettingsNavigation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(category: .system,
            overview: "Search a local catalog of macOS settings pages, then open the selected destination in the built-in System Settings app.",
            sections: [DocumentationSection(id: "system-settings.use", title: "Find and Open Settings", blocks: [
                .steps("system-settings.steps", [
                    "Open System Settings in Commandly to browse the catalog, or search a focused command such as Display Brightness Settings directly in the launcher.",
                    "Select an item with the arrow keys or pointer. Read its destination and press Return or choose Open in System Settings.",
                    "Choose and change options yourself in macOS. Commandly does not change a setting or request a permission."
                ]),
                .paragraph("system-settings.display", "Display, Brightness, Color Profile, Orientation, Resolution and Scaling all open the same Displays page. The destination is stated on every command. Available controls depend on the connected display and Mac; no fine-grained control is promised."),
                .shortcuts("system-settings.keys", [
                    DocumentationShortcut(id: "system-settings.arrows", title: "Select a setting", keys: ["↑", "↓"]),
                    DocumentationShortcut(id: "system-settings.open", title: "Open selected settings", keys: ["Return"]),
                    DocumentationShortcut(id: "system-settings.actions", title: "Open actions", keys: ["⌘", "K"]),
                    DocumentationShortcut(id: "system-settings.escape", title: "Cancel pending navigation, clear search, or go back", keys: ["Esc"])
                ])
            ]), DocumentationSection(id: "system-settings.recovery", title: "Availability and Privacy", blocks: [
                .paragraph("system-settings.fallback", "If a destination is unavailable or its handoff fails, Commandly opens System Settings and tells you to choose the page in the sidebar or search. If the application also fails to open, a recoverable message lets you retry or use the Apple menu."),
                .paragraph("system-settings.scope", "The catalog contains fixed macOS destinations. Labels are English and pages depend on the installed macOS version. A successful navigation request does not verify which page macOS ultimately displayed."),
                .paragraph("system-settings.privacy", "Search uses static catalog text. Opening reads bounded Apple application metadata and dispatches a fixed local settings URL to the built-in app. No settings values, files from user folders, network service, private API, AppleScript or shell command are used. Cancellation suppresses pending work and stale feedback; a request already handed to macOS cannot be withdrawn.")
            ])], keywords: ["macos", "preferences", "display", "brightness", "color profile", "rotation", "resolution", "scale", "settings"])
    }
}
