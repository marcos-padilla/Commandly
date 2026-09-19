import Foundation
import ModuleKit

/// Authored documentation owned by the Screen Tools module.
public enum ScreenToolsDocumentation {
    /// Identifier of the module's overview article.
    public static let overviewArticleID = "screen-tools.overview"

    /// The module's documentation contribution.
    public static let contribution = ModuleDocumentationContribution(
        articles: [
            ModuleDocumentationArticle(
                id: overviewArticleID,
                title: "Screen Tools",
                summary: """
                Select any area of the screen and copy the text recognized in it, or sample a \
                pixel's color and copy it in the format you prefer.

                Text recognition runs on this Mac. Nothing captured is uploaded, and the \
                recognized text goes to the clipboard and nowhere else. Selecting an area needs \
                Screen Recording permission; the color picker needs no permission because you \
                point at the pixel yourself.
                """,
                references: [
                    .command(ScreenToolsIdentifiers.application),
                    .command(ScreenToolsIdentifiers.copyText),
                    .command(ScreenToolsIdentifiers.pickColor),
                    .setting(variable: ScreenToolsSettingsVariable.colorFormat),
                    .setting(variable: ScreenToolsSettingsVariable.joinRecognizedLines),
                    .capability(identifier: ScreenToolsCapability.screenRecording)
                ]
            )
        ]
    )
}
