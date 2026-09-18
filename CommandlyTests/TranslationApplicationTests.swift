import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Translate registration", .timeLimit(.minutes(1)))
@MainActor
struct TranslationApplicationTests {
    @Test
    func textAndWordEntriesUseSharedExecutionWithoutImplicitNativeWork() async throws {
        let harness = TranslationTestHarness()
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        try registry.register(TranslationApplication(services: harness.services()))
        let commands = CommandRegistry()
        try await commands.replaceCatalog(with: registry.allManifests())
        let presenter = TranslationLaunchPresenter(registry: registry)
        let coordinator = SharedCommandExecutionCoordinator(resolver: commands,
            executor: SharedCommandExecutor(applicationOpener: NoOpApplicationOpener(), registeredApplicationPresenter: presenter,
                installedApplicationUsageRecorder: ApplicationPreferencesInstalledApplicationUsageRecorder(preferencesStore: InMemoryApplicationPreferencesStore())),
            usageHistory: InMemoryCommandUsageHistory())
        let sources: [CommandInvocationSource] = [.search, .applicationHotKey, .commandWheel(profileID: UUID(), pageID: UUID(), segmentID: UUID())]
        for (id, word) in [(TranslationApplication.applicationID, false), (TranslationApplication.wordToolID, true)] {
            for source in sources {
                _ = try await coordinator.execute(reference: CommandReference(commandID: id), context: CommandInvocationContext(source: source))
                let session = try #require(presenter.sessions.last)
                let model = try #require(session.model(as: TranslationViewModel.self))
                #expect(model.isWordMode == word && model.input.isEmpty && model.result == nil && !model.isBusy)
                #expect(session.primaryActionID == TranslationActionID.translate)
                session.stop()
            }
        }
        #expect(presenter.sessions.count == 6)
        #expect(harness.translator.requests.isEmpty && harness.translator.preparations.isEmpty)
        #expect(await harness.catalog.catalogCalls == 0)
        #expect(await harness.copier.values.isEmpty)
        #expect(registry.owningApplicationID(for: TranslationApplication.wordToolID) == TranslationApplication.applicationID)
    }

    @Test
    func separateLiveLauncherSessionsNeverShareTheirViewBoundNativeBridge() throws {
        // Construction only: no native session, catalog API, clipboard access, model download, or translation.
        let assembly = TranslationApplicationServices.live
        let first = assembly.freshSession()
        let second = assembly.freshSession()
        let firstBridge = try #require(first.nativeBridge)
        let secondBridge = try #require(second.nativeBridge)
        #expect(firstBridge !== secondBridge)
        #expect(firstBridge.operation == nil && secondBridge.operation == nil)
        firstBridge.cancel()
        #expect(secondBridge.operation == nil)
    }
}

@MainActor private final class TranslationLaunchPresenter: RegisteredLauncherApplicationPresenting {
    let registry: LauncherApplicationRegistry
    private(set) var sessions: [LauncherApplicationSession] = []
    init(registry: LauncherApplicationRegistry) { self.registry = registry }
    func presentRegisteredApplication(command: ResolvedCommand, context: CommandInvocationContext) async -> CommandResult? {
        guard let application = registry.application(for: TranslationApplication.applicationID) else { return nil }
        let launchContext = LauncherApplicationContext(navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        let launch = command.reference.commandID == TranslationApplication.applicationID ? application.launch(in: launchContext)
            : application.launch(toolID: command.reference.commandID, arguments: command.reference.arguments, in: launchContext)
        guard case .present(let session) = launch else { return nil }
        sessions.append(session)
        return .success(message: nil)
    }
}
