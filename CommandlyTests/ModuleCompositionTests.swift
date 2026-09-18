import AICommandBridge
import AIKit
import CommandKit
import Foundation
import ModuleKit
import ModuleRuntime
import Testing
import TimersModule
@testable import Commandly

/// Composition-level tests for the module system as the application wires it.
///
/// These complement the package tests: the package proves the host and bridge in isolation,
/// while these prove that `BuiltInModules`, the launcher registry, and the shared command
/// executor are connected the way the architecture requires.
@MainActor
struct ModuleCompositionTests {
    private func makeHost(
        registry: LauncherApplicationRegistry,
        timerStore: TimerStore
    ) -> ModuleHost {
        BuiltInModules.makeHost(
            timerStore: timerStore,
            enablement: LauncherRegistryModuleEnablementProvider(
                registry: registry,
                manifests: BuiltInModules.assemblies(timerStore: timerStore).map(\.manifest)
            )
        )
    }

    @Test func builtInModulesRegisterWithoutStartingServices() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = makeHost(registry: registry, timerStore: store)

        #expect(host.manifests().isEmpty == false)
        #expect(host.isActivated(TimersModuleIdentifiers.module) == false)
    }

    @Test func everyModuleCommandIDIsUniqueAndOwned() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = makeHost(registry: registry, timerStore: store)

        let ids = host.commandDefinitions().map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(host.owningModuleID(of: id) != nil)
        }
    }

    @Test func moduleCommandIDsExistInTheLauncherCatalog() throws {
        // A module command must correspond to something the launcher can actually resolve,
        // otherwise the module catalog and the executable catalog would drift apart.
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = makeHost(registry: registry, timerStore: store)

        let known = Set(registry.allKnownManifests().map(\.id))
        for definition in host.commandDefinitions() {
            #expect(
                known.contains(definition.id),
                "Module command \(definition.id.rawValue) is not in the launcher catalog."
            )
        }
    }

    @Test func settingsAndDocumentationDiscoveryStartsNoModule() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = makeHost(registry: registry, timerStore: store)

        _ = host.settingsContributions()
        _ = host.documentationContributions()
        _ = host.commandDefinitions()

        for manifest in host.manifests() {
            #expect(host.isActivated(manifest.id) == false)
        }
        #expect(store.timers.isEmpty)
    }

    @Test func moduleSettingsSchemaMatchesTheLauncherSettingsScreen() throws {
        // Modules author preferences once; the launcher renders a projection of that schema.
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let definition = try #require(
            registry.definition(for: TimersApplication.applicationID)
        )
        let authored = TimersSettings.contribution.fields

        #expect(definition.configurationFields.map(\.variable) == authored.map(\.variable))
        #expect(definition.configurationFields.map(\.id) == authored.map(\.id))
        #expect(definition.configurationFields.first?.kind == .toggle)
        #expect(definition.configurationFields.first?.defaultValue == .boolean(true))
    }

    @Test func disablingAModulesApplicationWithdrawsItsAvailability() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = makeHost(registry: registry, timerStore: store)
        #expect(host.availability(of: TimersModuleIdentifiers.module).isAvailable)

        var preferences = registry.preferences(for: TimersApplication.applicationID)
        preferences.isEnabled = false
        registry.savePreferences(preferences, for: TimersApplication.applicationID)

        #expect(host.availability(of: TimersModuleIdentifiers.module) == .disabled)
    }
}

/// AI exposure as the application composes it.
@MainActor
struct ModuleAIExposureCompositionTests {
    private func makeHost(timerStore: TimerStore) -> ModuleHost {
        BuiltInModules.makeHost(
            timerStore: timerStore,
            enablement: AlwaysEnabledModuleEnablementProvider()
        )
    }

    @Test func everyExposedToolWasExplicitlyReviewed() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let host = makeHost(timerStore: store)

        for definition in host.commandDefinitions() where definition.policy.aiExposure == .reviewed {
            // A reviewed command must be able to complete without native UI, or the model can
            // never truthfully report that it did anything.
            #expect(
                definition.policy.executionMode != .requiresUserInterface,
                "\(definition.id.rawValue) is exposed to AI but needs native UI."
            )
        }
    }

    @Test func theCurrentReviewedToolSetIsExactlyWhatWeExpect() throws {
        // This is a deliberate tripwire: adding a new AI-exposed command must be a conscious,
        // reviewed change, not something that slips in with a feature.
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let host = makeHost(timerStore: store)

        let exposed = host.commandDefinitions()
            .filter { $0.policy.aiExposure == .reviewed }
            .map(\.id.rawValue)
            .sorted()

        #expect(exposed == ["timers.start"])
    }

    @Test func interactiveCommandsAreNeverOfferedAsTools() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let host = makeHost(timerStore: store)
        let evaluator = ModuleHostAIEligibilityEvaluator(host: host)

        for definition in host.commandDefinitions()
        where definition.policy.executionMode == .requiresUserInterface {
            #expect(evaluator.isEligible(definition) == false)
        }
    }

    @Test func aDisabledModuleWithdrawsItsTools() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let host = BuiltInModules.makeHost(
            timerStore: store,
            enablement: LauncherRegistryModuleEnablementProvider(
                registry: registry,
                manifests: BuiltInModules.assemblies(timerStore: store).map(\.manifest)
            )
        )
        let evaluator = ModuleHostAIEligibilityEvaluator(host: host)
        let start = try #require(
            host.commandDefinition(for: TimersModuleIdentifiers.startTool)
        )
        #expect(evaluator.isEligible(start))

        var preferences = registry.preferences(for: TimersApplication.applicationID)
        preferences.isEnabled = false
        registry.savePreferences(preferences, for: TimersApplication.applicationID)

        // Enablement is not an AI grant, and losing it withdraws the tool immediately.
        #expect(evaluator.isEligible(start) == false)
    }

    @Test func toolNamesAreProviderSafeAndUnique() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let host = makeHost(timerStore: store)
        let bridge = AICommandBridge(
            definitions: { host.commandDefinitions() },
            dispatcher: NeverCallingDispatcher(),
            eligibility: ModuleHostAIEligibilityEvaluator(host: host)
        )

        let tools = try bridge.availableTools()
        #expect(Set(tools.map(\.name)).count == tools.count)
        for tool in tools {
            #expect(throws: Never.self) { try tool.validate() }
        }
    }
}

/// Dispatcher that fails the test if anything reaches it.
///
/// Used where a test must prove that a call was rejected before execution.
@MainActor
private final class NeverCallingDispatcher: ModuleCommandDispatching {
    func dispatch(
        reference: CommandReference,
        grants: ModuleCallerGrants,
        context: CommandInvocationContext
    ) async -> ModuleCommandOutcome {
        Issue.record("No command should have been dispatched. Got \(reference.commandID.rawValue).")
        return .failed(message: "unexpected dispatch")
    }
}
