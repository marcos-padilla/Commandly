enum SettingsDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.settings",
        title: "Settings & Application Configuration",
        subtitle: "Control startup, appearance, registered apps, aliases, hotkeys, and permissions.",
        systemImage: "gearshape",
        category: .settingsAndPrivacy,
        order: 300,
        documentation: LauncherApplicationDocumentation(
            category: .settingsAndPrivacy,
            overview: "Settings is Commandly’s control center for everyday preferences and every registered Commandly application. Open it from the launcher’s bottom-left Commandly menu or with Command–Comma.",
            sections: [
                DocumentationSection(
                    id: "settings-open",
                    title: "Open Settings",
                    blocks: [
                        .shortcuts("settings-open-shortcuts", [
                            DocumentationShortcut(
                                id: "settings-shortcut-open",
                                title: "Open Settings",
                                keys: ["⌘", ","]
                            ),
                        ]),
                        .bullets("settings-open-methods", [
                            "Choose Settings… from the Commandly icon at the bottom-left of the launcher.",
                            "Choose Settings… from Commandly’s menu bar menu.",
                            "Search for and run Open Settings in the launcher.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "settings-general",
                    title: "General",
                    blocks: [
                        .bullets("settings-general-options", [
                            "Open at Login registers or removes Commandly as a native login item. macOS can require approval in System Settings → General → Login Items.",
                            "The system-wide launcher hotkey is Option–Space.",
                            "Menu Bar Icon shows or hides Commandly’s status item. If you hide it, press Option–Space, open Settings, and turn Menu Bar Icon back on; relaunching preserves the saved hidden state.",
                            "View Mode switches between Comfortable and Compact layout density.",
                            "Text Size switches between Default and Larger text throughout Commandly surfaces.",
                            "Appearance follows System or forces Light or Dark appearance.",
                            "Emoji Picker Preference is saved for a future picker and does not claim to change the current Emoji Search application.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "settings-applications-overview",
                    title: "Applications",
                    blocks: [
                        .paragraph(
                            "settings-applications-summary",
                            "The Applications pane is generated from the launcher application registry. Search by name or alias, filter by registered item type, expand groups, and select an application to inspect its availability and declared configuration."
                        ),
                        .bullets("settings-applications-columns", [
                            "Name shows the registered hierarchy and icon.",
                            "Type identifies a Group, AI Extension, Extension, Command, or Application.",
                            "Alias adds a custom search keyword for a non-group item.",
                            "Shortcut records an optional global hotkey for a non-group item.",
                            "Enabled controls the selected node; disabling a group also makes its descendants effectively unavailable.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "settings-aliases",
                    title: "Create an alias",
                    blocks: [
                        .steps("settings-aliases-steps", [
                            "Open Settings → Applications.",
                            "Find the registered Commandly application you want to rename for search.",
                            "Enter a short word or phrase in its Alias field and press Return, or click elsewhere to commit it.",
                            "Open the launcher and type the alias; it is added to that application’s search keywords.",
                        ]),
                        .callout(
                            "settings-aliases-scope",
                            DocumentationCallout(
                                kind: .tip,
                                title: "Aliases do not rename apps",
                                text: "The application’s title remains unchanged. An alias is an extra local discovery keyword."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "settings-global-hotkeys",
                    title: "Assign a global application hotkey",
                    blocks: [
                        .steps("settings-global-hotkeys-steps", [
                            "Open Settings → Applications and find a non-group item.",
                            "Choose its Shortcut recorder, then press the key combination you want.",
                            "Use the clear control in the recorder to remove the assignment.",
                            "If Commandly reports a duplicate or reserved shortcut, choose another combination.",
                        ]),
                        .bullets("settings-global-hotkeys-rules", [
                            "Application shortcuts use native Carbon hot keys and do not require Accessibility permission.",
                            "Duplicate shortcuts are not registered.",
                            "Shortcuts reserved by Commandly, macOS, or another application are not registered.",
                            "A shortcut for a disabled application—or a descendant of a disabled group—is not active.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "settings-app-configuration",
                    title: "Per-application configuration",
                    blocks: [
                        .paragraph(
                            "settings-app-configuration-summary",
                            "Select a registered application to see configuration fields it declares. Commandly currently supports non-secret text, toggle, integer, decimal, and selection fields. The app receives the resolved values when it launches."
                        ),
                        .bullets("settings-app-configuration-actions", [
                            "Turn Enabled off to hide the app from discovery and disable its global shortcut.",
                            "Change any declared configuration value in the inspector.",
                            "Choose Restore Defaults to remove alias, hotkey, enablement, and configuration overrides for the selected app.",
                        ]),
                        .callout(
                            "settings-app-configuration-secrets",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Non-secret settings only",
                                text: "Application configuration is stored in UserDefaults. Passwords, tokens, and credentials must not be placed in these fields."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "settings-permissions-about",
                    title: "Permissions and About",
                    blocks: [
                        .bullets("settings-permissions-about-list", [
                            "Permissions shows current Calendar, Contacts, Files and Folders, and Accessibility states and provides the appropriate request or System Settings recovery action.",
                            "About shows the Commandly version, build, bundle identifier, and environment metadata.",
                        ]),
                    ]
                ),
            ],
            keywords: [
                "settings", "preferences", "alias", "global shortcut", "hotkey", "application registry",
                "enable", "disable", "configuration", "restore defaults", "Open at Login", "appearance",
                "compact", "larger text", "menu bar",
            ]
        )
    )
}
