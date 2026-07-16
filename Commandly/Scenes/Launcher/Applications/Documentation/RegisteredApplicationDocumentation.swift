import Foundation

/// Authored help articles contributed by Commandly's registered applications.
///
/// Application definitions reference these values directly so registration and documentation stay
/// in lockstep. Content describes only behavior implemented by the owning application.
enum RegisteredApplicationDocumentation {
    static let openSettings = LauncherApplicationDocumentation(
        category: .settingsAndPrivacy,
        overview: "Open Commandly Settings to adjust the app, review permissions, configure registered applications, or check version information.",
        sections: [
            DocumentationSection(
                id: "settings.open",
                title: "Open Settings",
                blocks: [
                    .steps("settings.open.steps", [
                        "Open Commandly and search for Open Settings.",
                        "Select Open Settings and press Return.",
                        "Choose General, AI, Applications, Permissions, or About in the sidebar."
                    ]),
                    .shortcuts("settings.open.shortcuts", [
                        DocumentationShortcut(
                            id: "settings.open.return",
                            title: "Open Settings",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "settings.open.command-comma",
                            title: "Open Settings from the launcher gear menu",
                            keys: ["⌘", ","]
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "settings.panes",
                title: "What You Can Configure",
                blocks: [
                    .bullets("settings.panes.items", [
                        "General controls Commandly's appearance and everyday launcher preferences.",
                        "AI connects BYOK providers, validates credentials or local endpoints, and selects the active model.",
                        "Applications manages registered Commandly applications, including aliases, enablement, global hotkeys, and each application's non-secret settings.",
                        "Permissions explains each optional macOS capability and provides recovery links when access is unavailable.",
                        "About shows Commandly's version, build, and project information."
                    ]),
                    .callout(
                        "settings.panes.scope",
                        DocumentationCallout(
                            kind: .important,
                            title: "Registered applications only",
                            text: "The Applications pane configures features built into Commandly. Actions for arbitrary installed macOS apps live in the launcher's application action panel."
                        )
                    )
                ]
            )
        ],
        keywords: ["preferences", "general", "applications", "permissions", "about", "alias", "hotkey"]
    )

    static let clipboardHistory = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Browse recent text, image, and file clipboard entries; search their locally derived content; copy an item again; or create, edit, append, and remove text entries.",
        sections: [
            DocumentationSection(
                id: "clipboard.browse",
                title: "Browse and Find Entries",
                blocks: [
                    .paragraph(
                        "clipboard.browse.summary",
                        "Entries are grouped by day. Use All Types, Text, Image, or File to narrow the list, then search previews, captured text, locally extracted text, classification labels, and source application names."
                    ),
                    .steps("clipboard.browse.steps", [
                        "Open Clipboard History from the launcher.",
                        "Choose a type filter or start typing to narrow the history.",
                        "Use the arrow keys or pointer to select an entry.",
                        "Press Return to make that entry the current clipboard value."
                    ]),
                    .shortcuts("clipboard.browse.shortcuts", [
                        DocumentationShortcut(id: "clipboard.browse.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "clipboard.browse.copy", title: "Copy selected entry", keys: ["Return"]),
                        DocumentationShortcut(id: "clipboard.browse.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(
                            id: "clipboard.browse.escape",
                            title: "Cancel the editor, clear search, or go back",
                            keys: ["Esc"],
                            detail: "Escape handles the closest active state first."
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "clipboard.write",
                title: "Create, Edit, and Append Text",
                blocks: [
                    .bullets("clipboard.write.actions", [
                        "New Text Entry saves reusable text in the current history and makes it the current clipboard value.",
                        "Edit Text Entry updates the selected text entry and makes the edited value current. Image and file entries are not editable.",
                        "Append to Clipboard adds text after the current string clipboard. Commandly inserts a newline when one is needed, then records the combined value."
                    ]),
                    .steps("clipboard.write.steps", [
                        "Press Command-K and choose New Text Entry, Edit Text Entry, or Append to Clipboard.",
                        "Enter the text in the editor.",
                        "Press Command-Return or choose Save. Escape cancels without changing the clipboard."
                    ]),
                    .shortcuts("clipboard.write.shortcuts", [
                        DocumentationShortcut(id: "clipboard.write.save", title: "Save clipboard text", keys: ["⌘", "Return"]),
                        DocumentationShortcut(id: "clipboard.write.cancel", title: "Cancel editing", keys: ["Esc"])
                    ]),
                    .examples("clipboard.write.examples", [
                        DocumentationExample(
                            id: "clipboard.write.append-example",
                            input: "Current clipboard: First line\nAppend: Second line",
                            output: "First line\nSecond line"
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "clipboard.manage",
                title: "Manage History",
                blocks: [
                    .bullets("clipboard.manage.actions", [
                        "Delete removes the selected entry.",
                        "Clear History removes every entry in the current in-memory history.",
                        "The Default filter setting chooses which content type is selected whenever this application opens."
                    ]),
                    .callout(
                        "clipboard.manage.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Private and in memory",
                            text: "Clipboard entries, OCR text, readable file text, and classification labels remain in memory for the current Commandly process. They are not logged, uploaded, or persisted between launches."
                        )
                    ),
                    .callout(
                        "clipboard.manage.files",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Protected files",
                            text: "The macOS sandbox can prevent reading some copied file URLs. Those entries can still be found by filename even when content extraction is unavailable."
                        )
                    )
                ]
            )
        ],
        keywords: ["paste", "copy", "history", "append", "edit", "OCR", "image", "file", "clear"]
    )
}
