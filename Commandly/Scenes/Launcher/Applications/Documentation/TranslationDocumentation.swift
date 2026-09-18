import Foundation

extension RegisteredApplicationDocumentation {
    static let translation = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Translate text or a word with Apple’s on-device translation framework. Choose the source and target, or let Apple detect the source. Review the result before explicitly copying it.",
        sections: [
            DocumentationSection(id: "translation.workflow", title: "Translate Text or a Word", blocks: [
                .steps("translation.workflow.steps", [
                    "Open Translate for paragraphs, or Translate a Word for a focused single-line entry. Opening an entry loads only supported-language metadata, never a translation or download.",
                    "Choose a target from the full native language list. Select Detect Language or choose a source language explicitly.",
                    "Enter text and choose Translate. Use Command–Return for paragraphs or Return in the word tool. Apple may ask you to resolve an ambiguous source language, especially for a single word.",
                    "If Apple needs language files, review its download prompt. You may decline. With a chosen source and target, Download Languages offers preparation separately from translation.",
                    "Review the native result and its source/target labels, then choose Copy Translation. Command–Shift–C also copies the reviewed result. Changing text or languages clears an older result."
                ]),
                .paragraph("translation.catalog", "The pickers show the languages available through Apple’s native framework on this Mac, without a fixed shortlist. Commandly prefers Apple’s higher-fidelity translation strategy, which uses Apple Intelligence where available and the native traditional models otherwise. A language being listed does not mean every pair is supported or its files are already installed. Translating to the same language is unsupported.")
            ]),
            DocumentationSection(id: "translation.privacy", title: "Privacy, Downloads, and Recovery", blocks: [
                .callout("translation.privacy.local", DocumentationCallout(kind: .privacy, title: "Text stays on this device", text: "Apple documents that TranslationSession processes the original and translated text on the device. Apple may collect API usage and performance metrics including the app identifier and language pair, but not the original or translated content. Commandly does not store, log, upload, or send the text to an AI provider.")),
                .bullets("translation.recovery", [
                    "Language downloads need your approval through Apple’s UI. Cancelling translation, dismissing a prompt, or leaving Commandly does not guarantee that an already approved operating-system download stops.",
                    "Cancel or Escape stops the local request and prevents late results from replacing current work. Your draft remains available for retry. Leaving the application clears input and result text.",
                    "If the source is unclear, choose it explicitly and retry. If a language pair is unsupported, choose different languages. Refresh Languages to check current native availability.",
                    "If models are missing or a download failed, retry Translate or choose a source and Download Languages. On macOS, downloaded models can be managed in System Settings → General → Language & Region → Translation Languages.",
                    "Each submission supports up to 10,000 characters and 64 KiB UTF-8, with a translated-output limit of 256 KiB. Split longer text into smaller passages.",
                    "Copy Translation writes only after explicit intent, including normal Clipboard History behavior when enabled. Copy failure keeps the result for retry."
                ])
            ])
        ], keywords: ["translate", "translation", "word", "source language", "target language", "detect", "Apple Translation", "downloads", "privacy"]
    )
}
