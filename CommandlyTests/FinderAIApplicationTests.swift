import CommandKit
import Testing
@testable import Commandly

struct FinderAIApplicationTests {
    @Test @MainActor func builtInRegistryPlacesFinderUnderAIExtensions() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        let group = try #require(
            registry.definition(for: BuiltInLauncherApplicationGroup.aiExtensionsID)
        )
        let finder = try #require(registry.definition(for: FinderAIApplicationID.command))

        #expect(group.kind == .group)
        #expect(group.title == "AI Extensions")
        #expect(finder.kind == .aiExtension)
        #expect(finder.parentID == group.id)
        #expect(finder.documentation?.sections.isEmpty == false)
        #expect(registry.allManifests().contains { $0.id == FinderAIApplicationID.command })
    }

    @Test @MainActor func finderSetupActionRoutesDirectlyToAISettings() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        var genericSettingsCount = 0
        var aiSettingsCount = 0
        let launcher = LauncherViewModel(
            applicationRegistry: registry,
            onOpenSettings: { genericSettingsCount += 1 },
            onOpenAISettings: { aiSettingsCount += 1 }
        )

        launcher.launch(FinderAIApplicationID.command)
        let model = try #require(launcher.activeApplicationModel(as: FinderAIViewModel.self))
        model.perform(FinderAIActionID.openAISettings)

        #expect(genericSettingsCount == 0)
        #expect(aiSettingsCount == 1)
    }

    @Test @MainActor func finderFolderSetupActionRoutesDirectlyToPermissions() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        var genericSettingsCount = 0
        var permissionsSettingsCount = 0
        let launcher = LauncherViewModel(
            applicationRegistry: registry,
            onOpenSettings: { genericSettingsCount += 1 },
            onOpenPermissionsSettings: { permissionsSettingsCount += 1 }
        )

        launcher.launch(FinderAIApplicationID.command)
        let model = try #require(launcher.activeApplicationModel(as: FinderAIViewModel.self))
        model.perform(FinderAIActionID.openPermissionsSettings)

        #expect(genericSettingsCount == 0)
        #expect(permissionsSettingsCount == 1)
    }
}
