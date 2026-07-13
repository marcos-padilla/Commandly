import Foundation

extension RegisteredApplicationDocumentation {
    static let fileSearch = LauncherApplicationDocumentation(
        category: .coreFeatures,
        overview: "Search user-authorized folders through Commandly's private local index, preview supported files, and run native open, Finder, sharing, clipboard, and file-management actions.",
        sections: [
            DocumentationSection(
                id: "files.access",
                title: "Choose Search Locations",
                blocks: [
                    .steps("files.access.steps", [
                        "Open Search Files. If no folders are authorized, choose Open Settings.",
                        "In Settings → Permissions, use Manage Folders to select the locations Commandly may search.",
                        "Return to Search Files. Commandly builds its local index and refreshes results as indexed information becomes available."
                    ]),
                    .callout(
                        "files.access.permission",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Files and Folders access",
                            text: "Commandly can search only folders you explicitly select. Access is read-write because move, copy, duplicate, shortcut, and Trash actions need it, but every mutation requires an explicit action."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "files.search",
                title: "Search, Filter, and Preview",
                blocks: [
                    .bullets("files.search.fields", [
                        "Search matches names, paths, folders, Finder tags, metadata, supported document text, PDF text, and bounded on-device image OCR.",
                        "An empty query shows Recent Files using available last-used metadata.",
                        "Filters cover All Files, Folders, Documents, Images, Audio, Video, Archives, and Source Code.",
                        "CSV files receive a bounded native table preview. Other supported formats use a cancellable static Quick Look representation with file metadata."
                    ]),
                    .shortcuts("files.search.shortcuts", [
                        DocumentationShortcut(id: "files.search.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "files.search.open", title: "Open in the default app", keys: ["Return"]),
                        DocumentationShortcut(id: "files.search.actions", title: "Open file actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(
                            id: "files.search.escape",
                            title: "Close an action page, clear search, or go back",
                            keys: ["Esc"]
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "files.actions",
                title: "File Actions",
                blocks: [
                    .paragraph(
                        "files.actions.open",
                        "Press Command-K on a selected result. The action panel is searchable and can open nested choices for applications, share services, and destination folders."
                    ),
                    .bullets("files.actions.items", [
                        "Open, Open With, Show Info in Finder, Show in Finder, Open Enclosing Folder, and show or hide details.",
                        "Use a native macOS sharing service.",
                        "Move To, Copy To, Duplicate, or Move to Trash.",
                        "Create a Commandly .webloc shortcut in a chosen folder.",
                        "Copy the file itself, its name, or its full path."
                    ]),
                    .callout(
                        "files.actions.automation",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Finder automation",
                            text: "Show Info in Finder can trigger macOS Automation permission the first time it is used. Other Finder and file actions report failures without claiming a change succeeded."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "files.settings",
                title: "Defaults and Privacy",
                blocks: [
                    .bullets("files.settings.options", [
                        "Default category chooses the file type selected when Search Files opens.",
                        "Show file details controls whether the metadata preview is visible initially."
                    ]),
                    .callout(
                        "files.settings.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Local index",
                            text: "Queries, filenames, paths, indexed contents, previews, and metadata are never logged or uploaded. The derived SQLite index remains in Commandly's local Application Support container and is not synced."
                        )
                    ),
                    .callout(
                        "files.settings.limits",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Coverage limits",
                            text: "Hidden files are excluded. Unsupported or encrypted formats may expose metadata without searchable contents, and external volumes must be selected explicitly and remain mounted."
                        )
                    )
                ]
            )
        ],
        keywords: ["Finder", "index", "FTS", "OCR", "PDF", "Quick Look", "open with", "share", "copy", "move", "duplicate", "trash"]
    )
}

