enum CommandWheelDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.command-wheel",
        title: "Command Wheel",
        subtitle: "Run familiar commands with a hold, flick, and release gesture.",
        systemImage: "circle.hexagongrid",
        category: .coreFeatures,
        order: 140,
        documentation: LauncherApplicationDocumentation(
            category: .coreFeatures,
            overview: "Command Wheel is a cursor-centered presentation of Commandly’s existing commands. It is disabled until you enable it and assign a profile shortcut in Settings. Wheel entries store command identifiers and arguments; selection still resolves and executes through the same command engine used by launcher search.",
            sections: [
                DocumentationSection(
                    id: "command-wheel-start",
                    title: "Enable and open a wheel",
                    blocks: [
                        .steps("command-wheel-start-steps", [
                            "Open Settings → Command Wheel and turn on Enable Command Wheel.",
                            "Select a profile and record a global shortcut. Choose another combination if Commandly reports a conflict.",
                            "For Hold and Release, hold the shortcut and move immediately toward the intended direction. Release runs the resolved segment even if content was still preparing and the panel had not appeared yet.",
                            "For Toggle, press the shortcut once, then click a segment or select it with the keyboard.",
                        ]),
                        .callout(
                            "command-wheel-start-access",
                            DocumentationCallout(
                                kind: .permission,
                                title: "No Accessibility permission for wheel shortcuts",
                                text: "Command Wheel’s Carbon global shortcuts and pointer sampling do not require Accessibility access. Accessibility remains optional for features such as Window Layouts."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-select-cancel",
                    title: "Select, execute, or cancel",
                    blocks: [
                        .bullets("command-wheel-select-rules", [
                            "A highlighted segment is eligible immediately; a fast flick does not wait for the opening animation.",
                            "Release inside the center dead zone in Hold and Release mode to close without executing.",
                            "Press Escape to cancel. In a submenu, Escape or the center Back control returns to the parent page first.",
                            "In Toggle mode, clicking outside closes the wheel, clicking the center cancels or goes back, and clicking an enabled segment activates it.",
                            "Unavailable and missing commands remain visible with an explanatory state unless the profile explicitly hides them. They cannot execute.",
                        ]),
                        .shortcuts("command-wheel-keyboard", [
                            DocumentationShortcut(
                                id: "command-wheel-keyboard-escape",
                                title: "Cancel or go back",
                                keys: ["Esc"]
                            ),
                            DocumentationShortcut(
                                id: "command-wheel-keyboard-activate",
                                title: "Activate selected segment",
                                keys: ["↩"]
                            ),
                            DocumentationShortcut(
                                id: "command-wheel-keyboard-rotate",
                                title: "Move around selectable segments",
                                keys: ["←", "→", "↑", "↓"]
                            ),
                            DocumentationShortcut(
                                id: "command-wheel-keyboard-tab",
                                title: "Move to next or previous segment",
                                keys: ["Tab", "⇧", "Tab"]
                            ),
                            DocumentationShortcut(
                                id: "command-wheel-keyboard-number",
                                title: "Select a visible numbered slot",
                                keys: ["1", "…", "9"]
                            ),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-submenus",
                    title: "Use submenus",
                    blocks: [
                        .paragraph(
                            "command-wheel-submenus-overview",
                            "A submenu replaces the current radial page while preserving one stable wheel center. Choose Directional Continuation, Dwell, Click Only, or Disabled in the profile’s interaction settings."
                        ),
                        .bullets("command-wheel-submenus-methods", [
                            "Directional Continuation opens the child page when you continue outward beyond its activation threshold.",
                            "Dwell opens the child page after the configured pointer delay.",
                            "Click Only requires a click or keyboard activation on the submenu segment.",
                            "Move back into the center after entering a submenu, activate the center Back control, or press Escape to return to its parent.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-profiles",
                    title: "Build profiles and pages",
                    blocks: [
                        .steps("command-wheel-profiles-steps", [
                            "Open Settings → Command Wheel. Create, rename, duplicate, reorder, enable, or export profiles from the profile list.",
                            "Choose the default profile and optionally give enabled profiles their own shortcuts.",
                            "Select a page and radial slot in the live editor.",
                            "Search the same registered commands and installed applications used by the launcher, assign one directly, create a submenu, choose Recent or Frequent Commands, or clear the slot.",
                            "Use the slot editor to change supported serializable arguments, an accessibility/editor label, or an SF Symbol override. The radial surface stays icon-only.",
                            "Adjust activation, placement, radius, dead zone, slot count, submenu behavior, animation, keyboard hints, and alternate input options. Changes save automatically after validation.",
                        ]),
                        .callout(
                            "command-wheel-profiles-stability",
                            DocumentationCallout(
                                kind: .tip,
                                title: "Keep directions stable",
                                text: "Static slots keep their positions. Recent and Frequent providers resolve on every invocation and remain frozen while visible. History excludes arguments, so commands requiring non-defaulted input are skipped before the result limit."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-search",
                    title: "Add a launcher result",
                    blocks: [
                        .steps("command-wheel-search-steps", [
                            "Find a registered Commandly command or installed application in launcher search.",
                            "Open its contextual Actions and choose Add to Command Wheel….",
                            "Choose a profile, page, and slot. Occupied destinations are identified before replacement.",
                            "Add a second reference, move an existing assignment, remove it, place it in a new submenu, or reveal its slot in Command Wheel settings.",
                            "Confirm the change. Commandly preserves the command identifier and any serializable arguments rather than copying executable behavior.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-contexts",
                    title: "Choose profiles by application context",
                    blocks: [
                        .paragraph(
                            "command-wheel-contexts-overview",
                            "Context-aware selection takes one snapshot of the frontmost application when the shortcut is pressed. Enabled exact bundle-identifier rules are sorted by higher priority, profile order, rule order, and stable identifiers. If none matches, Commandly uses the enabled default profile."
                        ),
                        .bullets("command-wheel-contexts-rules", [
                            "A profile explicitly assigned to a shortcut remains explicit unless context override is enabled for that invocation.",
                            "Rules never continuously poll the frontmost application.",
                            "While presented, activation of another process cancels the session; Toggle mode ignores Commandly’s own intentional temporary activation.",
                            "Settings rejects enabled rules with the same normalized bundle identifier and priority.",
                            "Commandly does not ship hard-coded rules for third-party applications.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-transfer-accessibility",
                    title: "Import, export, and accessibility",
                    blocks: [
                        .bullets("command-wheel-transfer-accessibility-list", [
                            "Export one profile or all profiles as versioned JSON. Import validates the complete graph, remaps colliding identifiers, and reports missing command identifiers without deleting them.",
                            "Every actionable segment is one VoiceOver element with a stable label, state, hint, and testing identifier; decorative wedge shapes are hidden from accessibility.",
                            "Selection uses shape, icon, outline, and state—not color alone—and adapts to Increased Contrast and Reduce Transparency.",
                            "Reduce Motion or the profile animation preference replaces scale and movement with restrained opacity changes without changing selection timing.",
                        ]),
                        .callout(
                            "command-wheel-transfer-privacy",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Local, non-secret configuration",
                                text: "Profiles are stored as versioned JSON in Commandly’s Application Support container. Command Wheel observes the pointer, current display, one frontmost-app rule-selection snapshot, application-activation changes needed to cancel stale sessions, and its own shortcut events while active. It does not store pointer paths, window titles, file contents, clipboard contents, credentials, or full search history."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "command-wheel-troubleshooting",
                    title: "Troubleshooting",
                    blocks: [
                        .bullets("command-wheel-troubleshooting-list", [
                            "Wheel does not open: confirm the feature and profile are enabled, a valid shortcut is assigned, and Settings shows no shortcut conflict.",
                            "Release runs nothing: make sure the pointer crossed the dead zone toward an available segment. A fast release during preparation still uses its final pointer location; a visible highlight is not required.",
                            "A saved command is missing: re-enable or reinstall its registered command, or replace the reference in the editor. Commandly will not substitute another command.",
                            "Context profile is unexpected: check global context selection, exact bundle identifiers, priorities, and profile order.",
                            "Another application activates while the wheel is presented: Commandly cancels rather than execute against stale context; invoke the wheel again in the new application.",
                            "A display or Space changes while the wheel is open: Commandly cancels the active gesture rather than risk executing against stale geometry or context; invoke it again on the new display or Space.",
                            "Imported profiles fail: the file must be valid supported Command Wheel JSON and every submenu must form one rooted, acyclic tree.",
                        ]),
                    ]
                ),
            ],
            keywords: [
                "command wheel", "radial menu", "hold flick release", "dead zone", "toggle",
                "submenu", "profile", "context application", "global shortcut", "keyboard",
                "recent commands", "frequent commands", "import export", "reduce motion",
                "VoiceOver", "missing command", "search action",
            ]
        )
    )
}
