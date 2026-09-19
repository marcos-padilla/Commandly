import Foundation

/// Authored documentation for the Screen Tools application.
extension RegisteredApplicationDocumentation {
    static let screenTools = LauncherApplicationDocumentation(
        category: .productivity,
        overview: """
        Select any area of the screen and copy the text recognized in it, or sample a pixel's \
        color and copy it in the format you prefer.
        """,
        sections: [
            DocumentationSection(
                id: "screen.tools.usage",
                title: "Copy Text and Pick Colors",
                blocks: [
                    .steps("screen.tools.steps", [
                        "Run Copy Text From Screen and drag to select an area.",
                        "The recognized text is copied, ready to paste.",
                        "Run Pick Color From Screen and click any pixel to copy its color.",
                        "Choose the color format and line joining in Settings → Applications.",
                        "Assign either tool a global shortcut for one-key access."
                    ]),
                    .callout("screen.tools.privacy", DocumentationCallout(
                        kind: .privacy,
                        title: "Recognition happens on this Mac",
                        text: """
                        Text is recognized locally and written only to your clipboard. Nothing \
                        captured is uploaded, and the recognized text is never included in a \
                        command result.
                        """
                    )),
                    .callout("screen.tools.permission", DocumentationCallout(
                        kind: .permission,
                        title: "Screen Recording for text only",
                        text: """
                        Selecting an area needs Screen Recording permission. The color picker uses \
                        the system sampler and needs no permission, because you point at the pixel.
                        """
                    ))
                ]
            )
        ],
        keywords: ["screen", "ocr", "copy text", "color picker", "eyedropper", "hex", "rgb"]
    )
}
