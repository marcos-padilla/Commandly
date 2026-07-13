import Foundation

extension RegisteredApplicationDocumentation {
    static let systemActivity = LauncherApplicationDocumentation(
        category: .system,
        overview: "Inspect aggregate resource use for this Mac and manage regular running GUI applications with explicit switch, quit, force-quit, and protected bulk-quit actions.",
        sections: [
            DocumentationSection(
                id: "activity.resources",
                title: "Resources",
                blocks: [
                    .bullets("activity.resources.metrics", [
                        "Aggregate CPU use.",
                        "Used and total physical memory.",
                        "Used and total capacity for the filesystem containing your home directory.",
                        "System uptime and current thermal state."
                    ]),
                    .paragraph(
                        "activity.resources.refresh",
                        "Commandly refreshes the snapshot automatically every three seconds while the application is open. Press Return or use Refresh System Activity for an immediate sample."
                    ),
                    .callout(
                        "activity.resources.scope",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Aggregate monitor",
                            text: "This is not a full Unix process inspector. It does not show GPU, network, battery, daemon, per-process CPU or memory, ports, or arbitrary signals."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "activity.applications",
                title: "Running Applications",
                blocks: [
                    .steps("activity.applications.steps", [
                        "Switch to the Applications mode.",
                        "Search by application name, bundle identifier, or process identifier.",
                        "Select a regular GUI application and press Return to switch to it.",
                        "Press Command-K for Refresh, Switch, Quit, Force Quit, or Quit All Other Applications."
                    ]),
                    .bullets("activity.applications.actions", [
                        "Quit requests graceful termination.",
                        "Force Quit shows a destructive confirmation because unsaved work can be lost.",
                        "Quit All Other Applications shows a confirmation and gracefully requests termination for every eligible GUI app."
                    ]),
                    .shortcuts("activity.applications.shortcuts", [
                        DocumentationShortcut(id: "activity.applications.arrows", title: "Move application selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "activity.applications.primary", title: "Refresh resources, switch apps, or confirm", keys: ["Return"]),
                        DocumentationShortcut(id: "activity.applications.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "activity.applications.escape", title: "Cancel confirmation, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "activity.protection",
                title: "Termination Protection",
                blocks: [
                    .callout(
                        "activity.protection.rules",
                        DocumentationCallout(
                            kind: .important,
                            title: "Protected applications",
                            text: "Commandly, Finder, and the current frontmost application are excluded from termination. Switch away from a frontmost app before trying to quit it. Partial failures are reported rather than presented as complete success."
                        )
                    ),
                    .callout(
                        "activity.protection.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Native system data",
                            text: "System Activity reads aggregate host statistics and the public list of regular GUI applications through native macOS APIs. It does not require an account or upload the snapshot."
                        )
                    )
                ]
            )
        ],
        keywords: ["CPU", "memory", "storage", "uptime", "thermal", "running apps", "process", "quit", "force quit", "quit all"]
    )

    static let windowLayouts = LauncherApplicationDocumentation(
        category: .system,
        overview: "Resize and position the external window that was focused before Commandly opened, using 58 built-in arrangements or your own named normalized rectangles.",
        sections: [
            DocumentationSection(
                id: "layouts.presets",
                title: "Apply a Built-in Layout",
                blocks: [
                    .steps("layouts.presets.steps", [
                        "Focus the window you want to arrange, then open Commandly.",
                        "Open Window Layouts and browse or search the 58 Presets source.",
                        "Choose a Featured, Halves, Thirds, Quarters, or Grid preset.",
                        "Press Return to apply the rectangle to the previously focused external window."
                    ]),
                    .bullets("layouts.presets.catalog", [
                        "Featured includes Maximize and centered large or medium rectangles.",
                        "Halves and Thirds include horizontal, vertical, and two-thirds arrangements.",
                        "Quarters and Grid include corner quarters, 3×3 cells, wide and tall 3×3 spans, and 4×4 cells."
                    ]),
                    .shortcuts("layouts.presets.shortcuts", [
                        DocumentationShortcut(id: "layouts.presets.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "layouts.presets.apply", title: "Apply selected layout", keys: ["Return"]),
                        DocumentationShortcut(id: "layouts.presets.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "layouts.presets.escape", title: "Cancel editing, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "layouts.custom",
                title: "Create a Custom Layout",
                blocks: [
                    .steps("layouts.custom.steps", [
                        "Press Command-K and choose New Custom Layout.",
                        "Give the layout a name and enter x, y, width, and height values.",
                        "Keep every value within the screen: x and y start at the top-left, and x + width and y + height must not exceed 1.",
                        "Save the layout, switch to the Custom source, and press Return to apply it. Use the actions menu to delete a selected custom layout."
                    ]),
                    .examples("layouts.custom.examples", [
                        DocumentationExample(
                            id: "layouts.custom.centered",
                            input: "x 0.1, y 0.1, width 0.8, height 0.8",
                            output: "A centered rectangle using 80% of the visible screen width and height"
                        ),
                        DocumentationExample(
                            id: "layouts.custom.left-half",
                            input: "x 0, y 0, width 0.5, height 1",
                            output: "Left half of the visible screen"
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "layouts.permission",
                title: "Accessibility and Targeting",
                blocks: [
                    .callout(
                        "layouts.permission.contextual",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Requested when you apply",
                            text: "Window Layouts asks for macOS Accessibility only after you invoke Apply. If access is denied, Commandly explains the failure so you can enable it in System Settings → Privacy & Security → Accessibility."
                        )
                    ),
                    .callout(
                        "layouts.permission.scope",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "One focused window",
                            text: "A layout acts only on the focused window of the external app captured before Commandly opened. There are no multi-app workspace layouts, window sequences, or separate global shortcuts for individual rectangles."
                        )
                    )
                ]
            )
        ],
        keywords: ["resize", "tile", "58", "presets", "grid", "custom rectangle", "Accessibility", "active window"]
    )
}

