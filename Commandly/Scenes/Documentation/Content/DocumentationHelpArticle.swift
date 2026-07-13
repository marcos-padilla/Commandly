enum DocumentationHelpArticle {
    static let article = CoreDocumentationArticle(
        id: "core.documentation",
        title: "Using Documentation",
        subtitle: "Browse every registered feature and search for a workflow or shortcut.",
        systemImage: "book.closed",
        category: .gettingStarted,
        order: 20,
        documentation: LauncherApplicationDocumentation(
            category: .gettingStarted,
            overview: "Commandly Documentation is an in-app guide assembled from core articles and documentation supplied by every registered Commandly application.",
            sections: [
                DocumentationSection(
                    id: "documentation-open",
                    title: "Open Documentation",
                    blocks: [
                        .steps("documentation-open-steps", [
                            "Open Commandly with Option–Space.",
                            "Click the Commandly icon in the bottom-left corner.",
                            "Choose Documentation.",
                        ]),
                        .shortcuts("documentation-open-shortcut", [
                            DocumentationShortcut(
                                id: "documentation-shortcut-open",
                                title: "Open Documentation",
                                keys: ["⌘", "?"],
                                detail: "Available from Commandly’s app menu."
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "documentation-browse",
                    title: "Browse and search",
                    blocks: [
                        .bullets("documentation-browse-list", [
                            "Choose an article in the sidebar to read its overview, workflows, shortcuts, examples, and important notes.",
                            "Articles are grouped into Getting Started, Core Features, Productivity, System, Utilities, and Settings & Privacy.",
                            "Use documentation search to match article titles, summaries, section text, shortcuts, keywords, and examples.",
                            "Registered app articles include the app’s current enabled state and user-configured alias or global shortcut when available.",
                        ]),
                        .shortcuts("documentation-browse-shortcuts", [
                            DocumentationShortcut(
                                id: "documentation-shortcut-find",
                                title: "Focus documentation search",
                                keys: ["⌘", "F"]
                            ),
                            DocumentationShortcut(
                                id: "documentation-shortcut-previous-article",
                                title: "Select previous matching article",
                                keys: ["↑"],
                                detail: "Works while the documentation search field is focused."
                            ),
                            DocumentationShortcut(
                                id: "documentation-shortcut-next-article",
                                title: "Select next matching article",
                                keys: ["↓"],
                                detail: "Works while the documentation search field is focused."
                            ),
                            DocumentationShortcut(
                                id: "documentation-shortcut-clear-search",
                                title: "Clear documentation search",
                                keys: ["Esc"],
                                detail: "Available when the documentation query is not empty."
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "documentation-registration",
                    title: "Documentation stays with each app",
                    blocks: [
                        .paragraph(
                            "documentation-registration-summary",
                            "A Commandly application contributes structured documentation through the same definition used to register it. Once the app is registered, its article appears here automatically—without a separate screen-specific list or runtime Markdown parser."
                        ),
                        .callout(
                            "documentation-registration-disabled",
                            DocumentationCallout(
                                kind: .tip,
                                title: "Disabled apps remain documented",
                                text: "Disabling a registered app removes it from launcher discovery, but its documentation remains available so you can learn what it does and decide whether to re-enable it."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "documentation-accuracy",
                    title: "Accuracy and scope",
                    blocks: [
                        .bullets("documentation-accuracy-list", [
                            "Examples describe implemented behavior rather than planned capabilities.",
                            "Dynamic values such as live exchange rates, relative dates, aliases, shortcuts, and permission state can differ from the static examples shown here.",
                            "Permission, privacy, ambiguity, and safety limitations are included alongside the workflows they affect.",
                        ]),
                    ]
                ),
            ],
            keywords: [
                "help", "guide", "manual", "documentation search", "articles", "registered apps",
                "Command question mark",
            ]
        )
    )
}
