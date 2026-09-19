import Foundation
import ModuleKit

/// Authored documentation owned by the Clipboard Tools module.
public enum ClipboardToolsDocumentation {
    /// Identifier of the module's overview article.
    public static let overviewArticleID = "clipboard-tools.overview"

    /// The module's documentation contribution.
    public static let contribution = ModuleDocumentationContribution(
        articles: [
            ModuleDocumentationArticle(
                id: overviewArticleID,
                title: "Clipboard Tools",
                summary: """
                Flatten copied formatting, strip tracking parameters from links, and clear the \
                clipboard on a timer or when your Mac sleeps or locks. Clearing the clipboard \
                never deletes your saved Clipboard History entries.

                Commandly is sandboxed and does not press keys in other applications, so \
                "Clipboard to Plain Text" prepares the clipboard and you paste normally.
                """,
                references: [
                    .command(ClipboardToolsIdentifiers.application),
                    .command(ClipboardToolsIdentifiers.plainText),
                    .command(ClipboardToolsIdentifiers.cleanURL),
                    .command(ClipboardToolsIdentifiers.clearNow),
                    .setting(variable: ClipboardToolsSettingsVariable.cleanLinksAutomatically),
                    .setting(variable: ClipboardToolsSettingsVariable.additionalTrackingParameters),
                    .setting(variable: ClipboardToolsSettingsVariable.autoClearIdleSeconds),
                    .setting(variable: ClipboardToolsSettingsVariable.autoClearOnSystemSleep),
                    .setting(variable: ClipboardToolsSettingsVariable.autoClearOnDisplaySleep),
                    .setting(variable: ClipboardToolsSettingsVariable.autoClearOnScreenLock)
                ]
            )
        ]
    )
}
