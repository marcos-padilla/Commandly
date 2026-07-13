enum AccessibilityDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.accessibility",
        title: "Accessibility & Keyboard Use",
        subtitle: "Use Commandly with keyboard navigation, VoiceOver labels, and adaptable presentation.",
        systemImage: "accessibility",
        category: .settingsAndPrivacy,
        order: 320,
        documentation: LauncherApplicationDocumentation(
            category: .settingsAndPrivacy,
            overview: "Commandly is designed around full keyboard operation and provides accessibility labels, values, hints, header traits, and selection state across its current launcher and application surfaces.",
            sections: [
                DocumentationSection(
                    id: "accessibility-keyboard",
                    title: "Keyboard-first operation",
                    blocks: [
                        .bullets("accessibility-keyboard-list", [
                            "The launcher search field reclaims focus each time Commandly is presented, so you can begin typing immediately.",
                            "Up and Down Arrow move through result lists and standard browser-style application lists.",
                            "Return runs the primary action for the current selection.",
                            "Command–K opens an available actions panel.",
                            "Escape closes the innermost panel, clears a query, goes back, or hides the launcher in that order.",
                            "Tab accepts a visible launcher or calculator autocomplete suggestion.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "accessibility-voiceover",
                    title: "VoiceOver information",
                    blocks: [
                        .bullets("accessibility-voiceover-list", [
                            "The launcher, search fields, footers, actions panels, option menus, result selections, and current application surfaces expose descriptive accessibility labels.",
                            "Calculator question, answer, and actions controls are separate focusable elements with distinct labels and hints.",
                            "Selection is exposed as state and not communicated by color alone.",
                            "Decorative imagery is hidden from accessibility when surrounding text already conveys its meaning.",
                            "Destructive and permission actions use descriptive text in addition to icons and color.",
                        ]),
                        .callout(
                            "accessibility-voiceover-review",
                            DocumentationCallout(
                                kind: .important,
                                title: "Ongoing review",
                                text: "Accessibility review is part of Commandly’s definition of done. A label in code is not a substitute for testing a complete workflow with VoiceOver."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "accessibility-presentation",
                    title: "Adapt the presentation",
                    blocks: [
                        .steps("accessibility-presentation-steps", [
                            "Open Settings with Command–Comma and choose General.",
                            "Choose Default or Larger under Text Size. Larger scales Commandly typography and pairs it with a larger Dynamic Type bucket.",
                            "Choose Comfortable or Compact under View Mode to change launcher height, spacing, row padding, and related layout density.",
                            "Choose System, Light, or Dark under Appearance.",
                        ]),
                        .paragraph(
                            "accessibility-presentation-colors",
                            "Commandly uses semantic macOS colors and adaptive materials so text and controls respond to light and dark appearances. Meaningful states include text or symbols rather than relying on color alone."
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "accessibility-permission-distinction",
                    title: "Accessibility permission is different",
                    blocks: [
                        .paragraph(
                            "accessibility-permission-distinction-summary",
                            "The macOS Accessibility privacy permission is used for controlling another application’s window when you apply a Window Layout. It is not required for VoiceOver labels, launcher keyboard navigation, the Option–Space hotkey, or user-assigned global application hotkeys."
                        ),
                    ]
                ),
            ],
            keywords: [
                "accessibility", "VoiceOver", "keyboard", "focus", "labels", "Dynamic Type",
                "larger text", "view mode", "compact", "appearance", "light", "dark",
                "Accessibility permission",
            ]
        )
    )
}
