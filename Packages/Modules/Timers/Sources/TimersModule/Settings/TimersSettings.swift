import Foundation
import ModuleKit

/// Typed configuration owned by the Timers & Focus module.
public enum TimersSettings {
    /// Storage key for the completion-sound preference.
    ///
    /// This matches the variable the shipped Timers application already persists, so existing user
    /// preferences keep working after the module migration.
    public static let completionSoundVariable = "completionSound"

    /// The module's configuration schema.
    public static let contribution = ModuleSettingsContribution(
        schemaVersion: 1,
        fields: [
            ModuleConfigurationField(
                id: "completion-sound",
                variable: completionSoundVariable,
                title: "Completion sound",
                description: "Play a local macOS sound when a timer finishes.",
                kind: .toggle,
                defaultValue: .boolean(true)
            )
        ]
    )
}
