import Foundation
import ModuleKit

/// Typed configuration owned by the Clipboard Tools module.
public enum ClipboardToolsSettings {
    /// Upper bound on the idle timeout, in seconds (24 hours).
    ///
    /// Bounded so a stored value cannot produce an absurd countdown.
    public static let maximumIdleSeconds = 86_400

    /// The module's configuration schema.
    public static let contribution = ModuleSettingsContribution(
        schemaVersion: 1,
        fields: [
            ModuleConfigurationField(
                id: "clean-links-automatically",
                variable: ClipboardToolsSettingsVariable.cleanLinksAutomatically,
                title: "Clean copied links automatically",
                description: """
                Remove tracking parameters as soon as a link is copied. Turn this off to clean \
                links only when you run the command yourself.
                """,
                section: "Links",
                kind: .toggle,
                defaultValue: .boolean(false)
            ),
            ModuleConfigurationField(
                id: "additional-tracking-parameters",
                variable: ClipboardToolsSettingsVariable.additionalTrackingParameters,
                title: "Also remove these parameters",
                description: "Comma-separated parameter names to strip in addition to the built-in list.",
                placeholder: "ref, source",
                section: "Links",
                kind: .text,
                defaultValue: .text("")
            ),
            ModuleConfigurationField(
                id: "auto-clear-idle-seconds",
                variable: ClipboardToolsSettingsVariable.autoClearIdleSeconds,
                title: "Clear the clipboard after",
                description: "Seconds of inactivity after a copy before the clipboard is emptied. Zero turns this off.",
                section: "Auto-clear",
                kind: .integer,
                defaultValue: .integer(0),
                minimumValue: 0,
                maximumValue: Double(maximumIdleSeconds),
                step: 30
            ),
            ModuleConfigurationField(
                id: "auto-clear-system-sleep",
                variable: ClipboardToolsSettingsVariable.autoClearOnSystemSleep,
                title: "Clear when the Mac sleeps",
                section: "Auto-clear",
                kind: .toggle,
                defaultValue: .boolean(false)
            ),
            ModuleConfigurationField(
                id: "auto-clear-display-sleep",
                variable: ClipboardToolsSettingsVariable.autoClearOnDisplaySleep,
                title: "Clear when the display sleeps",
                section: "Auto-clear",
                kind: .toggle,
                defaultValue: .boolean(false)
            ),
            ModuleConfigurationField(
                id: "auto-clear-screen-lock",
                variable: ClipboardToolsSettingsVariable.autoClearOnScreenLock,
                title: "Clear when the screen locks",
                section: "Auto-clear",
                kind: .toggle,
                defaultValue: .boolean(false)
            )
        ]
    )

    /// Reads an auto-clear configuration from resolved settings values.
    ///
    /// Everything defaults to off, so a module that has never been configured clears nothing.
    public static func autoClearConfiguration(
        from values: [String: ModuleConfigurationValue]
    ) -> ClipboardAutoClearConfiguration {
        let idleSeconds = min(
            max(0, values[ClipboardToolsSettingsVariable.autoClearIdleSeconds]?.integerValue ?? 0),
            maximumIdleSeconds
        )
        var triggers: Set<ClipboardAutoClearTrigger> = []
        if idleSeconds > 0 { triggers.insert(.idleTimeout) }
        if values[ClipboardToolsSettingsVariable.autoClearOnSystemSleep]?.booleanValue == true {
            triggers.insert(.systemSleep)
        }
        if values[ClipboardToolsSettingsVariable.autoClearOnDisplaySleep]?.booleanValue == true {
            triggers.insert(.displaySleep)
        }
        if values[ClipboardToolsSettingsVariable.autoClearOnScreenLock]?.booleanValue == true {
            triggers.insert(.screenLock)
        }
        return ClipboardAutoClearConfiguration(
            idleTimeoutSeconds: idleSeconds,
            triggers: triggers
        )
    }

    /// Parses the user's extra tracking parameter names.
    public static func additionalTrackingParameters(
        from values: [String: ModuleConfigurationValue]
    ) -> [String] {
        let raw = values[ClipboardToolsSettingsVariable.additionalTrackingParameters]?.textValue ?? ""
        return raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    /// Whether copied links should be cleaned without the user asking each time.
    public static func cleansLinksAutomatically(
        from values: [String: ModuleConfigurationValue]
    ) -> Bool {
        values[ClipboardToolsSettingsVariable.cleanLinksAutomatically]?.booleanValue ?? false
    }
}
