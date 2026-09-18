import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
struct CameraApplicationTests {
    @Test
    func applicationAndToolsUseSharedExecutionWithoutStartingTheCamera() async throws {
        let permissions = CameraLaunchPermissions()
        let factory = CameraLaunchFactory()
        let copier = CameraLaunchCopier()
        let services = CameraApplicationServices(
            permissions: permissions, makeCapture: { factory.make() }, photoCopier: copier,
            privacySettingsOpener: InMemoryPrivacySettingsOpener()
        )
        let applications = LauncherApplicationRegistry.makeBuiltIn(cameraServices: services)
        let commands = CommandRegistry()
        try await commands.replaceCatalog(with: applications.allManifests())
        let presenter = CameraLaunchPresenter(registry: applications)
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: commands,
            executor: SharedCommandExecutor(
                applicationOpener: NoOpApplicationOpener(), registeredApplicationPresenter: presenter,
                installedApplicationUsageRecorder: ApplicationPreferencesInstalledApplicationUsageRecorder(
                    preferencesStore: InMemoryApplicationPreferencesStore()
                )
            ), usageHistory: InMemoryCommandUsageHistory()
        )
        let sources: [CommandInvocationSource] = [
            .search, .applicationHotKey, .commandWheel(profileID: UUID(), pageID: UUID(), segmentID: UUID())
        ]
        let IDs = [CameraApplication.applicationID, CameraApplication.openToolID, CameraApplication.selfieToolID]
        for id in IDs {
            #expect(applications.resolvedSettings(for: id)?.isEnabled == true)
            for source in sources {
                _ = try await coordinator.execute(reference: CommandReference(commandID: id), context: CommandInvocationContext(source: source))
                let session = try #require(presenter.sessions.last)
                let model = try #require(session.model(as: CameraViewModel.self))
                #expect(model.state == .idle && model.frame == nil && model.photo == nil)
                #expect(session.primaryActionID == CameraActionID.start)
                session.stop()
                #expect(model.state == .idle && model.showsFileExporter == false)
            }
        }
        #expect(presenter.sessions.count == 9)
        #expect(factory.calls == 0)
        #expect(await permissions.callCount() == 0)
        #expect(await copier.callCount() == 0)
        for toolID in [CameraApplication.openToolID, CameraApplication.selfieToolID] {
            #expect(applications.owningApplicationID(for: toolID) == CameraApplication.applicationID)
            #expect(applications.definition(for: toolID)?.kind == .tool)
        }
    }
}

@MainActor
private final class CameraLaunchPresenter: RegisteredLauncherApplicationPresenting {
    let registry: LauncherApplicationRegistry
    private(set) var sessions: [LauncherApplicationSession] = []
    init(registry: LauncherApplicationRegistry) { self.registry = registry }
    func presentRegisteredApplication(command: ResolvedCommand, context: CommandInvocationContext) async -> CommandResult? {
        guard let application = registry.application(for: CameraApplication.applicationID) else { return nil }
        let launchContext = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:])
        )
        let launch = command.reference.commandID == CameraApplication.applicationID
            ? application.launch(in: launchContext)
            : application.launch(toolID: command.reference.commandID, arguments: command.reference.arguments, in: launchContext)
        guard case .present(let session) = launch else { return nil }
        sessions.append(session)
        return .success(message: nil)
    }
}

@MainActor
private final class CameraLaunchFactory {
    private(set) var calls = 0
    func make() -> any CameraCapturing { calls += 1; return CameraLaunchCapture() }
}

private actor CameraLaunchCapture: CameraCapturing {
    func start(deviceID: String?) throws -> CameraCaptureSession { throw CameraCaptureError.noCamera }
    func takePhoto(mirrored: Bool) throws -> CameraPhoto { throw CameraCaptureError.captureUnavailable }
    func stop() {}
}

private actor CameraLaunchPermissions: PermissionServicing {
    private var calls = 0
    func state(for kind: PermissionKind) -> PermissionState { calls += 1; return .authorized }
    func request(_ kind: PermissionKind) -> PermissionState { calls += 1; return .authorized }
    func callCount() -> Int { calls }
}

private actor CameraLaunchCopier: CameraPhotoCopying {
    private var calls = 0
    func copyPNG(_ data: Data) { calls += 1 }
    func callCount() -> Int { calls }
}
