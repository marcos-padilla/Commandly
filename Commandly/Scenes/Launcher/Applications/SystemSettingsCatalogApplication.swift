import CommandKit
import Infrastructure
import SwiftUI

@MainActor struct SystemSettingsCatalogApplication: LauncherApplication, LauncherApplicationToolBackgroundInvoking {
    static let id = CommandID(rawValue: "system.settings-catalog")
    static let openApplicationToolID = CommandID(rawValue: "system.settings-catalog.open-application")
    static let manifest = CommandManifest(id: id, title: "System Settings", subtitle: "Find and open macOS settings pages",
        systemImage: "gearshape.2", category: .system, mode: .view,
        keywords: ["macos", "preferences", "settings", "display", "sound", "keyboard", "privacy"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 50, documentation: RegisteredApplicationDocumentation.systemSettingsNavigation)
    private let services: SystemSettingsApplicationServices
    init(services: SystemSettingsApplicationServices) { self.services = services }

    var toolDefinitions: [LauncherApplicationDefinition] {
        SystemSettingsCatalog.items.enumerated().map { index, item in
            .tool(id: item.toolID, parentID: Self.id, title: item.title, subtitle: item.subtitle,
                  systemImage: item.systemImage, category: .system, order: index, keywords: item.keywords + ["settings", "preferences"])
        } + [.tool(id: Self.openApplicationToolID, parentID: Self.id, title: "Open macOS System Settings",
                   subtitle: "Open the macOS settings application", systemImage: "gearshape", category: .system,
                   order: SystemSettingsCatalog.items.count, keywords: ["macos", "preferences", "system settings"])]
    }
    var backgroundToolIDs: Set<CommandID> { Set(toolDefinitions.map(\.id)) }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message(SystemSettingsNavigationError.disabled.message) }
        return makeLaunch(item: nil, openImmediately: false, openApplication: false, context: context)
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message(SystemSettingsNavigationError.disabled.message) }
        guard arguments.values.isEmpty else { return .message(SystemSettingsNavigationError.invalidRequest.message) }
        if toolID == Self.openApplicationToolID { return makeLaunch(item: nil, openImmediately: true, openApplication: true, context: context) }
        guard let item = SystemSettingsCatalog.item(toolID: toolID) else { return .message(SystemSettingsNavigationError.invalidRequest.message) }
        return makeLaunch(item: item, openImmediately: true, openApplication: false, context: context)
    }
    private func makeLaunch(item: SystemSettingsCatalogItem?, openImmediately: Bool, openApplication: Bool,
                            context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = SystemSettingsViewModel(opener: services.opener, isEnabled: context.settings.isEnabled,
            initialItemID: item?.id, onGoBack: context.navigation.goBack, onOpened: context.navigation.dismissLauncher)
        if openImmediately {
            if openApplication { model.perform(SystemSettingsActionID.openApplication) }
            else { model.openSelected() }
        }
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { SystemSettingsCatalogView(viewModel: $0) })
    }
    func invokeToolInBackground(toolID: CommandID, arguments: CommandArguments, settings: LauncherApplicationResolvedSettings) async -> CommandResult {
        guard settings.isEnabled else { return .failure(message: SystemSettingsNavigationError.disabled.message) }
        guard arguments.values.isEmpty else { return .failure(message: SystemSettingsNavigationError.invalidRequest.message) }
        let pane: SystemSettingsPane?
        if toolID == Self.openApplicationToolID { pane = nil }
        else if let item = SystemSettingsCatalog.item(toolID: toolID) { pane = item.pane }
        else { return .failure(message: SystemSettingsNavigationError.invalidRequest.message) }
        do {
            try Task.checkCancellation()
            let result = try await services.opener.open(pane)
            try Task.checkCancellation()
            let message = SystemSettingsNavigationFeedback.message(result)
            // Background tools surface failures through the existing launcher recovery notice.
            // An app-only fallback did not fulfill the requested pane, so preserve its guidance.
            if case .openedApplication(fallbackFor: .some) = result { return .failure(message: message) }
            return .success(message: message)
        } catch is CancellationError { return .cancelled }
        catch { return .failure(message: (error as? SystemSettingsNavigationError ?? .navigationFailed).message) }
    }
}
