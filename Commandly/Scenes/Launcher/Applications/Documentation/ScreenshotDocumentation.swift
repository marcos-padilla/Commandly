import Foundation

extension RegisteredApplicationDocumentation {
    static let screenshot = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Capture one chosen region, window, or display, then review its PNG before copying or saving. Screenshot never records continuously or sends images to AI or a network service.",
        sections: [
            DocumentationSection(id: "screenshot.workflow", title: "Select and Review", blocks: [
                .steps("screenshot.workflow.steps", [
                    "Open Screenshot or a dedicated Region, Window, or Display tool. Opening the screen does not select or capture anything.",
                    "Choose a selection type and whether to include the pointer, then choose Choose and Capture.",
                    "For Window or Display, use the macOS picker. Only the content you choose is shared; no separate full Screen Recording grant is needed.",
                    "For Region, allow Screen Recording access when requested, then drag an area and release to capture. Arrow keys create or move a selection, Shift and arrows resize it, Return captures, and Escape cancels.",
                    "Review the image, then choose Copy Screenshot, Save, or Open in CleanShot X. New Screenshot and the Discard action clear the current image."
                ]),
                .shortcuts("screenshot.workflow.keys", [
                    DocumentationShortcut(id: "screenshot.return", title: "Choose content or copy the reviewed image", keys: ["Return"]),
                    DocumentationShortcut(id: "screenshot.actions", title: "Open actions", keys: ["⌘", "K"]),
                    DocumentationShortcut(id: "screenshot.cancel", title: "Cancel selection or go back", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "screenshot.cleanshot", title: "Annotate in CleanShot X", blocks: [
                .paragraph("screenshot.cleanshot.intro", "Open in CleanShot X sends the reviewed PNG to CleanShot’s local annotation editor. CleanShot X 3.8.1 or later must already be installed and registered as the CleanShot link handler. Commandly never installs or substitutes another editor."),
                .bullets("screenshot.cleanshot.details", [
                    "Choose Open in CleanShot X only after reviewing the image. Finish editing, copying, or saving inside CleanShot; Commandly does not import edits or request an upload.",
                    "The handoff uses a private temporary PNG. Its ten-minute deadline continues after the launcher closes while Commandly runs. If Commandly quits or the Mac is asleep, cleanup resumes on a later explicit handoff or when the app can run again. CleanShot controls any copy or history it retains.",
                    "Cancelling before dispatch prevents the handoff. After dispatch, cancelling Commandly cannot retract the recipient’s copy; the temporary file stays available until its deadline so CleanShot can finish reading it.",
                    "If unavailable or outdated, open or update your installed CleanShot X and retry. Review any API access prompt in CleanShot itself. You can also Save the screenshot and open it from CleanShot’s editor yourself."
                ])
            ]),
            DocumentationSection(id: "screenshot.privacy", title: "Privacy, Limits, and Recovery", blocks: [
                .callout("screenshot.privacy.local", DocumentationCallout(kind: .privacy, title: "Review before sharing", text: "Pixels stay in memory for this launcher session. There is no automatic clipboard write, saved file, recording, upload, or AI request. Copy, Save, and the optional CleanShot handoff are explicit actions. Leaving this screen clears the in-memory screenshot and cancels pending selection; a dispatched CleanShot temporary file follows its separate ten-minute deadline.")),
                .bullets("screenshot.privacy.details", [
                    "Region capture uses Privacy & Security → Screen & System Audio Recording. If denied, use Open Screen Recording Settings, enable Commandly, then retry. Window and Display continue to use the system picker’s scoped selection.",
                    "The launcher is temporarily hidden from capture and restored for review. A display layout change cancels an active region selection. A region spanning displays uses the highest intersecting pixel scale; uncovered gaps follow the system screenshot output.",
                    "Output is limited to 8,192 pixels per edge, 40 megapixels, and 160 MiB. Large selections are scaled down keeping proportions. Review previews are limited to 1,280 pixels on their longest edge.",
                    "Images are rendered to standard sRGB PNG with source metadata removed. Window capture excludes framing shadows and child windows. Protected or closed content may be unavailable.",
                    "The artifact retains only PNG bytes, dimensions, source category, and an ephemeral ID. It carries no window title, display identity, source coordinates, or authority to capture again.",
                    "Copy Screenshot writes the ordinary system clipboard, including normal Clipboard History behavior when enabled. Save writes only through the native file panel."
                ])
            ])
        ], keywords: ["screenshot", "capture", "region", "window", "display", "screen recording", "privacy", "PNG", "CleanShot", "annotate"]
    )
}
