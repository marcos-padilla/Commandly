import CommandKit
import ModuleKit
import ScreenToolsModule
import SwiftUI

/// Launcher surface for the Screen Tools module.
///
/// Both operations present native selection UI, so they run as background tools rather than
/// pushing a launcher session: the user draws a region or points at a pixel, and the result lands
/// on the clipboard.
@MainActor
struct ScreenToolsApplication:
    LauncherApplication,
    LauncherApplicationToolBackgroundInvoking
{
    static let id = ScreenToolsIdentifiers.application
    static let copyTextToolID = ScreenToolsIdentifiers.copyText
    static let pickColorToolID = ScreenToolsIdentifiers.pickColor

    private static let manifest = CommandManifest(
        id: id,
        title: ScreenToolsCommands.application.manifest.title,
        subtitle: ScreenToolsCommands.application.manifest.subtitle,
        systemImage: ScreenToolsCommands.application.manifest.systemImage,
        category: .productivity,
        mode: .view,
        keywords: ScreenToolsCommands.application.manifest.keywords,
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: ScreenToolsIdentifiers.copyText.rawValue),
                title: "Copy Text From Screen",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 36,
        configurationFields: ScreenToolsSettings.contribution.launcherConfigurationFields,
        documentation: RegisteredApplicationDocumentation.screenTools
    )

    private let operations: ScreenToolsOperations

    init(operations: ScreenToolsOperations) {
        self.operations = operations
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: CommandID(rawValue: "\(Self.id.rawValue).tool.open"),
                parentID: Self.id,
                title: "Open Screen Tools",
                subtitle: Self.manifest.subtitle,
                systemImage: Self.manifest.systemImage,
                keywords: ["screen", "tools", "open"]
            ),
            tool(for: ScreenToolsCommands.copyText, order: 1),
            tool(for: ScreenToolsCommands.pickColor, order: 2)
        ]
    }

    var backgroundToolIDs: Set<CommandID> { [Self.copyTextToolID, Self.pickColorToolID] }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        let handler: (any ModuleCommandHandling)?
        switch toolID {
        case Self.copyTextToolID:
            handler = CopyScreenTextCommandHandler(operations: operations)
        case Self.pickColorToolID:
            handler = PickScreenColorCommandHandler(operations: operations)
        default:
            handler = nil
        }
        guard let handler else { return .failure(message: "Screen tool is unavailable.") }
        let outcome = await handler.execute(
            ModuleCommandInvocation(
                commandID: toolID,
                arguments: arguments,
                context: CommandInvocationContext(source: .search),
                // The user performs the selection themselves, so this is a user-initiated action
                // that discloses screen content only to their own clipboard.
                grants: [.userInitiated, .sensitiveDisclosure]
            )
        )
        return outcome.commandResult
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = context
        return .message("Choose Copy Text From Screen or Pick Color From Screen.")
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == CommandID(rawValue: "\(Self.id.rawValue).tool.open") else {
            return .message("That screen action runs without opening a window.")
        }
        return launch(in: context)
    }

    private func tool(
        for definition: ModuleCommandDefinition,
        order: Int
    ) -> LauncherApplicationDefinition {
        LauncherApplicationDefinition.tool(
            id: definition.id,
            parentID: Self.id,
            title: definition.manifest.title,
            subtitle: definition.manifest.subtitle,
            systemImage: definition.manifest.systemImage,
            category: definition.manifest.category,
            order: order,
            keywords: definition.manifest.keywords
        )
    }
}
