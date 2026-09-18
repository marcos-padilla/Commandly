import Foundation

extension OfflineToolKind {
    /// Exhaustive documentation contribution for every registered offline tool.
    var documentation: LauncherApplicationDocumentation {
        switch self {
        case .emoji:
            emojiDocumentation
        case .textCase:
            textCaseDocumentation
        case .color:
            colorDocumentation
        case .dictionary:
            dictionaryDocumentation
        case .fonts:
            fontsDocumentation
        case .typing:
            typingDocumentation
        }
    }

    private var emojiDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Search a curated local catalog of common Unicode emoji by English name, preview the selection, and copy it without a network or AI service.",
            sections: [
                DocumentationSection(
                    id: "emoji.search",
                    title: "Find and Copy Emoji",
                    blocks: [
                        .steps("emoji.search.steps", [
                            "Open Emoji Search and type an English Unicode name such as heart, face, warning, or rocket.",
                            "Use the arrow keys or pointer to select an emoji.",
                            "Press Return to copy the selected symbol."
                        ]),
                        .examples("emoji.search.examples", [
                            DocumentationExample(id: "emoji.search.heart", input: "heart", detail: "Matches common heart symbols in the local catalog."),
                            DocumentationExample(id: "emoji.search.rocket", input: "rocket", output: "🚀"),
                            DocumentationExample(id: "emoji.search.warning", input: "warning", output: "⚠️")
                        ]),
                        .shortcuts("emoji.search.shortcuts", [
                            DocumentationShortcut(id: "emoji.search.arrows", title: "Move selection", keys: ["↑", "↓"]),
                            DocumentationShortcut(id: "emoji.search.copy", title: "Copy emoji", keys: ["Return"]),
                            DocumentationShortcut(id: "emoji.search.actions", title: "Open actions", keys: ["⌘", "K"]),
                            DocumentationShortcut(id: "emoji.search.escape", title: "Clear search or go back", keys: ["Esc"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "emoji.scope",
                    title: "Catalog and Privacy",
                    blocks: [
                        .callout(
                            "emoji.scope.local",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Entirely local",
                                text: "Emoji names come from Unicode scalar metadata available on macOS. Searches and copied symbols are not uploaded."
                            )
                        ),
                        .callout(
                            "emoji.scope.limit",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Curated catalog",
                                text: "The catalog contains more than 200 common emoji. It is not a complete emoji-standard browser and does not perform semantic or AI search."
                            )
                        )
                    ]
                )
            ],
            keywords: ["Unicode", "symbol", "reaction", "heart", "smile", "copy", "offline"]
        )
    }

    private var textCaseDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Transform text between nine deterministic naming and capitalization styles, preview the result immediately, and copy it locally.",
            sections: [
                DocumentationSection(
                    id: "text-case.convert",
                    title: "Convert Text",
                    blocks: [
                        .steps("text-case.convert.steps", [
                            "Open Convert Text Case and enter text in the Input editor.",
                            "Choose UPPERCASE, lowercase, Title Case, Sentence case, camelCase, PascalCase, snake_case, kebab-case, or CONSTANT_CASE.",
                            "Review the live converted output and choose Copy Converted Text in the footer."
                        ]),
                        .examples("text-case.convert.examples", [
                            DocumentationExample(id: "text-case.convert.camel", input: "commandly productivity launcher", output: "commandlyProductivityLauncher"),
                            DocumentationExample(id: "text-case.convert.pascal", input: "commandly_productivity-launcher", output: "CommandlyProductivityLauncher"),
                            DocumentationExample(id: "text-case.convert.snake", input: "CommandlyProductivityLauncher", output: "commandly_productivity_launcher"),
                            DocumentationExample(id: "text-case.convert.kebab", input: "Quick Note Title", output: "quick-note-title"),
                            DocumentationExample(id: "text-case.convert.constant", input: "completion sound", output: "COMPLETION_SOUND")
                        ]),
                        .shortcuts("text-case.convert.shortcuts", [
                            DocumentationShortcut(id: "text-case.convert.actions", title: "Open actions", keys: ["⌘", "K"]),
                            DocumentationShortcut(id: "text-case.convert.escape", title: "Clear input or go back", keys: ["Esc"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "text-case.privacy",
                    title: "Local Transformation",
                    blocks: [
                        .callout(
                            "text-case.privacy.local",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "No upload",
                                text: "Conversion is a deterministic in-process text operation. Input is not sent to a model, translation service, or network endpoint."
                            )
                        )
                    ]
                )
            ],
            keywords: ["uppercase", "lowercase", "title", "sentence", "camel", "Pascal", "snake", "kebab", "constant"]
        )
    }

    private var colorDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Preview a HEX, RGB, or HSL color and copy it in six formats. Enter a color directly in the root launcher or use Color Tools, with optional explicit sampling through the native macOS picker.",
            sections: [
                DocumentationSection(
                    id: "color.convert",
                    title: "Enter and Convert a Color",
                    blocks: [
                        .bullets("color.convert.formats", [
                            "Accepted HEX forms: #RGB, #RGBA, #RRGGBB, and #RRGGBBAA.",
                            "Accepts comma-separated RGB/HSL and modern space-separated forms, with optional slash alpha, percentages, and hue units deg, grad, rad, or turn.",
                            "Choose Hex, Hex with Alpha, RGBA, RGBA (Percentage), RGB (CSS4), or HSL. Return copies the selected format.",
                            "Transparency is preserved in every format except six-digit Hex; transparent inputs initially select Hex with Alpha.",
                            "Input is limited to 256 UTF-8 bytes. Named colors, CSS calculations, and wide-gamut spaces are not supported."
                        ]),
                        .examples("color.convert.examples", [
                            DocumentationExample(id: "color.convert.red-hex", input: "#FF0000", output: "rgba(255, 0, 0, 1) · hsl(0 100% 50% / 1)"),
                            DocumentationExample(id: "color.convert.short-hex", input: "#4AF", output: "#44AAFF"),
                            DocumentationExample(id: "color.convert.alpha", input: "rgba(74, 125, 255, 0.5)", output: "#4A7DFF80")
                        ]),
                        .shortcuts("color.convert.shortcuts", [
                            DocumentationShortcut(id: "color.convert.return", title: "Copy selected format", keys: ["Return"]),
                            DocumentationShortcut(id: "color.convert.actions", title: "Open all six format actions", keys: ["⌘", "K"]),
                            DocumentationShortcut(id: "color.convert.formats", title: "Copy format 1 through 6", keys: ["⌘", "1…6"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "color.sample",
                    title: "Pick from the Screen",
                    blocks: [
                        .steps("color.sample.steps", [
                            "Inside Color Tools, press Command-K and choose Pick Screen Color, or use Pick from Screen to place a sampled value in the editor.",
                            "To copy immediately without opening Color Tools, run the separate Pick Screen Color tool from the launcher or assign that tool a global shortcut in Settings → Applications.",
                            "Use the system-controlled macOS sampler to choose a visible pixel.",
                            "The focused tool copies the sampled HEX value to the clipboard; the in-application action places it in the editor for conversion or copying."
                        ]),
                        .callout(
                            "color.sample.privacy",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "System-controlled sampling",
                                text: "The native color sampler runs only after you request it. Commandly does not start a general screen recording, retain an image of the screen, or upload sampled pixels."
                            )
                        ),
                        .callout(
                            "color.sample.limit",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Supported color spaces",
                                text: "Outputs use bounded sRGB. Hex rounds to bytes; functional outputs use up to six decimal places. The tool does not parse every CSS color space or evaluate stylesheets."
                            )
                        )
                    ]
                )
            ],
            keywords: ["picker", "eyedropper", "HEX", "RGB", "RGBA", "HSL", "screen color"]
        )
    }

    private var dictionaryDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Look up a word in the dictionaries installed on this Mac and copy the local definition without a web request or account.",
            sections: [
                DocumentationSection(
                    id: "dictionary.lookup",
                    title: "Look Up a Definition",
                    blocks: [
                        .steps("dictionary.lookup.steps", [
                            "Open Dictionary and enter a word.",
                            "Press Return to query the local macOS Dictionary Services API.",
                            "Select the returned text if needed, or use Copy Definition in the action menu."
                        ]),
                        .examples("dictionary.lookup.examples", [
                            DocumentationExample(id: "dictionary.lookup.serendipity", input: "serendipity", detail: "The exact result depends on dictionaries installed and enabled in macOS."),
                            DocumentationExample(id: "dictionary.lookup.launcher", input: "launcher", detail: "If no local dictionary contains a result, Commandly reports that no local definition was found.")
                        ]),
                        .shortcuts("dictionary.lookup.shortcuts", [
                            DocumentationShortcut(id: "dictionary.lookup.return", title: "Look up word", keys: ["Return"]),
                            DocumentationShortcut(id: "dictionary.lookup.actions", title: "Open actions", keys: ["⌘", "K"]),
                            DocumentationShortcut(id: "dictionary.lookup.escape", title: "Clear the word or go back", keys: ["Esc"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "dictionary.scope",
                    title: "Sources and Limits",
                    blocks: [
                        .callout(
                            "dictionary.scope.local",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Installed dictionaries only",
                                text: "Words are resolved locally through dictionaries installed in macOS. Commandly does not send the query to a web service."
                            )
                        ),
                        .callout(
                            "dictionary.scope.limit",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "No web fallback or translation",
                                text: "Results vary with your installed dictionaries. This application does not translate words, download dictionaries, or fall back to the web."
                            )
                        )
                    ]
                )
            ],
            keywords: ["definition", "meaning", "word", "spell", "Dictionary Services", "offline"]
        )
    }

    private var fontsDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Browse and filter font families available on this Mac, preview representative characters in the selected family, and copy its family name.",
            sections: [
                DocumentationSection(
                    id: "fonts.browse",
                    title: "Find and Preview Fonts",
                    blocks: [
                        .steps("fonts.browse.steps", [
                            "Open Search Fonts and type part of an installed font-family name.",
                            "Use the arrow keys or pointer to select a family.",
                            "Review the pangram, uppercase and lowercase letters, and digits rendered in that family.",
                            "Press Return to copy the exact family name."
                        ]),
                        .shortcuts("fonts.browse.shortcuts", [
                            DocumentationShortcut(id: "fonts.browse.arrows", title: "Move selection", keys: ["↑", "↓"]),
                            DocumentationShortcut(id: "fonts.browse.copy", title: "Copy font-family name", keys: ["Return"]),
                            DocumentationShortcut(id: "fonts.browse.actions", title: "Open actions", keys: ["⌘", "K"]),
                            DocumentationShortcut(id: "fonts.browse.escape", title: "Clear search or go back", keys: ["Esc"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "fonts.scope",
                    title: "Font Catalog Scope",
                    blocks: [
                        .callout(
                            "fonts.scope.local",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Native catalog",
                                text: "Font families come from the local macOS font catalog. Search terms and font names are not sent to a service."
                            )
                        ),
                        .callout(
                            "fonts.scope.limit",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Browsing only",
                                text: "Search Fonts does not install, download, activate, deactivate, manage, or sync fonts."
                            )
                        )
                    ]
                )
            ],
            keywords: ["typeface", "typography", "font family", "preview", "installed", "copy"]
        )
    }

    private var typingDocumentation: LauncherApplicationDocumentation {
        LauncherApplicationDocumentation(
            category: .utilities,
            overview: "Practice a fixed local passage and receive an immediate estimate of words per minute and character-position accuracy, without accounts, uploads, or saved scores.",
            sections: [
                DocumentationSection(
                    id: "typing.attempt",
                    title: "Complete an Attempt",
                    blocks: [
                        .steps("typing.attempt.steps", [
                            "Open Typing Practice and read the displayed passage.",
                            "Reproduce the passage in the editor. Timing begins with your first typed character.",
                            "Watch estimated words per minute and character-position accuracy update as you type.",
                            "When the passage matches, the attempt is marked complete. Choose New Attempt to reset."
                        ]),
                        .examples("typing.attempt.prompt", [
                            DocumentationExample(
                                id: "typing.attempt.fixed-passage",
                                input: "Small, deliberate steps turn ambitious ideas into dependable tools.",
                                detail: "The current practice passage is fixed and stored locally."
                            )
                        ]),
                        .shortcuts("typing.attempt.shortcuts", [
                            DocumentationShortcut(id: "typing.attempt.escape", title: "Reset typed text or go back", keys: ["Esc"])
                        ])
                    ]
                ),
                DocumentationSection(
                    id: "typing.results",
                    title: "How Results Work",
                    blocks: [
                        .bullets("typing.results.metrics", [
                            "Words per minute uses the conventional five typed characters per word divided by elapsed minutes.",
                            "Accuracy compares typed characters with the expected character at each position.",
                            "Extra, missing, or different-position characters reduce the accuracy percentage."
                        ]),
                        .callout(
                            "typing.results.privacy",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "No profile or history",
                                text: "Typed text, timing, accuracy, and scores stay in the current attempt. Commandly does not create an account, save a history, or upload results."
                            )
                        )
                    ]
                )
            ],
            keywords: ["WPM", "accuracy", "practice", "keyboard", "passage", "speed", "offline"]
        )
    }
}
