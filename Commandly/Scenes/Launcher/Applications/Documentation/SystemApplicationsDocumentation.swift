import Foundation

extension RegisteredApplicationDocumentation {
    static let highlightMode = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Make mouse clicks, typed text, keyboard shortcuts, and cursor position visible during a presentation, tutorial, or screen recording.",
        sections: [
            DocumentationSection(
                id: "highlight-mode.use",
                title: "Present with Visual Feedback",
                blocks: [
                    .steps("highlight-mode.use.steps", [
                        "Open Highlight Mode or its Configure Highlight Mode tool, then choose Turn Highlight Mode On.",
                        "Grant Accessibility access when macOS asks after this explicit action.",
                        "Present or record normally while click rings, keyboard feedback, and the cursor spotlight appear above your apps.",
                        "Run the Toggle Highlight Mode tool, use its assigned global shortcut, or return to the application and choose Turn Highlight Mode Off."
                    ]),
                    .shortcuts("highlight-mode.use.shortcuts", [
                        DocumentationShortcut(
                            id: "highlight-mode.use.return",
                            title: "Turn Highlight Mode on or off from its application",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "highlight-mode.use.global",
                            title: "Toggle without opening Commandly",
                            keys: ["Assigned global shortcut"],
                            detail: "Expand Highlight Mode in Settings → Applications and assign the Toggle Highlight Mode tool."
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "highlight-mode.configure",
                title: "Configure the Overlay",
                blocks: [
                    .bullets("highlight-mode.configure.options", [
                        "Turn mouse click rings, keyboard shortcuts, typed text, and cursor spotlight on or off independently.",
                        "Choose a compact, medium, or large cursor spotlight.",
                        "Choose the highlight color and how long transient feedback remains visible."
                    ]),
                    .callout(
                        "highlight-mode.configure.live",
                        DocumentationCallout(
                            kind: .important,
                            title: "Live settings",
                            text: "Changes in Applications settings apply to an active Highlight Mode session without capturing or storing an input history."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "highlight-mode.privacy",
                title: "Privacy and Permission",
                blocks: [
                    .callout(
                        "highlight-mode.privacy.ephemeral",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Ephemeral input only",
                            text: "Typed characters and shortcuts exist only in memory long enough to draw the overlay. Commandly does not persist, log, upload, or copy them. Turn typed-text feedback off before entering sensitive information."
                        )
                    ),
                    .callout(
                        "highlight-mode.privacy.permission",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Accessibility is contextual",
                            text: "Global mouse and keyboard observation requires Accessibility access. Commandly requests it only when you turn Highlight Mode on; denial leaves the mode off."
                        )
                    )
                ]
            )
        ],
        keywords: [
            "presentation", "tutorial", "screen recording", "mouse clicks", "keystrokes",
            "shortcuts", "cursor spotlight", "Accessibility"
        ]
    )

    static let microphoneControl = LauncherApplicationDocumentation(
        category: .system,
        overview: "See whether the default Mac input device is muted and change its public Core Audio mute state without recording or inspecting any audio.",
        sections: [
            DocumentationSection(
                id: "microphone.control",
                title: "Check and Change the Microphone",
                blocks: [
                    .steps("microphone.control.steps", [
                        "Open Microphone Control from Commandly.",
                        "Check the large On or Off indicator and the default input device name.",
                        "Press Return or choose the main button to turn the current microphone off or on.",
                        "Keep the application open to see device or mute-state changes made elsewhere on the Mac.",
                        "For a direct action, run the Toggle Microphone tool or assign that tool a global shortcut in Settings → Applications."
                    ]),
                    .shortcuts("microphone.control.shortcuts", [
                        DocumentationShortcut(
                            id: "microphone.control.toggle",
                            title: "Turn the microphone on or off",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "microphone.control.actions",
                            title: "Open actions",
                            keys: ["⌘", "K"]
                        ),
                        DocumentationShortcut(
                            id: "microphone.control.escape",
                            title: "Return to launcher search",
                            keys: ["Esc"]
                        ),
                        DocumentationShortcut(
                            id: "microphone.control.global",
                            title: "Toggle without opening Commandly",
                            keys: ["Assigned global shortcut"],
                            detail: "Assign the Toggle Microphone tool under Microphone Control."
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "microphone.boundaries",
                title: "Privacy and Device Support",
                blocks: [
                    .callout(
                        "microphone.boundaries.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "No audio capture",
                            text: "Commandly reads only the device name and mute property. It does not open an audio stream, inspect samples, save recordings, or request Microphone permission."
                        )
                    ),
                    .callout(
                        "microphone.boundaries.hardware",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Depends on the input device",
                            text: "The control affects apps that use the current default input device. Some external, virtual, aggregate, or driver-managed devices do not expose a writable system mute property; Commandly reports those devices as unavailable instead of changing input gain."
                        )
                    )
                ]
            )
        ],
        keywords: ["mic", "mute", "unmute", "audio input", "Core Audio", "privacy"]
    )

    static let systemActivity = LauncherApplicationDocumentation(
        category: .system,
        overview: "Inspect aggregate resource use for this Mac and manage regular running GUI applications with explicit switch, quit, force-quit, and protected bulk-quit actions.",
        sections: [
            DocumentationSection(
                id: "activity.resources",
                title: "Resources",
                blocks: [
                    .bullets("activity.resources.metrics", [
                        "Aggregate CPU use.",
                        "Used and total physical memory.",
                        "Used and total capacity for the filesystem containing your home directory.",
                        "System uptime and current thermal state."
                    ]),
                    .paragraph(
                        "activity.resources.refresh",
                        "Commandly refreshes the snapshot automatically every three seconds while the application is open. Press Return or use Refresh System Activity for an immediate sample."
                    ),
                    .callout(
                        "activity.resources.scope",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Aggregate monitor",
                            text: "This is not a full Unix process inspector. It does not show GPU, network, battery, daemon, per-process CPU or memory, ports, or arbitrary signals."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "activity.applications",
                title: "Running Applications",
                blocks: [
                    .steps("activity.applications.steps", [
                        "Switch to the Applications mode.",
                        "Search by application name, bundle identifier, or process identifier.",
                        "Select a regular GUI application and press Return to switch to it.",
                        "Press Command-K for Refresh, Switch, Quit, Force Quit, or Quit All Other Applications."
                    ]),
                    .bullets("activity.applications.actions", [
                        "Quit requests graceful termination.",
                        "Force Quit shows a destructive confirmation because unsaved work can be lost.",
                        "Quit All Other Applications shows a confirmation and gracefully requests termination for every eligible GUI app."
                    ]),
                    .shortcuts("activity.applications.shortcuts", [
                        DocumentationShortcut(id: "activity.applications.arrows", title: "Move application selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "activity.applications.primary", title: "Refresh resources, switch apps, or confirm", keys: ["Return"]),
                        DocumentationShortcut(id: "activity.applications.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "activity.applications.escape", title: "Cancel confirmation, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "activity.protection",
                title: "Termination Protection",
                blocks: [
                    .callout(
                        "activity.protection.rules",
                        DocumentationCallout(
                            kind: .important,
                            title: "Protected applications",
                            text: "Commandly, Finder, and the current frontmost application are excluded from termination. Switch away from a frontmost app before trying to quit it. Partial failures are reported rather than presented as complete success."
                        )
                    ),
                    .callout(
                        "activity.protection.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Native system data",
                            text: "System Activity reads aggregate host statistics and the public list of regular GUI applications through native macOS APIs. It does not require an account or upload the snapshot."
                        )
                    )
                ]
            )
        ],
        keywords: ["CPU", "memory", "storage", "uptime", "thermal", "running apps", "process", "quit", "force quit", "quit all"]
    )

    static let portManager = LauncherApplicationDocumentation(
        category: .system,
        overview: "Inspect local TCP and UDP listeners, then explicitly stop the process that owns a selected listener.",
        sections: [
            DocumentationSection(
                id: "ports.listeners",
                title: "Listening Ports",
                blocks: [
                    .paragraph("ports.listeners.scope", "Port Manager lists local TCP listeners and UDP sockets visible to the current user. Filter by port number, process name, process ID, or protocol."),
                    .steps("ports.listeners.stop", ["Select a listener and press Return.", "Review the process, protocol, and port in the confirmation.", "Choose Stop Process to send that process a graceful termination request."]),
                    .examples("ports.listeners.typed-command", [
                        DocumentationExample(
                            id: "ports.listeners.kill-example",
                            input: "kill port 3000",
                            output: "Open Port Manager at port 3000 for review"
                        ),
                        DocumentationExample(
                            id: "ports.listeners.stop-example",
                            input: "stop port 8080",
                            output: "Open Port Manager at port 8080 for review"
                        )
                    ]),
                    .paragraph(
                        "ports.listeners.typed-command-behavior",
                        "Typed commands accept one port from 1 through 65535. No match shows a local status, one match opens confirmation, and multiple matches require a selection. The command itself has no shortcut; assign Inspect Ports or Kill Port instead."
                    ),
                    .shortcuts("ports.listeners.shortcuts", [DocumentationShortcut(id: "ports.listeners.arrows", title: "Move listener selection", keys: ["↑", "↓"]), DocumentationShortcut(id: "ports.listeners.stop-key", title: "Stop selected listener", keys: ["Return"]), DocumentationShortcut(id: "ports.listeners.actions", title: "Refresh or stop listener", keys: ["⌘", "K"])])
                ]
            ),
            DocumentationSection(
                id: "ports.safety",
                title: "Safety and Privacy",
                blocks: [
                    .callout("ports.safety.confirmation", DocumentationCallout(kind: .important, title: "Stopping a port stops its process", text: "A port cannot be terminated independently. Commandly rechecks that the selected process still owns the listener, then sends it a graceful termination request. Unsaved work can be lost, and protected or other-user processes may be unavailable.")),
                    .callout("ports.safety.privacy", DocumentationCallout(kind: .privacy, title: "Local inspection only", text: "Listener metadata is inspected on this Mac only. Commandly does not persist, upload, or log port numbers, process names, process IDs, or addresses."))
                ]
            )
        ],
        keywords: [
            "port", "TCP", "UDP", "localhost", "listener", "server", "kill port", "stop port",
            "Inspect Ports", "Kill Port"
        ]
    )

    static let storageCleaner = LauncherApplicationDocumentation(
        category: .system,
        overview: "Reclaim disk space with a review-first scan for identifier-based app leftovers, third-party user caches, and byte-for-byte duplicate files inside a folder you choose.",
        sections: [
            DocumentationSection(
                id: "storage-cleaner.review",
                title: "Review Cleanup Candidates",
                blocks: [
                    .bullets("storage-cleaner.review.tools", [
                        "Review App Leftovers and Caches opens Storage Cleaner and starts its bounded user Library scan.",
                        "Find Exact Duplicates opens Storage Cleaner and presents the native one-folder picker before any duplicate scan begins.",
                        "Both tools stop at the normal review surface. You can change the proposed selection, and nothing moves to Trash until you open Review Cleanup and confirm Move to Trash."
                    ]),
                    .bullets("storage-cleaner.review.categories", [
                        "App Leftovers are identifier-named files or folders in reviewed user Library locations whose bundle identifier does not match an installed application.",
                        "Caches are third-party entries under your user Library/Caches directory. They are never preselected because a currently installed app may recreate or actively use them.",
                        "Exact Duplicates are regular files with the same size and SHA-256 content hash inside one folder you explicitly choose. One copy in every group always remains unselected."
                    ]),
                    .steps("storage-cleaner.review.steps", [
                        "Open Storage Cleaner and wait for the bounded user Library scan.",
                        "Filter by category, name, parent path, or bundle identifier.",
                        "Use Return to toggle the focused candidate, or choose Select Recommended Items from Actions.",
                        "Press Command-Return or choose Review Cleanup, then confirm Move to Trash."
                    ]),
                    .shortcuts("storage-cleaner.review.shortcuts", [
                        DocumentationShortcut(id: "storage-cleaner.review.arrows", title: "Move candidate focus", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "storage-cleaner.review.toggle", title: "Toggle focused candidate", keys: ["Return"]),
                        DocumentationShortcut(id: "storage-cleaner.review.clean", title: "Review selected cleanup", keys: ["⌘", "Return"]),
                        DocumentationShortcut(id: "storage-cleaner.review.actions", title: "Rescan, find duplicates, or change selection", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "storage-cleaner.review.escape", title: "Cancel confirmation, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "storage-cleaner.duplicates",
                title: "Find Exact Duplicates",
                blocks: [
                    .steps("storage-cleaner.duplicates.steps", [
                        "Choose Find Exact Duplicates or use the Actions menu.",
                        "Select one folder in the native folder picker.",
                        "Review each byte-for-byte duplicate group. The most recently modified copy starts as the kept copy.",
                        "Toggle files if you want to keep a different copy; Commandly automatically leaves at least one copy unselected."
                    ]),
                    .callout(
                        "storage-cleaner.duplicates.scope",
                        DocumentationCallout(
                            kind: .permission,
                            title: "One ephemeral folder scope",
                            text: "Duplicate scanning uses only the folder you choose for that scan. The folder grant, paths, hashes, and results are not persisted or uploaded."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "storage-cleaner.safety",
                title: "Safety and Limitations",
                blocks: [
                    .callout(
                        "storage-cleaner.safety.trash",
                        DocumentationCallout(
                            kind: .important,
                            title: "Trash only, after confirmation",
                            text: "Storage Cleaner never deletes automatically or empties the Trash. Only checked items in the confirmation are moved, and partial failures are reported."
                        )
                    ),
                    .callout(
                        "storage-cleaner.safety.leftovers",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Conservative leftover matching",
                            text: "The initial scanner recognizes reverse-domain identifier names and intentionally skips ambiguous human-named folders, Apple data, shared group containers, hidden files, packages, and protected or inaccessible paths. A listed identifier can still belong to a helper without a visible app, so review every path."
                        )
                    ),
                    .callout(
                        "storage-cleaner.safety.bounds",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Bounded and on device",
                            text: "Library candidates, duplicate metadata, and content hashes stay in memory. Scans stop at documented file and hashing limits and report partial results instead of claiming a complete disk sweep."
                        )
                    )
                ]
            )
        ],
        keywords: [
            "storage", "disk cleaner", "cache", "app leftovers", "residual files",
            "duplicates", "SHA-256", "Trash", "privacy"
        ]
    )

    static let windowLayouts = LauncherApplicationDocumentation(
        category: .system,
        overview: "Resize and position the external window that was focused before Commandly opened, using 58 built-in arrangements or your own named normalized rectangles.",
        sections: [
            DocumentationSection(
                id: "layouts.presets",
                title: "Apply a Built-in Layout",
                blocks: [
                    .steps("layouts.presets.steps", [
                        "Focus the window you want to arrange, then open Commandly.",
                        "Open Window Layouts and browse or search the 58 Presets source.",
                        "Choose a Featured, Halves, Thirds, Quarters, or Grid preset.",
                        "Press Return to apply the rectangle to the previously focused external window."
                    ]),
                    .bullets("layouts.presets.catalog", [
                        "Featured includes Maximize and centered large or medium rectangles.",
                        "Halves and Thirds include horizontal, vertical, and two-thirds arrangements.",
                        "Quarters and Grid include corner quarters, 3×3 cells, wide and tall 3×3 spans, and 4×4 cells."
                    ]),
                    .shortcuts("layouts.presets.shortcuts", [
                        DocumentationShortcut(id: "layouts.presets.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "layouts.presets.apply", title: "Apply selected layout", keys: ["Return"]),
                        DocumentationShortcut(id: "layouts.presets.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "layouts.presets.escape", title: "Cancel editing, clear search, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "layouts.custom",
                title: "Create a Custom Layout",
                blocks: [
                    .steps("layouts.custom.steps", [
                        "Press Command-K and choose New Custom Layout.",
                        "Give the layout a name and enter x, y, width, and height values.",
                        "Keep every value within the screen: x and y start at the top-left, and x + width and y + height must not exceed 1.",
                        "Save the layout, switch to the Custom source, and press Return to apply it. Use the actions menu to delete a selected custom layout."
                    ]),
                    .examples("layouts.custom.examples", [
                        DocumentationExample(
                            id: "layouts.custom.centered",
                            input: "x 0.1, y 0.1, width 0.8, height 0.8",
                            output: "A centered rectangle using 80% of the visible screen width and height"
                        ),
                        DocumentationExample(
                            id: "layouts.custom.left-half",
                            input: "x 0, y 0, width 0.5, height 1",
                            output: "Left half of the visible screen"
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "layouts.permission",
                title: "Accessibility and Targeting",
                blocks: [
                    .callout(
                        "layouts.permission.contextual",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Requested when you apply",
                            text: "Window Layouts asks for macOS Accessibility only after you invoke Apply. If access is denied, Commandly explains the failure so you can enable it in System Settings → Privacy & Security → Accessibility."
                        )
                    ),
                    .callout(
                        "layouts.permission.scope",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "One focused window",
                            text: "A layout acts only on the focused window of the external app captured before Commandly opened. There are no multi-app workspace layouts, window sequences, or separate global shortcuts for individual rectangles."
                        )
                    )
                ]
            )
        ],
        keywords: ["resize", "tile", "58", "presets", "grid", "custom rectangle", "Accessibility", "active window"]
    )
}
