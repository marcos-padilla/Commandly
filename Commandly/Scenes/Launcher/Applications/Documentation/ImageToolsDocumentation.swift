import Foundation

extension RegisteredApplicationDocumentation {
    static let imageTools = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Convert, resize, or rotate one still image, extract editable text, or decode QR contents. Image processing uses native frameworks on this Mac.",
        sections: [
            DocumentationSection(id: "image-tools.workflow", title: "Convert an Image", blocks: [
                .steps("image-tools.workflow.steps", [
                    "Open Image Tools, then choose or drop one image. Choose Image to Convert opens the native picker directly.",
                    "Choose an output format. Only formats with an available native encoder are listed.",
                    "Optionally enable Resize and enter the longest edge in pixels. The other edge adjusts to keep the image's proportions. Rotate 90° turns it clockwise.",
                    "Choose Convert Image and compare the original and output previews. Changing any setting clears the previous output until you convert again.",
                    "Choose Save Image and select a destination in the native save panel. Commandly never overwrites the source automatically."
                ]),
                .shortcuts("image-tools.workflow.keys", [
                    DocumentationShortcut(id: "image-tools.return", title: "Choose, convert, or save at the current step", keys: ["Return"]),
                    DocumentationShortcut(id: "image-tools.actions", title: "Open actions", keys: ["⌘", "K"]),
                    DocumentationShortcut(id: "image-tools.cancel", title: "Cancel active processing or go back", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "image-tools.recognition", title: "Extract Text and Decode QR", blocks: [
                .steps("image-tools.recognition.steps", [
                    "Choose Extract Text or Decode QR in Image Tools. Their dedicated launcher tools open the image picker directly.",
                    "Choose or drop one image. Recognition starts on this Mac. Switching tools reuses the selected image and clears the previous recognition results.",
                    "For text, review and edit the result before choosing Copy Text. Check names, numbers, and reading order because recognition can make mistakes.",
                    "For QR codes, select a result and choose Copy QR Content to copy its exact text. Wi-Fi, contact, file, and application payloads never run automatically.",
                    "A valid HTTP or HTTPS QR payload offers Review Link. Check the full address and hostname, then explicitly choose Open Link to send it to the default browser. Cancel keeps it local."
                ]),
                .bullets("image-tools.recognition.limits", [
                    "Vision reads an orientation-corrected image limited to 4,096 pixels on the longest edge. Use a sharper image or closer crop for small text and dense QR codes.",
                    "OCR results and edits are limited to 64,000 characters. QR output is limited to 32 distinct text payloads, 4,096 characters each, and 64,000 characters total. A notice identifies omitted results; QR contents are never partly copied as if they were complete.",
                    "Binary-only QR contents are reported but cannot be copied as readable text. Only standard QR codes are decoded; other barcode formats are outside this tool.",
                    "Recognition never reads your clipboard. Copy is explicit and uses the ordinary system clipboard, including normal Clipboard History behavior if enabled."
                ])
            ]),
            DocumentationSection(id: "image-tools.privacy", title: "Privacy and Limits", blocks: [
                .callout("image-tools.privacy.local", DocumentationCallout(kind: .privacy, title: "Private by default", text: "Source bytes and recognition results stay in memory for the launcher session. Processing uploads or logs nothing. Copying text and opening a reviewed web link occur only when requested. Exports contain newly rendered pixels with source metadata removed; a fresh color profile may be included for consistent display.")),
                .bullets("image-tools.privacy.limits", [
                    "Still images only. Animated and multi-page images are rejected rather than silently losing frames.",
                    "Input is limited to 64 MB, 40 megapixels, and 16,384 pixels per side. Output is limited to 40 megapixels, 16,384 pixels per side, and 192 MB.",
                    "PNG and TIFF retain transparency. JPEG and HEIC place transparent areas on white and use high-quality lossy compression.",
                    "Image orientation is applied before resizing. Enlarging an image increases its dimensions without adding detail. HDR and wide-gamut images are rendered to standard sRGB.",
                    "Processing can be cancelled; a native codec already running may finish internally, but its cancelled result is discarded."
                ])
            ])
        ],
        keywords: ["image", "convert", "resize", "rotate", "PNG", "JPEG", "HEIC", "TIFF", "privacy", "OCR", "extract text", "QR code"]
    )
}
