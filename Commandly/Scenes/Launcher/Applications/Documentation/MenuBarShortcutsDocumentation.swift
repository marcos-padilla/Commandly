import Foundation

extension RegisteredApplicationDocumentation {
    static let menuBarShortcuts = LauncherApplicationDocumentation(category: .productivity,
        overview: "Keep up to eight chosen Commandly applications or tools as independent icons in the macOS menu bar.",
        sections: [DocumentationSection(id: "menu-bar.use", title: "Choose Your Shortcuts", blocks: [
            .steps("menu-bar.steps", [
                "Open Menu Bar Shortcuts and search for a tool. Use the arrow keys to select it and Return to pin or remove it.",
                "Open the new icon's native menu and choose Open to run the tool through its usual review and permission flow.",
                "Remove a pin from its native menu or from Menu Bar Shortcuts. Hold Command while dragging icons to arrange them."
            ]),
            .paragraph("menu-bar.rules", "Pinning does not run a tool or request access. Pins survive restarting Commandly and remain independent of hiding its main status icon. Disabled or missing tools remain removable but cannot run. macOS controls available menu-bar space."),
            .paragraph("menu-bar.privacy", "Only registered command IDs are saved locally. Shortcut arguments, search text, clipboard data, and documents are not stored. Custom third-party status displays require their own integration and are not created by pinning a tool.")
        ])], keywords: ["menu bar", "pin", "status item", "shortcut", "remove"])
}
