import Foundation

extension RegisteredApplicationDocumentation {
    static let gifSearch = LauncherApplicationDocumentation(category: .productivity,
        overview: "Search GIPHY's animated reaction catalog using your own API key. Preview a GIF, then explicitly copy its animation bytes or save a .gif file. GIFs remain attributed to GIPHY and their creator/source.",
        sections: [
            DocumentationSection(id: "gif.setup", title: "Connect GIPHY", blocks: [
                .steps("gif.setup.steps", [
                    "Open Connection and follow the GIPHY Developer Dashboard link. Obtain your own API key for this macOS integration; Commandly does not create an account or accept terms for you.",
                    "Paste the key into the secure field and Save Key. It is stored only in Keychain. A search checks API access; saving the key makes no provider request.",
                    "Beta keys currently allow 100 API calls per hour. GIPHY manages production access and pricing. A rejected key or rate limit produces a recoverable message.",
                    "Use Remove Saved Key to disconnect. Changing or removing the key cancels pending operations and clears result and preview buffers. Refresh reloads the saved connection state."
                ])
            ]),
            DocumentationSection(id: "gif.search", title: "Find and Preview", blocks: [
                .paragraph("gif.search.words", "Enter up to 50 characters and press Return or choose Search. The exact phrase is sent directly to GIPHY only when submitted. Trending is a separate explicit request. Maximum Rating is applied by GIPHY's API. Results preserve provider order; Previous and Next request pages of up to 24 items."),
                .paragraph("gif.search.preview", "Use arrow keys to select a result. Its animated preview loads directly from GIPHY. Pause freezes the preview; Reduce Motion shows a still frame. The selected title, creator, and available source attribution remain visible. Large or unsupported previews show a limit message while leaving original Copy/Save available. Changing selection releases the prior animation.")
            ]),
            DocumentationSection(id: "gif.export", title: "Copy or Save Animation", blocks: [
                .paragraph("gif.export.copy", "Return after completed search or Command–Shift–C copies the selected original GIF bytes. Save GIF opens the native Save panel and writes to your chosen file. Copy and Save download the original animation for that action and do not substitute a static preview, URL, or converted movie. The original is limited to 32 MiB and 1,000 frames; previews are limited to 8 MiB, 400 frames, and 48 MiB of decoded pixels. Some destination apps only paste still images; use the saved .gif file in those apps."),
                .callout("gif.export.privacy", DocumentationCallout(kind: .privacy, title: "Explicit remote search", text: "GIPHY receives submitted search terms, the API key for API requests, and ordinary network metadata such as your IP address. This feature stores no search history, media cache, cookies, or analytics identifiers. Results and selected previews remain only in the current session. Explicit copies may enter Clipboard History if you enabled it, and exported GIFs remain where you saved them."))
            ])
        ], keywords: ["gif", "animated", "giphy", "API key", "copy", "download", "save", "attribution", "privacy"])
}
