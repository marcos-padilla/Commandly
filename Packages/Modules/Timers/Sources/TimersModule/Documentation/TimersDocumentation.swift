import Foundation
import ModuleKit

/// Authored documentation owned by the Timers & Focus module.
///
/// The host gathers this without activating the module, so documentation stays readable while the
/// feature is disabled.
public enum TimersDocumentation {
    /// Identifier of the module's overview article.
    public static let overviewArticleID = "timers.overview"

    /// The module's documentation contribution.
    public static let contribution = ModuleDocumentationContribution(
        articles: [
            ModuleDocumentationArticle(
                id: overviewArticleID,
                title: "Timers & Focus",
                summary: """
                Run named countdowns and focus sessions. Timers keep running after you dismiss \
                Commandly, and finish with an optional local sound.
                """,
                references: [
                    .command(TimersModuleIdentifiers.application),
                    .command(TimersModuleIdentifiers.openTool),
                    .command(TimersModuleIdentifiers.newTimerTool),
                    .command(TimersModuleIdentifiers.startTool),
                    .setting(variable: TimersSettings.completionSoundVariable)
                ]
            )
        ]
    )
}
