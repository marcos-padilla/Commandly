import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct SystemSettingsCatalogApplicationTests {
    @Test func catalogAndToolsRegisterWithoutNavigation() async throws {
        let opener = SettingsModelTestOpener()
        let application = SystemSettingsCatalogApplication(services: .init(opener: opener))
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        try registry.register(application)
        #expect(application.toolDefinitions.count == 28)
        #expect(application.backgroundToolIDs.count == 28)
        #expect(registry.isLaunchableCommand(SystemSettingsCatalogApplication.id))
        for item in SystemSettingsCatalog.items {
            #expect(registry.owningApplicationID(for: item.toolID) == SystemSettingsCatalogApplication.id)
            #expect(registry.isBackgroundInvokingCommand(item.toolID))
        }
        guard case .present(let session) = application.launch(in: context()) else {
            Issue.record("Catalog must present a session."); return
        }
        #expect(session.model(as: SystemSettingsViewModel.self) != nil)
        #expect(await opener.requests.isEmpty)
        session.stop()
    }
    @Test func eachDisplayToolUsesSameDestinationWithoutArguments() async throws {
        let opener = SettingsModelTestOpener()
        let application = SystemSettingsCatalogApplication(services: .init(opener: opener))
        for item in SystemSettingsCatalog.items.filter({ $0.pane == .displays }) {
            let result = await application.invokeToolInBackground(toolID: item.toolID, arguments: .empty, settings: context().settings)
            #expect(result == .success(message: "Requested Displays in System Settings."))
        }
        #expect(await opener.requests == Array(repeating: SystemSettingsPane?.some(.displays), count: 6))
    }
    @Test func disabledUnknownAndArgumentBearingInvocationsCannotDispatch() async throws {
        let opener = SettingsModelTestOpener()
        let application = SystemSettingsCatalogApplication(services: .init(opener: opener))
        let id = try #require(SystemSettingsCatalog.items.first?.toolID)
        #expect(await application.invokeToolInBackground(toolID: id, arguments: .empty, settings: context(enabled: false).settings) == .failure(message: SystemSettingsNavigationError.disabled.message))
        #expect(await application.invokeToolInBackground(toolID: .init(rawValue: "system.settings-catalog.unknown"), arguments: .empty, settings: context().settings) == .failure(message: SystemSettingsNavigationError.invalidRequest.message))
        #expect(await application.invokeToolInBackground(toolID: id, arguments: .init(["url": .string("https://example.com")]), settings: context().settings) == .failure(message: SystemSettingsNavigationError.invalidRequest.message))
        if case .present = application.launch(in: context(enabled: false)) { Issue.record("Disabled catalog must not create a session.") }
        #expect(await opener.requests.isEmpty)
    }
    @Test func disabledCatalogRemovesEveryOwnedToolFromCommandRegistry() async throws {
        let opener = SettingsModelTestOpener()
        let preferences = InMemoryLauncherApplicationPreferencesStore()
        let registry = LauncherApplicationRegistry(preferencesStore: preferences)
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        let application = SystemSettingsCatalogApplication(services: .init(opener: opener))
        try registry.register(application)
        var disabled = LauncherApplicationPreferences.empty
        disabled.isEnabled = false
        preferences.save(disabled, for: SystemSettingsCatalogApplication.id)
        for tool in application.toolDefinitions {
            #expect(!registry.isEffectivelyEnabled(tool.id))
            #expect(registry.allManifests().contains { $0.id == tool.id } == false)
        }
        #expect(await opener.requests.isEmpty)
    }
    @Test func backgroundFallbackIsVisibleRecoveryAndDoesNotClaimPaneOpened() async throws {
        let opener = SettingsModelTestOpener(mode: .fallback)
        let application = SystemSettingsCatalogApplication(services: .init(opener: opener))
        let id = try #require(SystemSettingsCatalog.items.first?.toolID)
        let result = await application.invokeToolInBackground(toolID: id, arguments: .empty, settings: context().settings)
        guard case .failure(let message) = result else { Issue.record("Fallback must retain visible recovery guidance."); return }
        #expect(message.contains("System Settings opened; choose Displays"))
    }
    private func context(enabled: Bool = true) -> LauncherApplicationContext {
        .init(navigation: .init(dismissLauncher: {}, openSettings: {}, goBack: {}), settings: .init(alias: "", hotKey: nil, isEnabled: enabled, configuration: [:]))
    }
}
