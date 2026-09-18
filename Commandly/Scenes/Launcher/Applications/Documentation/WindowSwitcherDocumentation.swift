import Foundation

extension RegisteredApplicationDocumentation {
    static let windowSwitcher = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "A reviewed prototype for an original Commandly individual-window panel. The "
            + "sandboxed production target does not register this application because cross-app "
            + "Accessibility control requires a separate approved distribution architecture.",
        sections: [
            DocumentationSection(
                id: "window-switcher.open",
                title: "Open and Switch",
                blocks: [
                    .callout(
                        "window-switcher.open.unavailable",
                        DocumentationCallout(
                            kind: .important,
                            title: "Unavailable in the sandboxed build",
                            text: "These controls document foundation code and intended behavior, "
                                + "not a shipping Commandly feature. Enabling them requires a new "
                                + "security and distribution decision for a separately authorized "
                                + "companion or a non-sandboxed direct build."
                        )
                    ),
                    .paragraph(
                        "window-switcher.open.summary",
                        "The prototype accepts Option-Tab, an assigned application shortcut, or a "
                            + "launcher command. Option-Tab defaults to Hold and Cycle, which "
                            + "advances the selection and focuses it when the shortcut is released. "
                            + "Launcher and assigned application shortcuts use a toggle overlay for "
                            + "deliberate selection."
                    ),
                    .shortcuts("window-switcher.open.shortcuts", [
                        DocumentationShortcut(
                            id: "window-switcher.open.forward",
                            title: "Show or cycle forward",
                            keys: ["⌥", "Tab"]
                        ),
                        DocumentationShortcut(
                            id: "window-switcher.open.backward",
                            title: "Cycle backward",
                            keys: ["⌥", "⇧", "Tab"]
                        ),
                        DocumentationShortcut(
                            id: "window-switcher.open.navigate",
                            title: "Move selection",
                            keys: ["←", "↑", "↓", "→"]
                        ),
                        DocumentationShortcut(
                            id: "window-switcher.open.focus",
                            title: "Focus selected window",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "window-switcher.open.dismiss",
                            title: "Close without switching",
                            keys: ["Esc"]
                        ),
                    ]),
                    .callout(
                        "window-switcher.open.command-tab",
                        DocumentationCallout(
                            kind: .important,
                            title: "Command-Tab replacement is opt-in",
                            text: "Commandly leaves the standard macOS Command-Tab switcher "
                                + "unchanged by default. Turn on Replace Command-Tab only if you want "
                                + "the same Commandly panel on that shortcut."
                        )
                    ),
                ]
            ),
            DocumentationSection(
                id: "window-switcher.find",
                title: "Choose the Window Set",
                blocks: [
                    .bullets("window-switcher.find.options", [
                        "Show all windows, only the active application's windows, or groups by "
                            + "application; preserve current adapter order or sort by application "
                            + "name or window title.",
                        "Optionally limit results to the current desktop or display and include "
                            + "hidden, minimized, or windowless applications.",
                        "Type to filter visible titles and application names. Selection can follow "
                            + "pointer hover, while clicking remains available when hover selection "
                            + "is off. H, J, K, and L navigation can be enabled when text search is "
                            + "not active.",
                        "Exclusion terms accept application names, exact bundle identifiers, or "
                            + "window-title text separated by commas or new lines. Application and "
                            + "title text use local case-insensitive matching."
                    ]),
                    .callout(
                        "window-switcher.find.desktop",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "macOS controls Space visibility",
                            text: "Current-desktop filtering uses the window information macOS makes "
                                + "available. A window assigned across Spaces or owned by a system "
                                + "process may not expose the same metadata as an ordinary "
                                + "application window."
                        )
                    ),
                ]
            ),
            DocumentationSection(
                id: "window-switcher.appearance",
                title: "Layout, Labels, and Actions",
                blocks: [
                    .bullets("window-switcher.appearance.options", [
                        "Choose a grid, list, or horizontal strip and adjust item size. Grid mode also provides a bounded column count.",
                        "Window titles, application names, and inline action controls can be shown independently.",
                        "Available actions focus, close, minimize or restore, toggle full screen, "
                            + "zoom, center, place in a screen half, and quit the owning application. "
                            + "Commandly performs only the action you select and reports windows that "
                            + "macOS will not control.",
                        "During a session, Command-W/M/F/G/C/Q control close, minimize, full screen, "
                            + "zoom, center, and quit. Command-1/2/3/4 place the selected window in "
                            + "the left, right, top, or bottom half.",
                        "Place the panel on the active, pointer, or main display, then apply bounded horizontal and vertical offsets."
                    ]),
                    .callout(
                        "window-switcher.appearance.limits",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "One window at a time",
                            text: "Half-screen, center, and zoom actions affect only the selected "
                                + "window. Window Switcher does not save multi-window workspaces or "
                                + "move windows between Spaces."
                        )
                    ),
                ]
            ),
            DocumentationSection(
                id: "window-switcher.previews",
                title: "Previews, Dock Integration, and Privacy",
                blocks: [
                    .bullets("window-switcher.previews.options", [
                        "Thumbnail quality, live refresh, and a bounded in-memory cache can be "
                            + "configured. Setting the cache limit to zero disables reuse.",
                        "Dock window previews are off by default. When enabled, Commandly waits for "
                            + "the configured delay before showing a best-effort preview for the "
                            + "hovered application.",
                        "In a future authorized runtime, unavailable Screen Recording access would "
                            + "fall back to application icons and metadata-only cards."
                    ]),
                    .callout(
                        "window-switcher.previews.permissions",
                        DocumentationCallout(
                            kind: .permission,
                            title: "A companion permission design is still required",
                            text: "The sandboxed Commandly target cannot use cross-application "
                                + "Accessibility for this feature. A future approved companion "
                                + "would require its own explicit Accessibility grant; optional "
                                + "Screen Recording would remain limited to visual previews."
                        )
                    ),
                    .callout(
                        "window-switcher.previews.privacy",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Private window data stays transient",
                            text: "Window titles and captured previews are kept only for the active "
                                + "presentation or bounded memory cache. Commandly does not persist "
                                + "or log titles, thumbnails, search text, or the exclusion matches "
                                + "that occur while switching."
                        )
                    ),
                ]
            ),
        ],
        keywords: [
            "Option-Tab",
            "Command-Tab",
            "windows",
            "Spaces",
            "displays",
            "Dock previews",
            "thumbnails",
            "Accessibility",
            "Screen Recording",
            "Vim",
        ]
    )
}
