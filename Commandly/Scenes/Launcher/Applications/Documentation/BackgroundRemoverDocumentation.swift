import Foundation

extension RegisteredApplicationDocumentation {
    static let backgroundRemover = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Remove an image background with Apple's on-device foreground segmentation and save the result as a transparent PNG without uploading the image.",
        sections: [
            DocumentationSection(
                id: "background-remover.create",
                title: "Create a Transparent Image",
                blocks: [
                    .bullets("background-remover.create.tools", [
                        "Open Background Remover opens its empty application surface so you can choose or drop an image.",
                        "Choose Image is a focused launcher tool that opens the same application and presents its native single-image picker. Commandly does not choose a file for you, and exporting the processed PNG remains a separate explicit action."
                    ]),
                    .steps("background-remover.create.steps", [
                        "Open Background Remover from the launcher.",
                        "Choose an image or drag one onto the application surface.",
                        "Review the original and transparent previews.",
                        "Choose Save PNG and select a destination."
                    ]),
                    .shortcuts("background-remover.create.shortcuts", [
                        DocumentationShortcut(
                            id: "background-remover.create.return",
                            title: "Choose an image or save the completed PNG",
                            keys: ["Return"]
                        ),
                        DocumentationShortcut(
                            id: "background-remover.create.actions",
                            title: "Open actions after processing",
                            keys: ["⌘", "K"]
                        ),
                        DocumentationShortcut(
                            id: "background-remover.create.escape",
                            title: "Cancel active processing or go back",
                            keys: ["Esc"]
                        )
                    ])
                ]
            ),
            DocumentationSection(
                id: "background-remover.privacy",
                title: "Privacy and Results",
                blocks: [
                    .callout(
                        "background-remover.privacy.local",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Processed on this Mac",
                            text: "The selected image, foreground mask, and transparent result stay in memory for the active launcher session. Commandly does not upload or log them."
                        )
                    ),
                    .callout(
                        "background-remover.privacy.limits",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Foreground quality varies",
                            text: "Busy scenes, reflections, fine hair, transparent objects, and low-contrast edges can produce imperfect cutouts. Try an image with a clearly separated subject when no foreground is detected."
                        )
                    )
                ]
            )
        ],
        keywords: ["image", "photo", "background", "transparent", "PNG", "cutout", "on-device AI"]
    )
}
