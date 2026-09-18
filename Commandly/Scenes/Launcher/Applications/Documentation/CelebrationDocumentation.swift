import Foundation

extension RegisteredApplicationDocumentation {
    static let celebration = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Take a moment for a finished task with one brief, original confetti animation inside the launcher.",
        sections: [
            DocumentationSection(id: "celebration.play", title: "Celebrate a Win", blocks: [
                .steps("celebration.play.steps", [
                    "Search for Confetti or Celebrate with Confetti and press Return to play one burst.",
                    "Press Return or choose Celebrate Again to replay. Each replay replaces the previous burst.",
                    "Choose Done, Back, or press Escape to return to the launcher."
                ]),
                .shortcuts("celebration.play.keys", [
                    DocumentationShortcut(id: "celebration.return", title: "Celebrate again", keys: ["Return"]),
                    DocumentationShortcut(id: "celebration.escape", title: "Return to the launcher", keys: ["Esc"])
                ])
            ]),
            DocumentationSection(id: "celebration.accessibility", title: "Quiet When You Want It", blocks: [
                .paragraph("celebration.motion", "Reduce Motion replaces moving confetti with a stationary arrangement. Turning it on stops the current burst immediately. Turning it off does not automatically start another burst."),
                .paragraph("celebration.bounds", "The animation lasts 3.2 seconds and stops updating afterward. It stays inside Commandly, plays no sound, opens no extra windows, asks for no permissions, and stores or sends no data.")
            ])
        ], keywords: ["confetti", "celebrate", "replay", "reduce motion"]
    )
}
