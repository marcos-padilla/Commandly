import ClipboardToolsModule
import CommandKit
import ModuleKit
import SwiftUI

/// Launcher surface for the Clipboard Tools module.
///
/// The application owns only presentation. Every operation is performed by the module's
/// ``ClipboardToolsOperations``, so the launcher, a shortcut, the Command Wheel, and the menu bar
/// all run one implementation.
@MainActor
struct ClipboardToolsApplication:
    LauncherApplication,
    LauncherApplicationToolBackgroundInvoking
{
    static let id = ClipboardToolsIdentifiers.application
    static let plainTextToolID = ClipboardToolsIdentifiers.plainText
    static let cleanURLToolID = ClipboardToolsIdentifiers.cleanURL
    static let clearToolID = ClipboardToolsIdentifiers.clearNow

    private static let manifest = CommandManifest(
        id: id,
        title: ClipboardToolsCommands.application.manifest.title,
        subtitle: ClipboardToolsCommands.application.manifest.subtitle,
        systemImage: ClipboardToolsCommands.application.manifest.systemImage,
        category: .productivity,
        mode: .view,
        keywords: ClipboardToolsCommands.application.manifest.keywords,
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: ClipboardToolsIdentifiers.plainText.rawValue),
                title: "Make Plain Text",
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
        order: 35,
        configurationFields: ClipboardToolsSettings.contribution.launcherConfigurationFields,
        documentation: RegisteredApplicationDocumentation.clipboardTools
    )

    /// The module's operations. The application never touches the pasteboard itself.
    private let operations: ClipboardToolsOperations

    init(operations: ClipboardToolsOperations) {
        self.operations = operations
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: CommandID(rawValue: "\(Self.id.rawValue).tool.open"),
                parentID: Self.id,
                title: "Open Clipboard Tools",
                subtitle: Self.manifest.subtitle,
                systemImage: Self.manifest.systemImage,
                keywords: ["clipboard", "tools", "open"]
            ),
            tool(for: ClipboardToolsCommands.plainText, order: 1),
            tool(for: ClipboardToolsCommands.cleanURL, order: 2),
            tool(for: ClipboardToolsCommands.clearNow, order: 3)
        ]
    }

    /// All three operations run without presenting the launcher.
    var backgroundToolIDs: Set<CommandID> {
        [Self.plainTextToolID, Self.cleanURLToolID, Self.clearToolID]
    }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        guard let handler = handler(for: toolID) else {
            return .failure(message: "Clipboard tool is unavailable.")
        }
        let outcome = await handler.execute(
            ModuleCommandInvocation(
                commandID: toolID,
                arguments: arguments,
                context: CommandInvocationContext(source: .search),
                grants: Self.backgroundInvocationGrants
            )
        )
        return outcome.commandResult
    }

    /// Grants for a command that already cleared the shared executor's authorization gate.
    ///
    /// These commands are local, non-disclosing mutations, so they need only a caller identity and
    /// no filesystem, external-action, or disclosure authority. See the equivalent note on
    /// `TimersApplication` and the outstanding item in `docs/MODULARIZATION_PROGRESS.md`.
    private static let backgroundInvocationGrants: ModuleCallerGrants = [.userInitiated]

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = context
        return .message("Run a Clipboard Tools action from search or a shortcut.")
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        // The three operations are direct. Falling back to a surface here would report success
        // for work that never happened.
        guard toolID == CommandID(rawValue: "\(Self.id.rawValue).tool.open") else {
            return .message("That Clipboard Tools action runs without opening a window.")
        }
        return launch(in: context)
    }

    private func handler(for toolID: CommandID) -> (any ModuleCommandHandling)? {
        switch toolID {
        case Self.plainTextToolID:
            return FlattenClipboardCommandHandler(operations: operations)
        case Self.cleanURLToolID:
            return CleanCopiedLinkCommandHandler(operations: operations)
        case Self.clearToolID:
            return ClearClipboardCommandHandler(operations: operations)
        default:
            return nil
        }
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
