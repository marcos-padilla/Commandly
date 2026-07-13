enum FirstRunDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.first-run",
        title: "First Run & Setup",
        subtitle: "Understand every step of Commandly's initial setup.",
        systemImage: "checklist",
        category: .gettingStarted,
        order: 5,
        documentation: LauncherApplicationDocumentation(
            category: .gettingStarted,
            overview: "Commandly shows a five-step setup the first time it runs. You can move backward before finishing, skip every optional permission, and change the saved preferences later in Settings.",
            sections: [
                DocumentationSection(
                    id: "first-run-flow",
                    title: "The five setup steps",
                    blocks: [
                        .steps("first-run-flow-steps", [
                            "Welcome introduces Commandly as a private, keyboard-first launcher. Choose Start Setup to continue.",
                            "Features previews the launcher, unified search, Clipboard History, Quicklinks, snippets, and Window Layouts. Scroll horizontally to review every card.",
                            "Preferences lets you turn Open at Login on or off and save whether you prefer Commandly's future emoji picker. The emoji-picker preference is remembered, but it does not replace the current Emoji Search application.",
                            "Permissions lets you review Calendar and Contacts, selected Files and Folders, and Accessibility. Grant only the access you want, or choose Continue without granting anything.",
                            "Ready teaches Option–Space. Press Option–Space to confirm the shortcut, or choose Open Commandly to finish without performing the shortcut exercise."
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "first-run-preferences",
                    title: "Saved setup choices",
                    blocks: [
                        .bullets("first-run-preferences-list", [
                            "Open at Login uses macOS's native login-item service. If macOS requires approval, Commandly points you to System Settings → General → Login Items.",
                            "The emoji-picker choice is a local preference for a future picker; the current Emoji Search application remains unchanged.",
                            "Confirming Option–Space records that you completed the shortcut exercise. Option–Space is the built-in system-wide launcher hotkey either way.",
                            "Finishing setup stores a local completion flag so the setup window does not reopen on every launch."
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "first-run-permissions",
                    title: "Permissions are optional",
                    blocks: [
                        .paragraph(
                            "first-run-permissions-summary",
                            "Choose Grant Access only when you want the described benefit. A denial or skipped row does not block setup or unrelated features. Calendar and Contacts are reserved for future schedule and people experiences and are not currently surfaced by a Commandly application."
                        ),
                        .callout(
                            "first-run-permissions-later",
                            DocumentationCallout(
                                kind: .permission,
                                title: "Review supported access later",
                                text: "Open Settings → Permissions to review Calendar, Contacts, selected folder access, and Accessibility. Feature-specific prompts such as Finder Automation are handled when that feature is used."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "first-run-navigation",
                    title: "Move through setup",
                    blocks: [
                        .bullets("first-run-navigation-list", [
                            "Choose Back to revisit an earlier step before setup finishes.",
                            "Choose Continue to keep the current choices and advance. Permissions do not need to be granted before Continue becomes available.",
                            "On the final step, either Option–Space or Open Commandly completes setup after the short success animation."
                        ]),
                    ]
                ),
            ],
            keywords: [
                "first run", "setup", "onboarding", "welcome", "features", "preferences",
                "permissions", "Open at Login", "Option Space", "Grant Access", "Continue",
            ]
        )
    )
}
