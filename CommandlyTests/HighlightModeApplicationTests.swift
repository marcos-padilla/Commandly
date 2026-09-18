import CommandKit
import Infrastructure
import Testing
@testable import Commandly

@Suite("Highlight Mode application")
@MainActor
struct HighlightModeApplicationTests {
    @Test func builtInRegistryPublishesConfigurableHighlightMode() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        let definition = try #require(
            registry.definition(for: HighlightModeApplication.applicationID)
        )

        #expect(definition.title == "Highlight Mode")
        #expect(definition.configurationFields.count == 7)
        #expect(registry.application(for: definition.id) != nil)

        let settings = try #require(registry.resolvedSettings(for: definition.id))
        let configuration = HighlightModeApplication.configuration(from: settings)
        #expect(configuration == .default)
    }

    @Test func viewModelTogglesServiceWithoutStoppingSessionOnNavigation() async {
        let service = InMemoryHighlightModeService()
        let model = HighlightModeViewModel(
            service: service,
            configuration: .default,
            onOpenPermissions: {},
            onGoBack: {}
        )

        model.toggle()
        await model.waitForOperationForTesting()
        #expect(model.state.isEnabled)
        #expect(service.state.isEnabled)

        model.stop()
        #expect(service.state.isEnabled)

        model.toggle()
        await model.waitForOperationForTesting()
        #expect(model.state.isEnabled == false)
        #expect(service.state.isEnabled == false)
    }

    @Test func assignedHotkeyInvocationTogglesInBackground() async throws {
        let service = InMemoryHighlightModeService()
        let application = HighlightModeApplication(service: service)
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            highlightModeService: service
        )
        let settings = try #require(
            registry.resolvedSettings(for: HighlightModeApplication.applicationID)
        )

        let firstResult = await application.invokeInBackground(settings: settings)
        #expect(firstResult == .success(message: "Highlight Mode on."))
        #expect(service.state.isEnabled)

        let secondResult = await application.invokeInBackground(settings: settings)
        #expect(secondResult == .success(message: "Highlight Mode off."))
        #expect(service.state.isEnabled == false)
    }

    @Test func permissionDenialLeavesModeOffAndOffersRecovery() async {
        let service = DeniedHighlightModeService()
        var openedPermissions = false
        let model = HighlightModeViewModel(
            service: service,
            configuration: .default,
            onOpenPermissions: { openedPermissions = true },
            onGoBack: {}
        )

        model.toggle()
        await model.waitForOperationForTesting()

        #expect(model.state.isEnabled == false)
        #expect(model.errorMessage?.contains("Accessibility") == true)
        model.openPermissions()
        #expect(openedPermissions)
    }

    @Test func resolvedPreferencesMapToNativeConfigurationValues() throws {
        let store = InMemoryLauncherApplicationPreferencesStore()
        var preferences = LauncherApplicationPreferences.empty
        preferences.configuration = [
            "showMouseClicks": .boolean(false),
            "showKeyboardShortcuts": .boolean(false),
            "showTypedText": .boolean(false),
            "showCursorSpotlight": .boolean(true),
            "spotlightSize": .text("large"),
            "accentColor": .text("orange"),
            "displayDuration": .text("long"),
        ]
        store.save(preferences, for: HighlightModeApplication.applicationID)
        let registry = LauncherApplicationRegistry.makeBuiltIn(preferencesStore: store)
        let settings = try #require(
            registry.resolvedSettings(for: HighlightModeApplication.applicationID)
        )

        let configuration = HighlightModeApplication.configuration(from: settings)
        #expect(configuration.showsMouseClicks == false)
        #expect(configuration.showsKeyboardShortcuts == false)
        #expect(configuration.showsTypedText == false)
        #expect(configuration.showsCursorSpotlight)
        #expect(configuration.spotlightSize == .large)
        #expect(configuration.accent == .orange)
        #expect(configuration.displayDuration == .long)
    }
}

@MainActor
private final class DeniedHighlightModeService: HighlightModeControlling {
    let state = HighlightModeState(isEnabled: false)

    func setEnabled(
        _ isEnabled: Bool,
        configuration: HighlightModeConfiguration
    ) async throws -> HighlightModeState {
        _ = isEnabled
        _ = configuration
        throw HighlightModeError.accessibilityDenied
    }

    func updateConfiguration(_ configuration: HighlightModeConfiguration) {
        _ = configuration
    }

    func stop() {}
}
