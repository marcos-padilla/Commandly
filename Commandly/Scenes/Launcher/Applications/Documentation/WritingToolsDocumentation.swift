import Foundation

extension RegisteredApplicationDocumentation {
    static let writingTools = LauncherApplicationDocumentation(category: .productivity,
        overview: "Review spelling and grammar suggestions from macOS, or use the native Quick Fix Selection Locally service to return eligible corrections to an editor’s selected text.",
        sections: [
            DocumentationSection(id: "writing.review", title: "Review a Correction", blocks: [
                .steps("writing.review.steps", [
                    "Open Spelling & Grammar and type or paste a short selection. Choose an installed language or use Automatic language.",
                    "Choose Check Text. Review the native issues and suggested replacements. Some grammar issues have an explanation without an automatic correction.",
                    "Use Automatic Suggestions, accept individual non-overlapping suggestions, or edit the result yourself. Accepted choices are retained; Restore Original resets them and protects manually edited output from new suggestions. Copy Result explicitly copies your reviewed text."
                ])
            ]),
            DocumentationSection(id: "writing.inline", title: "Quick Fix in an Editor", blocks: [
                .paragraph("writing.inline.service", "Select editable text in another app, then invoke Services → Quick Fix Selection Locally. This explicit action applies eligible local suggestions directly; the progress panel offers Cancel. The service returns text only to the requesting editor, which controls replacement and its native Undo support."),
                .paragraph("writing.inline.shortcut", "Enable the service and assign an unused shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services → Text. Run Commandly from Applications and reopen the editor if a newly installed service is missing."),
                .callout("writing.inline.boundary", DocumentationCallout(kind: .limitation, title: "Editor support varies", text: "The launcher does not capture or replace an external selection automatically. Apps without editable text Services need the review checker and Copy Result. Overlapping or incomplete native results also require review. This is a native Services workflow, not universal Accessibility injection."))
            ]),
            DocumentationSection(id: "writing.privacy", title: "Private, Bounded Requests", blocks: [
                .paragraph("writing.privacy.native", "Commandly uses the Mac’s spelling services and installed languages. It does not send this text to a configured AI provider, use a network client, inspect the general clipboard, log text, or retain it after the session. The inline service receives only the specific pasteboard supplied by its requester."),
                .paragraph("writing.privacy.bounds", "Check at most 16 KiB at a time. Native results retain at most 128 issues. Quick Fix stops after eight seconds and discards late callbacks; the system service timeout is fifteen seconds. Cancellation, timeout, or a changed request leaves the original selection untouched.")
            ])
        ], keywords: ["grammar", "spelling", "quick fix", "services", "review", "local"])
}
