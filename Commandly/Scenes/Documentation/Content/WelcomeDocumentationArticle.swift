enum WelcomeDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.welcome",
        title: "Welcome to Commandly",
        subtitle: "The quickest path from an idea to an action on your Mac.",
        systemImage: "sparkles",
        category: .gettingStarted,
        order: 0,
        documentation: LauncherApplicationDocumentation(
            category: .gettingStarted,
            overview: "Commandly is a native, keyboard-first macOS launcher. Open it from anywhere, type what you want, and run the selected result without reaching for another window.",
            sections: [
                DocumentationSection(
                    id: "welcome-first-action",
                    title: "Your first action",
                    blocks: [
                        .steps("welcome-first-action-steps", [
                            "Press Option–Space to show Commandly from anywhere.",
                            "Start typing the name of an installed Mac application, a Commandly application, or a calculation.",
                            "Use the Up and Down Arrow keys to choose a result.",
                            "Press Return to run the selected result.",
                            "Press Escape to clear the current query, go back, or hide the launcher.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "welcome-essential-shortcuts",
                    title: "Essential shortcuts",
                    blocks: [
                        .shortcuts("welcome-essential-shortcuts-list", [
                            DocumentationShortcut(
                                id: "welcome-shortcut-open-launcher",
                                title: "Open Commandly",
                                keys: ["⌥", "Space"],
                                detail: "System-wide launcher hotkey."
                            ),
                            DocumentationShortcut(
                                id: "welcome-shortcut-open-launcher-menu",
                                title: "Open Commandly from the menu bar menu",
                                keys: ["⌥", "⌘", "O"],
                                detail: "Menu item keyboard equivalent."
                            ),
                            DocumentationShortcut(
                                id: "welcome-shortcut-open-actions",
                                title: "Open Actions",
                                keys: ["⌘", "K"],
                                detail: "Shows actions for the selected installed app or active Commandly application."
                            ),
                            DocumentationShortcut(
                                id: "welcome-shortcut-open-documentation",
                                title: "Open Documentation",
                                keys: ["⌘", "?"],
                                detail: "Also available from the Settings gear at the bottom-right of the launcher."
                            ),
                            DocumentationShortcut(
                                id: "welcome-shortcut-open-settings",
                                title: "Open Settings",
                                keys: ["⌘", ","],
                                detail: "Configure appearance, registered applications, and permissions."
                            ),
                            DocumentationShortcut(
                                id: "welcome-shortcut-quit",
                                title: "Quit Commandly",
                                keys: ["⌘", "Q"]
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "welcome-ways-to-open",
                    title: "Other ways to open Commandly",
                    blocks: [
                        .bullets("welcome-ways-to-open-list", [
                            "Choose Open Commandly from the menu bar icon.",
                            "Press Option–Command–O while the Commandly menu bar menu is open.",
                            "Launch Commandly from Finder or another application launcher; the menu bar utility remains available while Commandly is running.",
                            "Turn on Open at Login in Settings to make Commandly available after sign-in.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "welcome-current-scope",
                    title: "What to expect",
                    blocks: [
                        .paragraph(
                            "welcome-current-scope-summary",
                            "Commandly searches registered Commandly applications and installed macOS applications, evaluates calculator-shaped input, and exposes native utilities through focused application screens. Each feature article in this documentation describes what is currently implemented."
                        ),
                        .callout(
                            "welcome-current-scope-honesty",
                            DocumentationCallout(
                                kind: .important,
                                title: "Implemented features only",
                                text: "Commandly does not present planned placeholders as working features. If a capability is not described as available here, do not assume it is implemented."
                            )
                        ),
                    ]
                ),
            ],
            keywords: [
                "getting started", "open launcher", "Option Space", "keyboard", "quick start",
                "menu bar", "shortcut", "Command K", "Settings", "Documentation",
            ]
        )
    )
}
