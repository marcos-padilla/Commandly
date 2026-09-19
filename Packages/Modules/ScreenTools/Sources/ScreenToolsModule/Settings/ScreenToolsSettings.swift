import Foundation
import ModuleKit

/// Typed configuration owned by the Screen Tools module.
public enum ScreenToolsSettings {
    /// The module's configuration schema.
    public static let contribution = ModuleSettingsContribution(
        schemaVersion: 1,
        fields: [
            ModuleConfigurationField(
                id: "screen-color-format",
                variable: ScreenToolsSettingsVariable.colorFormat,
                title: "Copy colors as",
                description: "The format used when a sampled color is copied.",
                section: "Color picker",
                kind: .selection,
                defaultValue: .text(ScreenColorFormat.hex.rawValue),
                options: ScreenColorFormat.allCases.map {
                    ModuleConfigurationOption(id: $0.rawValue, title: $0.title)
                }
            ),
            ModuleConfigurationField(
                id: "join-recognized-lines",
                variable: ScreenToolsSettingsVariable.joinRecognizedLines,
                title: "Join recognized lines into paragraphs",
                description: """
                Collapse hard-wrapped lines into one paragraph when copying text from the screen. \
                Blank lines still separate paragraphs.
                """,
                section: "Copy text",
                kind: .toggle,
                defaultValue: .boolean(false)
            )
        ]
    )

    /// Reads the configured colour format, falling back to hex for an unknown stored value.
    public static func colorFormat(
        from values: [String: ModuleConfigurationValue]
    ) -> ScreenColorFormat {
        guard let raw = values[ScreenToolsSettingsVariable.colorFormat]?.textValue,
              let format = ScreenColorFormat(rawValue: raw) else {
            return .hex
        }
        return format
    }

    /// Whether recognised lines are joined into paragraphs.
    public static func joinsRecognizedLines(
        from values: [String: ModuleConfigurationValue]
    ) -> Bool {
        values[ScreenToolsSettingsVariable.joinRecognizedLines]?.booleanValue ?? false
    }
}
