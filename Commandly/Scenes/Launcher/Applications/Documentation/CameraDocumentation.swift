import Foundation

extension RegisteredApplicationDocumentation {
    static let camera = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Check your camera preview or take a selfie. Camera access begins only when you choose Start Camera; the camera turns off before you review the photo.",
        sections: [
            DocumentationSection(id: "camera.workflow", title: "Preview and Take a Photo", blocks: [
                .steps("camera.workflow.steps", [
                    "Open Camera Preview or Take a Selfie. Both open the camera screen with the camera off.",
                    "Choose Start Camera. If needed, allow Commandly’s Camera request. No microphone access is requested.",
                    "Choose a connected camera when more than one is available. Mirror preview and photo changes both the preview and the captured pixels.",
                    "Choose Take Photo. The camera stops before the captured PNG is shown for review.",
                    "Choose Save Photo for a native save panel, Copy Photo for the system clipboard, Retake to start a new preview, or Discard to clear the photo."
                ]),
                .shortcuts("camera.workflow.keys", [
                    DocumentationShortcut(id: "camera.return", title: "Start, take, or save at the current step", keys: ["Return"]),
                    DocumentationShortcut(id: "camera.actions", title: "Open actions", keys: ["⌘", "K"]),
                    DocumentationShortcut(id: "camera.escape", title: "Stop active preview or cancel; otherwise go back", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "camera.privacy", title: "Privacy and Recovery", blocks: [
                .callout("camera.privacy.local", DocumentationCallout(kind: .privacy, title: "An explicit camera session", text: "The camera is never activated at application launch or when browsing tools. Live frames and the reviewed photo stay in memory and are never uploaded or logged. Stopping, leaving Camera, or dismissing the launcher releases the camera and clears the photo. Saving and copying are separate explicit actions.")),
                .bullets("camera.privacy.details", [
                    "Camera permission is used only for video input. Commandly creates no audio input and captures no microphone samples.",
                    "If access is denied, use Open Camera Settings to find Privacy & Security → Camera, enable Commandly, then try Start Camera again. Restricted access may require a Mac administrator.",
                    "Disconnecting a camera or a native interruption stops preview and presents a retry path. Close another camera app if this camera cannot start.",
                    "Preview frames are limited to 960 pixels per edge and at most 12 updates per second. Captured photos are normalized to sRGB PNG, limited to 4,096 pixels on the longest edge, and stripped of source metadata.",
                    "Copy Photo writes the ordinary system clipboard, including normal Clipboard History behavior when enabled. Nothing is written to a file until you choose a save location."
                ])
            ])
        ],
        keywords: ["camera", "preview", "webcam", "selfie", "photo", "mirror", "privacy", "permission"]
    )
}
