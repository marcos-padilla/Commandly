import Foundation

extension RegisteredApplicationDocumentation {
    static let calculatorHistory = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Review successful calculator results saved during the current Commandly session, search by expression or answer, and copy or remove individual entries.",
        sections: [
            DocumentationSection(
                id: "calculation-history.add",
                title: "Build the Current Session History",
                blocks: [
                    .steps("calculation-history.add.steps", [
                        "Enter a supported calculator expression in the main launcher.",
                        "Use a successful calculator result to add it to the current session history.",
                        "Open Calculation History to review the saved expression and formatted answer."
                    ]),
                    .callout(
                        "calculation-history.add.scope",
                        DocumentationCallout(
                            kind: .important,
                            title: "Successful results only",
                            text: "History is a bounded record of results you explicitly use. It is not a transcript of every query, incomplete expression, or error entered in the launcher."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "calculation-history.use",
                title: "Search and Use Results",
                blocks: [
                    .bullets("calculation-history.use.actions", [
                        "Search checks both the original expression and its formatted result.",
                        "Return copies the selected formatted result.",
                        "The actions menu can copy the original expression, delete the selected entry, or clear the entire calculation history."
                    ]),
                    .shortcuts("calculation-history.use.shortcuts", [
                        DocumentationShortcut(id: "calculation-history.use.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "calculation-history.use.copy", title: "Copy result", keys: ["Return"]),
                        DocumentationShortcut(id: "calculation-history.use.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "calculation-history.use.escape", title: "Clear search or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "calculation-history.privacy",
                title: "Storage and Privacy",
                blocks: [
                    .callout(
                        "calculation-history.privacy.session",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Session only",
                            text: "Calculation history stays in process and is discarded when Commandly quits. Expressions and results are not logged or synced, and copying occurs only after an explicit action."
                        )
                    )
                ]
            )
        ],
        keywords: ["calculator", "math", "answers", "copy expression", "session", "clear"]
    )

    static let downloads = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "See the newest visible files at the top level of Downloads, then open, reveal, or copy either the selected item or the newest download.",
        sections: [
            DocumentationSection(
                id: "downloads.browse",
                title: "Browse Recent Downloads",
                blocks: [
                    .paragraph(
                        "downloads.browse.summary",
                        "Recent Downloads scans visible regular files at the top level of your Downloads folder. It orders items by date added, then uses creation and modification dates as fallbacks."
                    ),
                    .bullets("downloads.browse.search", [
                        "Type to filter by filename or extension.",
                        "The default scan is bounded to 50 items.",
                        "Folders, hidden items, and nested files are not included."
                    ]),
                    .shortcuts("downloads.browse.shortcuts", [
                        DocumentationShortcut(id: "downloads.browse.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "downloads.browse.open", title: "Open selected download", keys: ["Return"]),
                        DocumentationShortcut(id: "downloads.browse.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "downloads.browse.refresh", title: "Refresh downloads", keys: ["⌘", "R"]),
                        DocumentationShortcut(id: "downloads.browse.escape", title: "Clear filter or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "downloads.actions",
                title: "Open, Reveal, Copy, and Refresh",
                blocks: [
                    .bullets("downloads.actions.items", [
                        "Open Newest Download launches the newest file in its default application.",
                        "Copy Newest Download writes the actual file URL to the pasteboard so another app can receive the file.",
                        "For the selection, you can Open, Show in Finder, or Copy the file.",
                        "Refresh Downloads performs a new metadata scan."
                    ]),
                    .callout(
                        "downloads.actions.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Read-only Downloads access",
                            text: "Commandly uses a narrow read-only Downloads entitlement. The scan reads metadata rather than file contents, cannot modify Downloads, and never logs filenames or paths."
                        )
                    )
                ]
            )
        ],
        keywords: ["latest", "recent", "Finder", "copy file", "reveal", "refresh", "read-only"]
    )

    static let timers = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Run multiple named countdowns, use built-in Focus and Short Break presets, and pause, resume, reset, filter, or delete timers without an account or network service.",
        sections: [
            DocumentationSection(
                id: "timers.create",
                title: "Start a Timer",
                blocks: [
                    .steps("timers.create.steps", [
                        "Open Timers & Focus. Choose the 25-minute Focus preset, the 5-minute Short Break preset, or New Timer.",
                        "For a custom timer, enter a nonempty name and a duration from 1 to 1,440 minutes.",
                        "Press Return to start. You can create and run multiple timers at the same time."
                    ]),
                    .shortcuts("timers.create.shortcuts", [
                        DocumentationShortcut(id: "timers.create.new", title: "Create a new timer", keys: ["⌘", "N"]),
                        DocumentationShortcut(
                            id: "timers.create.primary",
                            title: "Start, pause, resume, or reset the selected timer",
                            keys: ["Return"],
                            detail: "The primary action changes with the timer's current phase."
                        ),
                        DocumentationShortcut(id: "timers.create.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "timers.create.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "timers.create.escape", title: "Cancel creation, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "timers.manage",
                title: "Manage Active Timers",
                blocks: [
                    .bullets("timers.manage.actions", [
                        "Search by timer name or phase, or filter by All Timers, Running, Paused & Ready, or Completed.",
                        "A ready timer starts, a running timer pauses, a paused timer resumes, and a completed timer resets when you use its primary action.",
                        "The actions menu can start a preset, reset or delete the selection, and turn the local completion sound on or off."
                    ]),
                    .callout(
                        "timers.manage.duration",
                        DocumentationCallout(
                            kind: .tip,
                            title: "Drift-resistant countdowns",
                            text: "Commandly derives remaining time from absolute dates. Active timers continue when the launcher closes, and multiple timers can progress independently."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "timers.limits",
                title: "Completion and Limits",
                blocks: [
                    .callout(
                        "timers.limits.local",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Commandly must remain running",
                            text: "Timers are in-process and do not survive quitting Commandly. There are no notifications, background launches, automatic Pomodoro work/break cycles, session history, or productivity reports."
                        )
                    ),
                    .callout(
                        "timers.limits.sound",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Local completion sound",
                            text: "When enabled, completion uses a local macOS sound. No notification permission, account, or network service is involved."
                        )
                    )
                ]
            )
        ],
        keywords: ["countdown", "focus", "pomodoro", "break", "pause", "resume", "sound"]
    )

    static let productivityLibrary = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Keep reusable snippets, quick notes, Quicklinks, and emoji keywords in one searchable local library, with explicit copy, open, edit, share, and delete workflows.",
        sections: [
            DocumentationSection(
                id: "library.types",
                title: "Four Reusable Item Types",
                blocks: [
                    .bullets("library.types.items", [
                        "Snippet stores reusable text or code. Every {{clipboard}} token is replaced with the current clipboard string when the snippet is copied.",
                        "Quick Note stores persistent local text that can be searched and copied.",
                        "Quicklink opens a validated HTTP or HTTPS URL, file URL, absolute or ~/ path, folder path, or custom application deep link.",
                        "Emoji Keyword pairs a searchable title or keyword with an emoji value that is copied on use."
                    ]),
                    .examples("library.types.examples", [
                        DocumentationExample(
                            id: "library.types.clipboard-template",
                            input: "Snippet: Hello, {{clipboard}}!\nClipboard: team",
                            output: "Hello, team!",
                            detail: "All {{clipboard}} tokens are replaced at copy time."
                        ),
                        DocumentationExample(
                            id: "library.types.quicklink-web",
                            input: "https://developer.apple.com",
                            detail: "A web Quicklink opens only after you explicitly use it."
                        ),
                        DocumentationExample(
                            id: "library.types.quicklink-path",
                            input: "~/Documents",
                            detail: "Absolute and tilde-prefixed file or folder paths are supported."
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "library.manage",
                title: "Create, Find, and Manage Items",
                blocks: [
                    .steps("library.manage.steps", [
                        "Use the plus menu to choose Snippet, Quick Note, Quicklink, or Emoji Keyword.",
                        "Enter a title and content, then choose Save in the editor. Return inserts a new line in multiline content.",
                        "Search titles, contents, and type names, or choose a type filter.",
                        "Use the selected item's primary action to copy text and emoji items or open a Quicklink. Use Command-K for Edit, Delete, and New Item."
                    ]),
                    .bullets("library.manage.details", [
                        "Delete requires confirmation.",
                        "The detail pane can share an item's content through the native macOS share sheet.",
                        "Escape closes confirmation, actions, or the editor before it clears search or returns to the launcher."
                    ]),
                    .shortcuts("library.manage.shortcuts", [
                        DocumentationShortcut(id: "library.manage.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "library.manage.use", title: "Use the selected item", keys: ["Return"]),
                        DocumentationShortcut(id: "library.manage.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "library.manage.escape", title: "Cancel the closest active state", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "library.safety",
                title: "Quicklink Safety and Local Storage",
                blocks: [
                    .callout(
                        "library.safety.quicklinks",
                        DocumentationCallout(
                            kind: .important,
                            title: "Validated before opening",
                            text: "Quicklinks reject javascript: and data: payloads, malformed links, and unsafe values. A valid custom scheme is handed to macOS and can still fail if no target app accepts it or the sandbox protects the path."
                        )
                    ),
                    .callout(
                        "library.safety.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Local private library",
                            text: "Items are stored as versioned JSON in Commandly's Application Support container. Content is not logged or uploaded. Sharing is an explicit native share action, not a Commandly account, public link, sync service, or team library."
                        )
                    )
                ]
            )
        ],
        keywords: ["snippet", "clipboard template", "quick note", "Quicklink", "bookmark", "deep link", "emoji keyword", "share"]
    )

    static let shelf = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Keep files, folders, clipboard text, and clipboard images on one temporary floating board, then preview, share, manage, copy, move, or drag them into another macOS application.",
        sections: [
            DocumentationSection(
                id: "shelf.open",
                title: "Open, Stage, and Use Items",
                blocks: [
                    .steps("shelf.open.steps", [
                        "Use the system-wide New Shelf or New Shelf From Clipboard shortcut, choose either command from Commandly's menu bar item, or search for Shelf in the launcher and press Return. Each new board opens on the display that is active when you invoke it.",
                        "Drop one or more files or folders on the board. A blue outline and an incoming-item prompt confirm the target without relying on color alone. New Shelf From Clipboard accepts text, standalone images, files, and folders.",
                        "Choose the semantic item count, such as 2 images or 3 PDFs, to inspect the grid, toggle a multi-item selection, and drag the active items into Finder or another compatible app. Drag-out is copy-only, so originals are never moved or deleted and the Shelf references remain.",
                        "When a drag enters Shelf, drop directly on the native AirDrop, Messages, or Mail targets below the board to open that sharing service without first staging the files."
                    ]),
                    .bullets("shelf.open.actions", [
                        "Open, Open With, Show in Finder, and Quick Look use native macOS services.",
                        "AirDrop, Messages, Mail, and More Sharing apply to the explicit selection, or to all staged items when nothing is selected.",
                        "Add From Clipboard accepts text, standalone images, files, and folders. Copy Items writes the staged file representations back to the pasteboard; Copy Paths writes their newline-separated paths as text.",
                        "Drag from any unused part of the board to move Shelf. Controls and staged-item drags keep their own interactions, so dragging an item out does not move the window.",
                        "Duplicate, Copy To, Move To, and Rename change the real items on disk. Remove From Shelf and Clear Shelf remove references only.",
                        "Move to Trash changes the real items and requires confirmation from the detail view."
                    ]),
                    .shortcuts("shelf.open.shortcuts", [
                        DocumentationShortcut(
                            id: "shelf.open.new",
                            title: "New Shelf",
                            keys: ["⌥", "⇧", "Space"],
                            detail: "Works system-wide while Commandly is running."
                        ),
                        DocumentationShortcut(
                            id: "shelf.open.clipboard",
                            title: "New Shelf From Clipboard",
                            keys: ["⌥", "⇧", "A"],
                            detail: "Works system-wide while Commandly is running."
                        ),
                        DocumentationShortcut(id: "shelf.open.preview", title: "Quick Look active items", keys: ["Space"]),
                        DocumentationShortcut(id: "shelf.open.details", title: "Toggle compact and detail views", keys: ["Tab"]),
                        DocumentationShortcut(id: "shelf.open.copy", title: "Copy active file URLs", keys: ["⌘", "C"]),
                        DocumentationShortcut(id: "shelf.open.paste", title: "Add clipboard content", keys: ["⌘", "V"]),
                        DocumentationShortcut(id: "shelf.open.clear", title: "Clear the board", keys: ["Delete"]),
                        DocumentationShortcut(
                            id: "shelf.open.escape",
                            title: "Close Shelf",
                            keys: ["Esc"],
                            detail: "Command-W also closes the board."
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "shelf.settings",
                title: "Shelf Settings",
                blocks: [
                    .bullets("shelf.settings.items", [
                        "Close when empty dismisses the board after its final staged reference is explicitly removed or trashed. Copy-only drag-out keeps references, and a new empty board remains open.",
                        "Preferred corner chooses Bottom right, Bottom left, Top right, or Top left on the display active when a new board opens.",
                        "Play drop sound plays a local macOS sound after new content is accepted."
                    ]),
                    .callout(
                        "shelf.settings.scope",
                        DocumentationCallout(
                            kind: .important,
                            title: "Corner placement applies on open",
                            text: "Preferred corner positions a new board on the active display. Drag any unused part of the board to move it afterward; controls and item drags keep the board in place."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "shelf.limits",
                title: "Current Limits",
                blocks: [
                    .callout(
                        "shelf.limits.preview",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "One temporary board",
                            text: "Shelf does not persist or restore boards, open simultaneous or recent/pinned shelves, reorder items, materialize promised Finder files, or create reusable snippets. Clipboard text and standalone images are represented by private temporary files only for the lifetime of the board."
                        )
                    ),
                    .callout(
                        "shelf.limits.activation",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "No hidden activation or processing system",
                            text: "Shelf has no notch/menu-bar drop zone, shake gesture, modifier-key drag activation, folder monitoring, hosted/cloud-provider links, file transformations, custom scripts, or shell execution. Open it through Commandly's launcher, menu-bar commands, or a configured application shortcut."
                        )
                    ),
                    .callout(
                        "shelf.limits.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Temporary local content",
                            text: "Dropped or pasted files and folders remain untouched references. Clipboard text and standalone images are written to a private per-board temporary directory so native macOS actions can use them, then removed when the item leaves or Shelf closes. Shelf does not log paths, previews, clipboard values, or contents. Native sharing occurs only after your action; the selected macOS service controls recipients, sign-in, and transfer."
                        )
                    )
                ]
            )
        ],
        keywords: [
            "shelf",
            "staging",
            "clipboard",
            "drop",
            "temporary",
            "board",
            "menu bar",
            "New Shelf",
            "Drop files here",
            "AirDrop",
            "Messages",
            "Mail",
            "Quick Look",
            "drag out",
            "file actions"
        ]
    )
}
