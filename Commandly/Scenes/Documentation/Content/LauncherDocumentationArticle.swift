enum LauncherDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.launcher",
        title: "Launcher Search & Navigation",
        subtitle: "Find commands and apps, complete suggestions, and move without leaving the keyboard.",
        systemImage: "command",
        category: .gettingStarted,
        order: 10,
        documentation: LauncherApplicationDocumentation(
            category: .gettingStarted,
            overview: "The launcher is Commandly’s keyboard-first home. Its single search field combines Commandly applications, installed Mac applications, and calculator results while keeping the best current selection ready to run.",
            sections: [
                DocumentationSection(
                    id: "launcher-search",
                    title: "Search",
                    blocks: [
                        .bullets("launcher-search-behavior", [
                            "Type a feature name such as Clipboard History, File Search, or Timers & Focus.",
                            "Type the name of an installed application to open it with its real app icon.",
                            "Type a calculator-shaped query; a Calculator card appears above normal results without replacing them.",
                            "Registered application aliases are searchable after you add them in Settings.",
                            "Disabled registered Commandly applications are excluded from discovery. Disabled installed Mac applications are hidden from the empty-query list but remain searchable by name so you can manage or re-enable them.",
                            "Search work is cancelled and restarted as you type so an older result cannot overwrite a newer query.",
                        ]),
                        .callout(
                            "launcher-search-history-callout",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "No search-history log",
                                text: "Commandly does not persist or log your full launcher search history."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "launcher-keyboard-navigation",
                    title: "Keyboard navigation",
                    blocks: [
                        .shortcuts("launcher-keyboard-shortcuts", [
                            DocumentationShortcut(
                                id: "launcher-shortcut-next",
                                title: "Select next result",
                                keys: ["↓"]
                            ),
                            DocumentationShortcut(
                                id: "launcher-shortcut-previous",
                                title: "Select previous result",
                                keys: ["↑"]
                            ),
                            DocumentationShortcut(
                                id: "launcher-shortcut-complete",
                                title: "Accept autocomplete",
                                keys: ["Tab"],
                                detail: "Available when a ghost completion or calculator correction is shown."
                            ),
                            DocumentationShortcut(
                                id: "launcher-shortcut-confirm",
                                title: "Run selected result",
                                keys: ["↩"],
                                detail: "For a selected calculator card, copies the answer and keeps Commandly visible."
                            ),
                            DocumentationShortcut(
                                id: "launcher-shortcut-actions",
                                title: "Open Actions",
                                keys: ["⌘", "K"],
                                detail: "Works for a selected installed app and for Commandly application surfaces with actions."
                            ),
                            DocumentationShortcut(
                                id: "launcher-shortcut-escape",
                                title: "Clear, close, go back, or hide",
                                keys: ["Esc"],
                                detail: "Escape handles the innermost visible layer first."
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "launcher-escape-order",
                    title: "How Escape works",
                    blocks: [
                        .steps("launcher-escape-order-steps", [
                            "If an actions panel or menu is open, Escape closes it.",
                            "Inside a Commandly application, the application first gets a chance to clear its search or close its own panel.",
                            "If nothing inside the application consumes Escape, Commandly returns to launcher home.",
                            "At home, Escape clears a nonempty search query.",
                            "With an empty home query, Escape hides the launcher.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "launcher-autocomplete",
                    title: "Autocomplete and calculator previews",
                    blocks: [
                        .paragraph(
                            "launcher-autocomplete-summary",
                            "A muted ghost suffix can complete the best matching result or a recoverable calculator expression. Calculator completion can balance parentheses, finish a trailing operator, infer a conventional unit target, complete a function name, or offer a bounded typo correction."
                        ),
                        .examples("launcher-autocomplete-examples", [
                            DocumentationExample(
                                id: "launcher-autocomplete-sqrt",
                                input: "sqrt(5",
                                output: "sqrt(5)",
                                detail: "Press Tab to accept the closing parenthesis."
                            ),
                            DocumentationExample(
                                id: "launcher-autocomplete-operator",
                                input: "2 +",
                                detail: "Shows a recoverable live preview and an offered completion."
                            ),
                            DocumentationExample(
                                id: "launcher-autocomplete-unit",
                                input: "5 mph",
                                output: "5 mph in km/h",
                                detail: "The conventional target is recomputed if you continue typing another target."
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "launcher-pointer",
                    title: "Pointer and window behavior",
                    blocks: [
                        .bullets("launcher-pointer-behavior", [
                            "Click a result to select and run it.",
                            "Right-click an installed application row to open its searchable actions panel.",
                            "While the results list is scrolling, hover does not steal the keyboard selection.",
                            "Clicking outside Commandly dismisses the launcher. Keyboard-only Space changes keep it available in the current Space.",
                            "The launcher window can be moved to a convenient position; macOS preserves normal window placement behavior.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "launcher-app-menu",
                    title: "Settings menu",
                    blocks: [
                        .paragraph(
                            "launcher-app-menu-summary",
                            "Click the Settings gear at the bottom-right of launcher home to open the utility menu. From there you can open Documentation, open Settings, or quit Commandly."
                        ),
                        .shortcuts("launcher-app-menu-shortcuts", [
                            DocumentationShortcut(
                                id: "launcher-app-menu-documentation",
                                title: "Documentation",
                                keys: ["⌘", "?"]
                            ),
                            DocumentationShortcut(
                                id: "launcher-app-menu-settings",
                                title: "Settings",
                                keys: ["⌘", ","]
                            ),
                            DocumentationShortcut(
                                id: "launcher-app-menu-quit",
                                title: "Quit Commandly",
                                keys: ["⌘", "Q"]
                            ),
                        ]),
                    ]
                ),
            ],
            keywords: [
                "search", "launcher", "navigation", "arrow keys", "autocomplete", "Tab",
                "Return", "Escape", "Actions", "Command K", "Settings menu", "footer",
            ]
        )
    )
}
