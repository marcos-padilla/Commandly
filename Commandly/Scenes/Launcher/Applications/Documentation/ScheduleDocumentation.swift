import Foundation

extension RegisteredApplicationDocumentation {
    static let schedule = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Review upcoming Calendar events, choose an exact meeting link, and optionally arm one occurrence to join automatically while Commandly stays running.",
        sections: [
            DocumentationSection(id: "schedule.open", title: "See Your Schedule", blocks: [
                .steps("schedule.open.steps", [
                    "Open My Schedule. Reading permission is checked without presenting a system prompt.",
                    "Choose Grant Calendar Access when ready. My Schedule reads events only; macOS calls the required permission Full Access.",
                    "Filter Today, Next 7 Days, or Next 30 Days and optionally choose a calendar. Search matches local event titles, calendars, and locations.",
                    "Select an event with the arrow keys and press Return to review its meeting links. Join Next Meeting opens that review for the next eligible event."
                ]),
                .shortcuts("schedule.open.keys", [
                    DocumentationShortcut(id: "schedule.return", title: "Review or confirm the selected meeting", keys: ["Return"]),
                    DocumentationShortcut(id: "schedule.actions", title: "Open schedule actions", keys: ["⌘", "K"]),
                    DocumentationShortcut(id: "schedule.escape", title: "Cancel review, clear search, or return", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "schedule.join", title: "Meeting Links and Autojoin", blocks: [
                .paragraph("schedule.join.review", "Choose a destination when an event contains multiple HTTPS links, review its exact URL, then Join Meeting. Commandly rechecks the occurrence and link immediately before opening it. It never joins by merely searching, selecting, or opening Schedule."),
                .paragraph("schedule.join.auto", "Automatically Join This Occurrence opens an explicit review. Enable Autojoin arms only that occurrence and replaces any previously armed one. Google Meet, Zoom, Microsoft Teams, and Webex destinations are supported. Autojoin survives closing the launcher but ends when Commandly quits. Cancel it from My Schedule at any time."),
                .paragraph("schedule.join.changes", "Changed or canceled events, declined invitations, changed links, denied access, or waking more than a minute after the scheduled start stop automatic joining. The latest failure is shown in My Schedule; Commandly does not silently retry an uncertain open.")
            ]),
            DocumentationSection(id: "schedule.privacy", title: "Privacy and Limits", blocks: [
                .callout("schedule.privacy.local", DocumentationCallout(kind: .privacy, title: "Calendar data stays local", text: "Event snapshots, meeting tokens, filters, and armed occurrence details remain in memory. They are not logged, uploaded, added to command history, or persisted. My Schedule never creates or changes Calendar events.")),
                .callout("schedule.privacy.bounds", DocumentationCallout(kind: .limitation, title: "A bounded upcoming view", text: "Each view loads at most 200 occurrences and indicates when more exist. Calendar data reflects accounts already configured in macOS. Camera previews, meeting recording, reminders, and joining while Commandly is closed are separate capabilities."))
            ])
        ], keywords: ["calendar", "agenda", "meeting", "join", "autojoin"]
    )
}
