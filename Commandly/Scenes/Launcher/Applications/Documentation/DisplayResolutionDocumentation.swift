import Foundation

extension RegisteredApplicationDocumentation {
    static let displayResolution = LauncherApplicationDocumentation(category: .system,
        overview: "Choose a connected display and preview one of its native desktop modes. Keep the mode for the current login session or let the bounded preview revert.",
        sections: [
            DocumentationSection(id: "resolution.preview", title: "Preview and Confirm", blocks: [
                .steps("resolution.steps", [
                    "Open Display Resolution. Choose an active, non-mirrored display and a mode. The list distinguishes logical size from pixel size and reports refresh rate when macOS provides it.",
                    "Choose Apply Preview. The temporary preview has a fifteen-second monotonic deadline, including time spent applying the change.",
                    "Choose Keep for This Session to request a login-session setting. Choose Revert, close the window, or press Escape to restore the original mode while the preview is pending."
                ]),
                .paragraph("resolution.scope", "The chooser is independent of the launcher and its runtime owner survives launcher dismissal. Once Keep is accepted, a close waits for that decision to finish. Permanent display preferences are never written.")
            ]),
            DocumentationSection(id: "resolution.recovery", title: "Recovery and Limits", blocks: [
                .paragraph("resolution.changed", "If another app changes the mode, Commandly preserves that newer choice. A disconnected display, unavailable original mode, or failed system operation leaves visible recovery controls with Retry Revert and System Settings. Commandly never picks an approximate replacement or restores all displays globally."),
                .paragraph("resolution.quit", "Quitting waits for pending restoration. If restoration fails, the recovery window offers an explicit quit. macOS removes app-lifetime overrides at process termination, but that fallback is not a guarantee of the exact original mode. A previously attempted login-session promotion may remain until logout."),
                .callout("resolution.limits", DocumentationCallout(kind: .limitation, title: "Native support varies", text: "Mirrored or inactive displays use System Settings. Very small modes are listed but cannot be previewed because the confirmation must remain readable. Full-screen apps and display hardware can reject configuration requests. This workflow needs real-device acceptance before claiming all modes or post-quit session persistence work."))
            ])
        ], keywords: ["display", "resolution", "hidpi", "preview", "revert"])
}
