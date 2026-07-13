enum InstalledApplicationsDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.installed-applications",
        title: "Installed Applications",
        subtitle: "Launch Mac apps, reveal their bundles, manage ranking, and review an uninstall.",
        systemImage: "app.dashed",
        category: .coreFeatures,
        order: 100,
        documentation: LauncherApplicationDocumentation(
            category: .coreFeatures,
            overview: "Commandly discovers application bundles in the standard system, local, and user Applications folders. Search by app name, press Return to launch, or open Actions for native Finder and management workflows.",
            sections: [
                DocumentationSection(
                    id: "installed-apps-find-open",
                    title: "Find and open an app",
                    blocks: [
                        .steps("installed-apps-find-open-steps", [
                            "Open Commandly and type part of an installed application’s name.",
                            "Choose the app in the Applications section. Commandly shows the icon from its application bundle.",
                            "Press Return to open the app through macOS.",
                        ]),
                        .paragraph(
                            "installed-apps-ranking-summary",
                            "Commandly keeps a local open count and last-opened time to improve application ranking. Favorites also receive their own visual status. Reset Ranking removes the learned ranking for one app."
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "installed-apps-open-actions",
                    title: "Open application actions",
                    blocks: [
                        .bullets("installed-apps-open-actions-methods", [
                            "Select an application and press Command–K.",
                            "Click Actions in the launcher footer while an installed application is selected.",
                            "Right-click an installed application row.",
                            "Type in the actions panel to filter actions; pressing Return runs the first visible match.",
                        ]),
                        .shortcuts("installed-apps-primary-shortcuts", [
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-open",
                                title: "Open Application",
                                keys: ["↩"]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-reveal",
                                title: "Show in Finder",
                                keys: ["⌘", "↩"]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-info",
                                title: "Show Info in Finder",
                                keys: ["⌘", "I"],
                                detail: "Finder Automation access is requested only when this action is used."
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-package",
                                title: "Show Package Contents",
                                keys: ["⌥", "⌘", "I"]
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "installed-apps-copy-favorite",
                    title: "Favorites and clipboard actions",
                    blocks: [
                        .shortcuts("installed-apps-copy-favorite-shortcuts", [
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-favorite",
                                title: "Add to or remove from Favorites",
                                keys: ["⇧", "⌘", "F"]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-copy-name",
                                title: "Copy Name",
                                keys: ["⌘", "."]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-copy-path",
                                title: "Copy Path",
                                keys: ["⇧", "⌘", "."]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-copy-bundle-id",
                                title: "Copy Bundle Identifier",
                                keys: ["⇧", "⌘", "C"]
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "installed-apps-management",
                    title: "Manage an installed app",
                    blocks: [
                        .bullets("installed-apps-management-list", [
                            "Enable Auto Quit to ask the app to terminate after it has remained in the background for five minutes. Commandly checks periodically and never force-quits through this feature.",
                            "Disable Application to hide the app from the empty-query list without uninstalling it. Search for the disabled app by name, open Actions, and choose Enable Application to restore it.",
                            "Reset Ranking clears that app’s local open count and last-opened value.",
                        ]),
                        .shortcuts("installed-apps-management-shortcuts", [
                            DocumentationShortcut(
                                id: "installed-apps-shortcut-disable",
                                title: "Disable or enable Application",
                                keys: ["⌃", "⇧", "⌘", "D"]
                            ),
                        ]),
                        .callout(
                            "installed-apps-auto-quit-callout",
                            DocumentationCallout(
                                kind: .important,
                                title: "Auto Quit is app-specific",
                                text: "The idle timer starts when Commandly first observes an enabled app in the background. A frontmost app is never terminated by Auto Quit."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "installed-apps-uninstall",
                    title: "Review an uninstall",
                    blocks: [
                        .steps("installed-apps-uninstall-steps", [
                            "Choose Uninstall Application… in the selected app’s Actions panel.",
                            "Wait while Commandly discovers the app bundle and related support files associated with its bundle identifier.",
                            "Filter by file or folder name, sort by path, name, or size, and deselect anything you want to keep.",
                            "Review the selected file count and total size.",
                            "Press Return or choose Uninstall Application to move only the selected items to the Trash.",
                        ]),
                        .shortcuts("installed-apps-uninstall-shortcuts", [
                            DocumentationShortcut(
                                id: "installed-apps-uninstall-confirm",
                                title: "Confirm selected uninstall items",
                                keys: ["↩"]
                            ),
                            DocumentationShortcut(
                                id: "installed-apps-uninstall-cancel",
                                title: "Cancel and go back",
                                keys: ["Esc"]
                            ),
                        ]),
                        .callout(
                            "installed-apps-uninstall-safety",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Review before removing",
                                text: "Protected or sandboxed paths can fail, and related-file discovery cannot guarantee that every vendor-specific file is found. Commandly reports partial failures instead of claiming a complete wipe. Items are moved to the Trash, not permanently erased."
                            )
                        ),
                    ]
                ),
            ],
            keywords: [
                "launch apps", "Applications", "Finder", "Get Info", "package contents", "favorite",
                "copy bundle identifier", "copy app path", "auto quit", "disable app", "ranking",
                "uninstall", "Trash", "Command Return", "Command I",
            ]
        )
    )
}
