import Foundation

extension RegisteredApplicationDocumentation {
    static let visualAI = LauncherApplicationDocumentation(category: .productivity,
        overview: "Ask a supported configured AI model about one screenshot you explicitly capture and review. Opening Visual AI does not capture or send anything.",
        sections: [DocumentationSection(id: "visual-ai.use", title: "Capture, Review, Send", blocks: [
            .steps("visual-ai.steps", ["Choose Full Screen or Selected Region, then select Capture. Full Screen uses the macOS display picker; Region may request Screen Recording access.",
                "Review the exact prepared image. Remove it or capture again if it includes information you do not want to share.",
                "Choose a saved image-capable provider/model, write a question, and choose Send Screenshot. Your image and question go directly to that provider under your account."]),
            .paragraph("visual-ai.models", "Supported curated models use the OpenAI, Anthropic or Google Gemini image APIs. Save an image-capable model in AI Settings, then refresh the local choices. Unsupported models are unavailable; Visual AI does not silently send text instead of the image.")]),
        DocumentationSection(id: "visual-ai.privacy", title: "Privacy and Limits", blocks: [
            .paragraph("visual-ai.image", "The image is resized locally to at most 2,048 pixels per edge and encoded as a JPEG of at most 2 MiB before review. The preview uses those exact provider-bound bytes. Metadata is removed; fine details may be lost. A selected region contains only that region; Full Screen contains the chosen full display."),
            .paragraph("visual-ai.cancel", "Cancel stops local work and rejects late results. It cannot recall data already sent to the provider. Remove, Back and launcher dismissal clear local image and answer state. Images and conversation history are not saved or logged."),
            .paragraph("visual-ai.authority", "This is single-turn image analysis. Text visible in a screenshot has no authority to invoke commands. No tools, computer-control actions, browser, shell, files or clipboard are exposed to the model. AI answers can be mistaken.")])],
        keywords: ["screenshot", "AI", "vision", "screen", "region", "privacy"])
}
