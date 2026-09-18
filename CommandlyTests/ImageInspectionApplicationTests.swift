import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct ImageInspectionApplicationTests {
    @Test
    func textAndQRToolsUseTheSharedExecutorAcrossSearchHotkeysAndCommandWheel() async throws {
        let recognizer = NeverInvokedImageRecognizer()
        let applications = LauncherApplicationRegistry.makeBuiltIn(imageRecognitionService: recognizer)
        let commands = CommandRegistry()
        try await commands.replaceCatalog(with: applications.allManifests())
        let presenter = ImageInspectionTestPresenter(registry: applications)
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: commands,
            executor: SharedCommandExecutor(
                applicationOpener: NoOpApplicationOpener(),
                registeredApplicationPresenter: presenter,
                installedApplicationUsageRecorder: ApplicationPreferencesInstalledApplicationUsageRecorder(
                    preferencesStore: InMemoryApplicationPreferencesStore()
                )
            ),
            usageHistory: InMemoryCommandUsageHistory()
        )
        let sources: [CommandInvocationSource] = [
            .search, .applicationHotKey,
            .commandWheel(profileID: UUID(), pageID: UUID(), segmentID: UUID())
        ]
        for (toolID, mode) in [(ImageToolsApplication.extractTextToolID, ImageToolsMode.text), (ImageToolsApplication.decodeQRToolID, .qr)] {
            #expect(applications.owningApplicationID(for: toolID) == ImageToolsApplication.applicationID)
            #expect(applications.resolvedSettings(for: toolID)?.isEnabled == true)
            let definition = try #require(applications.definition(for: toolID))
            #expect(definition.kind == .tool && definition.parentID == ImageToolsApplication.applicationID)
            for source in sources {
                let count = presenter.sessions.count
                _ = try await coordinator.execute(reference: CommandReference(commandID: toolID), context: CommandInvocationContext(source: source))
                #expect(presenter.sessions.count == count + 1)
                let session = try #require(presenter.sessions.last)
                let model = try #require(session.model(as: ImageToolsViewModel.self))
                #expect(model.mode == mode && model.showsImageImporter)
                #expect(model.source == nil && model.inspection?.result == nil)
                session.stop()
                #expect(model.showsImageImporter == false)
            }
        }
        #expect(await recognizer.callCount() == 0)
        #expect(presenter.invocationSources == sources + sources)
    }
}

@MainActor
private final class ImageInspectionTestPresenter: RegisteredLauncherApplicationPresenting {
    let registry: LauncherApplicationRegistry
    private(set) var sessions: [LauncherApplicationSession] = []
    private(set) var invocationSources: [CommandInvocationSource] = []
    init(registry: LauncherApplicationRegistry) { self.registry = registry }
    func presentRegisteredApplication(command: ResolvedCommand, context: CommandInvocationContext) async -> CommandResult? {
        guard let application = registry.application(for: ImageToolsApplication.applicationID) else { return nil }
        let launchContext = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:])
        )
        guard case .present(let session) = application.launch(
            toolID: command.reference.commandID, arguments: command.reference.arguments, in: launchContext
        ) else { return nil }
        sessions.append(session)
        invocationSources.append(context.source)
        return .success(message: nil)
    }
}

private actor NeverInvokedImageRecognizer: ImageRecognizing {
    private var calls = 0
    func recognize(_ source: ImageConversionSource, mode: ImageRecognitionMode) -> ImageRecognitionResult {
        calls += 1
        return ImageRecognitionResult()
    }
    func callCount() -> Int { calls }
}
