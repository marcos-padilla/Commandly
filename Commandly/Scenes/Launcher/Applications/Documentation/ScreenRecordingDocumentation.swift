import Foundation

extension RegisteredApplicationDocumentation {
    static let screenRecording = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Record one explicitly selected window or display in a separate Commandly window. Stop into local video review, then save only where you choose. Audio is off by default and the microphone is never captured.",
        sections: [
            DocumentationSection(id: "recording.workflow", title: "Record and Review", blocks: [
                .steps("recording.workflow.steps", [
                    "Open Screen Recording, Record a Window, or Record a Display. Opening the controls does not start capture or request permission.",
                    "Choose window or display, audio off or system audio, MP4 or MOV, H.264 or HEVC, and a maximum of 1080p or 720p. Choose whether to include the pointer.",
                    "Choose Choose & Record, then share the content using the macOS picker. The recording controls show elapsed time, size, and the active audio setting.",
                    "Choose Stop & Review, or run Stop Screen Recording from the launcher or an assigned shortcut. Wait for the native video to finish before reviewing it.",
                    "Play the video if you want to check it, then choose Save Video. Cancelling Save keeps the review. Discard removes its temporary copy."
                ]),
                .shortcuts("recording.workflow.keys", [
                    DocumentationShortcut(id: "recording.return", title: "Start, Stop & Review, or Save Video", keys: ["Return"]),
                    DocumentationShortcut(id: "recording.save", title: "Save the reviewed video", keys: ["⌘", "S"]),
                    DocumentationShortcut(id: "recording.close", title: "Close safely; active recording stops into review", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "recording.privacy", title: "Selection, Audio, and Storage", blocks: [
                .callout("recording.privacy.local", DocumentationCallout(kind: .privacy, title: "Local until you save", text: "Recording uses the exact window or display selected in the macOS picker. No screen enumeration, background capture, microphone access, clipboard write, upload, or AI request is performed. A display recording includes everything visible there, including Commandly's movable controls.")),
                .bullets("recording.privacy.details", [
                    "The independent recording window stays visible when the launcher closes. Closing or quitting during capture stops into review. Keeping the review open cancels quitting and never resumes recording.",
                    "System audio is optional and excludes audio from Commandly itself. It does not enable the microphone. The selected audio setting is shown both before and during recording.",
                    "Output fits within 1920×1080 or 1280×720, preserves proportions, and uses 30 fps. Recording stops at 10 minutes or near 384 MiB, with a finalized-video limit of 512 MiB. Native buffering can write beyond the early stop threshold; this is not an exact write cap.",
                    "At least 768 MiB of available storage is required before recording. One private temporary recording is retained per recorder. Saving atomically replaces a chosen destination only after the complete video has copied.",
                    "If macOS cannot confirm Stop, controls remain active with Retry Stop. You can also stop sharing from the macOS recording indicator. The temporary output cannot be exported or deleted while capture might continue.",
                    "Private temporary files are removed by Discard and normal close. After a crash or forced quit, abandoned files are cleaned on the next explicit recording start; another active Commandly process's output is protected by an ownership lock.",
                    "The system picker grants access to the selected content. If denied or restricted, choose again and approve sharing, or review Privacy & Security → Screen & System Audio Recording in System Settings. Protected or unavailable content may not be recordable."
                ])
            ])
        ], keywords: ["screen recording", "record", "video", "screencast", "MP4", "MOV", "H.264", "HEVC", "audio", "privacy"]
    )
}
