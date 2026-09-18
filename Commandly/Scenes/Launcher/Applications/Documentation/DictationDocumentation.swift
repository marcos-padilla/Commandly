import Foundation

extension RegisteredApplicationDocumentation {
    static let dictation = LauncherApplicationDocumentation(category: .productivity,
        overview: "Explicitly record microphone speech and transcribe it on this Mac. Choose a supported language, review and edit the result, then copy or save it. Optional AI writing styles operate only on reviewed text.",
        sections: [
            DocumentationSection(id: "dictation.record", title: "Record and Review", blocks: [
                .steps("dictation.record.steps", [
                    "Open Dictation and choose a supported language and microphone. The system language is preselected when supported; spoken-language autodetection is not available in this native API.",
                    "If needed, choose Download Language. This explicitly asks Apple to install its model. It does not start the microphone. Apple manages shared model files and may retain or update them after cancellation. Downloading another language can release an older unused reservation belonging to Commandly.",
                    "Choose Start Dictation or press Command–Return. Commandly asks for microphone access only at this point. Denied access can be changed in System Settings → Privacy & Security → Microphone; start again after changing it.",
                    "Speak while the recording indicator and timer are visible. Preliminary text can change as speech is recognized. Stop & Review, also Command–Return, stops the microphone and waits for final text. Recording stops at five minutes; transcript size is limited to 64 KiB.",
                    "Edit the text, then explicitly choose Copy Text or Command–Shift–C. Paste into your current app. Direct focused-field insertion requires a separately implemented, authenticated companion capability; this application does not claim cross-app insertion.",
                    "Cancel Recording discards the new capture and restores the previous draft. Escape cancels active capture or a model download; unsaved review text has a discard confirmation before Back/Escape leaves. Hiding/replacing the launcher stops the microphone and clears the session."
                ])
            ]),
            DocumentationSection(id: "dictation.styles", title: "Preview a Writing Style", blocks: [
                .paragraph("dictation.styles.preview", "Expand Writing Style, choose Clean Up, Concise, Professional, or Friendly, and select your configured AI provider/model. Preview Style sends the reviewed text and style instructions through the existing AI connection, never microphone audio. Opening this panel or changing styles sends no request. Your original text remains until you choose Use This Version. Editing the source, changing model/style, or cancelling rejects late results. Style input is limited to 8 KiB; a truncated or invalid reply is rejected. Always review the suggestion for meaning and accuracy.")
            ]),
            DocumentationSection(id: "dictation.history", title: "Save Only What You Choose", blocks: [
                .paragraph("dictation.history.save", "Save to History explicitly stores the reviewed text, chosen recognition language, date, and duration on this Mac. It does not save audio. Saved Dictations lets you search, review, copy, delete one entry, or clear everything. History allows up to 50 entries and 2 MiB; it does not silently evict earlier entries. Saving edits updates the current dictation’s existing record. Your active draft stays separate from history deletion."),
                .callout("dictation.privacy", DocumentationCallout(kind: .privacy, title: "On-device speech, optional text AI", text: "SpeechAnalyzer and its native transcriber modules process speech on-device. Commandly never stores or logs raw audio. No transcript is automatically saved or sent to a provider. Only Preview Style sends the currently reviewed text to the displayed provider. Explicit clipboard copies follow normal Clipboard History behavior when enabled."))
            ])
        ], keywords: ["dictation", "microphone", "speech", "language", "model download", "history", "writing style", "privacy"])
}
