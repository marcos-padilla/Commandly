import CommandKit
import Foundation
import SwiftUI

@MainActor
struct WindowLayoutsApplicationServices {
    let layoutService: any WindowLayoutApplying
    let customStore: any CustomWindowLayoutStoring
    let commandCatalog: WindowLayoutCommandCatalog
    init(layoutService: any WindowLayoutApplying, customStore: any CustomWindowLayoutStoring) {
        self.layoutService = layoutService
        let catalog = WindowLayoutCommandCatalog(store: customStore)
        self.customStore = catalog; self.commandCatalog = catalog
    }
}

@MainActor
struct WindowLayoutsApplication: LauncherApplication, LauncherApplicationToolBackgroundInvoking {
    static let id = CommandID(rawValue: "windows.layouts")

    private static let manifest = CommandManifest(
        id: id,
        title: "Window Layouts",
        subtitle: "Arrange the active window with 58 native presets",
        systemImage: "rectangle.3.group",
        category: .system,
        mode: .view,
        keywords: ["window", "tile", "resize", "position", "custom", "grid"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: WindowLayoutsActionID.apply,
                title: "Apply to Active Window",
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
        order: 80,
        documentation: RegisteredApplicationDocumentation.windowLayouts
    )

    private let services: WindowLayoutsApplicationServices

    init(services: WindowLayoutsApplicationServices) {
        self.services = services
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: CommandID(rawValue: "windows.layouts.tool.open"), parentID: Self.id, title: "Open Window Layouts",
               subtitle: "Browse presets and create custom layouts", systemImage: "rectangle.3.group", category: .system,
               keywords: ["window", "layout", "custom"])] + services.commandCatalog.presets.enumerated().map { index, preset in
            .tool(id: WindowLayoutCommandCatalog.toolID(preset), parentID: Self.id, title: "Window: " + preset.title,
                  subtitle: "Apply this layout to the current external window", systemImage: "rectangle.3.group", category: .system,
                  order: index + 1, keywords: ["window", "layout", "arrange", "resize", preset.title])
        }
    }
    var backgroundToolIDs: Set<CommandID> { Set(services.commandCatalog.presets.map(WindowLayoutCommandCatalog.toolID)) }

    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled, arguments.values.isEmpty else { return .message("This layout command is disabled or unavailable.") }
        if toolID.rawValue == "windows.layouts.tool.open" { return launch(in: context) }
        guard let preset = services.commandCatalog.preset(toolID: toolID) else { return .message("This custom layout was removed. Choose another layout.") }
        let model = WindowLayoutsViewModel(service: services.layoutService, customStore: services.customStore, onGoBack: context.navigation.goBack)
        if preset.id.hasPrefix("custom.") {
            model.source = .custom
            // The editor's legacy identifiers use Foundation's uppercase UUID rendering.
            if let id = UUID(uuidString: String(preset.id.dropFirst(7))) { model.select("custom." + id.uuidString) }
        } else { model.select(preset.id) }
        model.applySelected()
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { WindowLayoutsView(viewModel: $0) })
    }

    func invokeToolInBackground(toolID: CommandID, arguments: CommandArguments, settings: LauncherApplicationResolvedSettings) async -> CommandResult {
        guard settings.isEnabled, arguments.values.isEmpty, let preset = services.commandCatalog.preset(toolID: toolID) else {
            return .failure(message: "This layout command is disabled or unavailable.")
        }
        do {
            try await services.layoutService.apply(rect: preset.rect)
            try Task.checkCancellation()
            return .success(message: "Applied \(preset.title).")
        } catch is CancellationError { return .cancelled }
        catch let error as CompanionWindowLayoutApplicationError { return .failure(message: error.localizedDescription) }
        catch { return .failure(message: "The window layout could not be applied.") }
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message("Enable Window Layouts in Applications settings first.") }
        let model = WindowLayoutsViewModel(
            service: services.layoutService,
            customStore: services.customStore,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                WindowLayoutsView(viewModel: $0)
            }
        )
    }
}

extension WindowLayoutsViewModel: LauncherApplicationModel {}
