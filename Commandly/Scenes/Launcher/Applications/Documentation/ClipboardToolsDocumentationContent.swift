import Foundation

/// Authored documentation for the Clipboard Tools application.
extension RegisteredApplicationDocumentation {
    static let clipboardTools = LauncherApplicationDocumentation(
        category: .productivity,
        overview: """
        Flatten copied formatting, strip tracking parameters from a copied link, and empty the \
        clipboard on demand or automatically. Clearing the clipboard never deletes entries you \
        already saved in Clipboard History.
        """,
        sections: [
            DocumentationSection(
                id: "clipboard.tools.actions",
                title: "Three Clipboard Actions",
                blocks: [
                    .steps("clipboard.tools.steps", [
                        "Copy something as usual.",
                        "Run Clipboard to Plain Text to drop fonts, colors, and links, then paste normally.",
                        "Run Clean Copied Link to remove tracking parameters while the destination stays the same.",
                        "Run Clear Clipboard to empty it immediately.",
                        "Assign any of these a global shortcut in Settings → Applications."
                    ]),
                    .callout("clipboard.tools.paste-note", DocumentationCallout(
                        kind: .limitation,
                        title: "Plain text prepares the clipboard",
                        text: """
                        Commandly is sandboxed and does not press keys in other applications, so \
                        this action rewrites the clipboard rather than pasting for you. Paste \
                        normally afterwards and the result is unformatted.
                        """
                    ))
                ]
            ),
            DocumentationSection(
                id: "clipboard.tools.auto",
                title: "Automatic Clearing",
                blocks: [
                    .bullets("clipboard.tools.auto.bullets", [
                        "Clear after a period of inactivity following a copy.",
                        "Clear when the Mac sleeps, the display sleeps, or the screen locks.",
                        "Every trigger is off by default and each one is separate.",
                        "Automatic clearing empties the system clipboard only; saved Clipboard History entries are untouched.",
                        "Turn on automatic link cleaning to strip tracking from every copied link."
                    ])
                ]
            )
        ],
        keywords: [
            "clipboard", "plain text", "paste", "formatting", "clean url", "tracking",
            "utm", "clear clipboard", "privacy", "auto clear"
        ]
    )
}
