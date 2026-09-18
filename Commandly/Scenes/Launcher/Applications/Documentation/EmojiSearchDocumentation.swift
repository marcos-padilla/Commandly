import Foundation

extension RegisteredApplicationDocumentation {
    static let emojiSearch = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Find and explicitly copy emoji from the complete Unicode 17.0 RGI catalog, with native macOS glyphs, English names, categories, and search keywords. Optional AI search matches a description using your configured provider.",
        sections: [
            DocumentationSection(id: "emoji.catalog", title: "Search and Choose", blocks: [
                .steps("emoji.catalog.steps", [
                    "Open Emoji Search and type an English name or keyword. Choose a category to narrow the catalog, or paste an emoji to find its exact sequence.",
                    "The default grid groups skin-tone variants. Choose an emoji and use Variant to select an available combination. Show all skin tones reveals every sequence; tone words in a search also reveal variants.",
                    "Up and Down move by six columns. Click the grid to use all four arrow keys; Left and Right remain text-editing keys in the search field.",
                    "Return copies the selected emoji. Command–Shift–C or Copy Emoji also copies. Choosing an emoji or skin tone only changes the preview. If a local search is pending, Return waits for that query; editing it or leaving cancels the pending copy."
                ]),
                .paragraph("emoji.catalog.coverage", "The bundled catalog includes 3,944 fully-qualified Unicode 17.0 emoji and 9 standalone components, with 1,923 default family entries. It retains variation selectors, joined sequences, country/subdivision flags, and mixed skin tones. Names and keywords are English. Actual glyph appearance and support depend on the macOS fonts on this Mac; unsupported sequences may display as separate symbols.")
            ]),
            DocumentationSection(id: "emoji.ai", title: "Find an Emoji for an Idea", blocks: [
                .steps("emoji.ai.steps", [
                    "Choose AI Search or open Find Emoji with AI. Select a saved provider and model, then describe an idea, feeling, or occasion.",
                    "Review the provider/model disclosure and choose Find with AI. Typing, opening the tool, or selecting a provider never submits a prompt.",
                    "The response must be a short list of catalog emoji. Review the suggestions, select a variant if available, and explicitly copy your choice.",
                    "Escape or Cancel stops the request. Editing the description, changing providers, switching to Catalog, or leaving also cancels and rejects late responses. Escape next clears your description, then returns home.",
                    "Use AI Settings to connect or repair a provider. Refresh Saved AI Connections in Actions rereads saved metadata without remote discovery. If a model returns malformed output, choose another model or rewrite the description."
                ]),
                .callout("emoji.ai.privacy", DocumentationCallout(kind: .privacy, title: "AI is optional", text: "Local catalog search sends nothing. Find with AI sends only the entered description and Commandly’s output-format instructions through the existing configured AI connection. The provider may process that request under its own policies. Saved Emoji Keyword items, clipboard content, files, and search history are never included. Commandly does not save prompts or suggestions.")),
                .paragraph("emoji.ai.bounds", "AI descriptions are limited to 1,024 UTF-8 bytes; replies to 8 KiB and 12 suggestions. No provider text or partial response is rendered. A malformed, truncated, or out-of-catalog answer is rejected; local keyword results are never presented as AI output.")
            ]),
            DocumentationSection(id: "emoji.saved", title: "Your Saved Keywords", blocks: [
                .paragraph("emoji.saved.preserve", "Your locally authored Emoji Keyword items remain in Emoji Keywords in Productivity Library, with their existing persistence and copy actions. The Unicode catalog does not modify, migrate, upload, or automatically expand them. Slack workspace emoji and GIFs are separate features.")
            ])
        ], keywords: ["emoji", "unicode", "keyword", "skin tone", "flag", "AI", "semantic", "copy", "privacy"]
    )
}
