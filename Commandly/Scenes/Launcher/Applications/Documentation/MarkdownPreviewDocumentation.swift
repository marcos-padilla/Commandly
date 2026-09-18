import Foundation

extension RegisteredApplicationDocumentation {
    static let markdownPreview = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Read Markdown in Commandly or Finder with a private local renderer, an outline, source view, live reload, search, and explicit HTML or PDF export.",
        sections: [
            DocumentationSection(
                id: "markdown-preview.open",
                title: "Open and Read",
                blocks: [
                    .bullets("markdown-preview.open.tools", [
                        "Open Markdown Preview opens the local reader without selecting a document.",
                        "Choose Markdown File is a focused launcher tool that opens the same reader and presents its native supported-document picker. It does not read a file until you choose one."
                    ]),
                    .steps("markdown-preview.open.steps", [
                        "Open Markdown Preview from the launcher.",
                        "Choose a supported Markdown file or drop one onto the viewer.",
                        "Use the outline, in-document search, zoom, or escaped source view while reading.",
                        "Leave automatic reload enabled to follow changes saved by another editor."
                    ]),
                    .shortcuts("markdown-preview.open.shortcuts", [
                        DocumentationShortcut(
                            id: "markdown-preview.open.choose",
                            title: "Choose a document when empty",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "markdown-preview.open.reload",
                            title: "Reload the active document",
                            keys: ["⌘", "R"]
                        ),
                        DocumentationShortcut(
                            id: "markdown-preview.open.search",
                            title: "Search inside the preview",
                            keys: ["⌘", "F"]
                        ),
                        DocumentationShortcut(
                            id: "markdown-preview.open.source",
                            title: "Switch between rendered preview and source",
                            keys: ["⇧", "⌘", "M"]
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "markdown-preview.rendering",
                title: "Rendering and Formats",
                blocks: [
                    .bullets("markdown-preview.rendering.features", [
                        "Render headings, lists, links, local images, fenced code, tables, tasks, strikethrough, alerts, front matter, footnotes, emoji shortcodes, and right-to-left documents.",
                        "Preview Markdown variants including MDX, R Markdown, Quarto, Markdoc, MDC, Mermaid source, and Livebook as text without executing JSX, chunks, directives, or notebook code.",
                        "Math and diagram blocks use Commandly's dependency-free local representations and always preserve their source when the full external language is not supported.",
                        "Raw document HTML and scripts are escaped, and implicit remote resources are blocked."
                    ]),
                    .callout(
                        "markdown-preview.rendering.compatibility",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Advanced language compatibility",
                            text: "Commandly does not bundle the complete Mermaid, KaTeX, Typst, Vega, or Graphviz engines. Complex or malformed constructs remain visible as a safe source fallback instead of being downloaded or executed."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "markdown-preview.finder",
                title: "Finder Quick Look",
                blocks: [
                    .steps("markdown-preview.finder.steps", [
                        "Install a signed Commandly build that contains the Markdown Quick Look extension.",
                        "Enable the extension in System Settings under Login Items & Extensions, then Quick Look.",
                        "Select a supported file in Finder and press Space, or open Finder's preview pane."
                    ]),
                    .callout(
                        "markdown-preview.finder.registration",
                        DocumentationCallout(
                            kind: .important,
                            title: "macOS controls preview providers",
                            text: "Finder chooses among installed extensions for each file type. Reinstalling, changing the enablement switch, or another Markdown provider can change which preview appears."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "markdown-preview.export",
                title: "Export",
                blocks: [
                    .bullets("markdown-preview.export.options", [
                        "Export self-contained sanitized HTML with allowed local images embedded as data.",
                        "Export the rendered WebKit document as PDF to a location you choose.",
                        "Finder Quick Look remains read-only and exposes no export or print action."
                    ]),
                    .shortcuts("markdown-preview.export.shortcuts", [
                        DocumentationShortcut(
                            id: "markdown-preview.export.html",
                            title: "Export HTML",
                            keys: ["⇧", "⌘", "E"]
                        ),
                        DocumentationShortcut(
                            id: "markdown-preview.export.pdf",
                            title: "Export PDF",
                            keys: ["⇧", "⌘", "P"]
                        ),
                        DocumentationShortcut(
                            id: "markdown-preview.export.zoom",
                            title: "Zoom in, out, or reset",
                            keys: ["⌘+", "⌘−", "⌘0"]
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "markdown-preview.privacy",
                title: "Privacy and Safety",
                blocks: [
                    .callout(
                        "markdown-preview.privacy.local",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Local and private",
                            text: "Markdown text, rendered HTML, images, paths, links, search queries, and outlines are not logged or uploaded. Shared Quick Look preferences contain only declared non-secret rendering options."
                        )
                    ),
                    .bullets("markdown-preview.privacy.resources", [
                        "Local images must stay beneath the selected document directory and pass count, type, per-file, and total-byte limits.",
                        "Traversal, absolute paths, encoded traversal, and symlink escape are rejected.",
                        "The Quick Look extension is sandboxed, read-only, and has no ambient network, Downloads, shell, process, AI, or clipboard authority."
                    ])
                ]
            )
        ],
        keywords: [
            "Markdown", "Quick Look", "Finder", "preview", "GFM", "front matter", "outline",
            "source", "HTML", "PDF", "Mermaid", "math", "diagram", "local", "private"
        ]
    )
}
