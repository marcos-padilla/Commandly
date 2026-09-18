import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
struct ScreenshotApplicationTests {
    @Test
    func allScreenshotEntriesUseSharedExecutionWithoutImplicitPermissionOrSelection() async throws {
        let permissions = ScreenshotLaunchPermissions()
        let factory = ScreenshotLaunchFactory()
        let services = ScreenshotApplicationServices(permissions: permissions, makeCapture: { factory.make() },
                                                     copier: ScreenshotLaunchCopier(), privacySettings: InMemoryPrivacySettingsOpener())
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        try registry.register(ScreenshotApplication(services: services))
        let commands = CommandRegistry()
        try await commands.replaceCatalog(with: registry.allManifests())
        let presenter = ScreenshotLaunchPresenter(registry: registry)
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: commands, executor: SharedCommandExecutor(applicationOpener: NoOpApplicationOpener(),
                registeredApplicationPresenter: presenter, installedApplicationUsageRecorder: ApplicationPreferencesInstalledApplicationUsageRecorder(
                    preferencesStore: InMemoryApplicationPreferencesStore())), usageHistory: InMemoryCommandUsageHistory())
        let sources: [CommandInvocationSource] = [.search, .applicationHotKey, .commandWheel(profileID: UUID(), pageID: UUID(), segmentID: UUID())]
        for (id, kind) in [(ScreenshotApplication.applicationID, ScreenshotKind.region), (ScreenshotApplication.regionToolID, .region),
                           (ScreenshotApplication.windowToolID, .window), (ScreenshotApplication.displayToolID, .display)] {
            for source in sources {
                _ = try await coordinator.execute(reference: CommandReference(commandID: id), context: CommandInvocationContext(source: source))
                let session = try #require(presenter.sessions.last)
                let model = try #require(session.model(as: ScreenshotViewModel.self))
                #expect(model.kind == kind && model.image == nil && model.isCapturing == false)
                #expect(session.primaryActionID == ScreenshotActionID.capture)
                session.stop()
            }
        }
        #expect(presenter.sessions.count == 12 && factory.calls == 0)
        #expect(await permissions.count() == 0)
        for id in [ScreenshotApplication.regionToolID, ScreenshotApplication.windowToolID, ScreenshotApplication.displayToolID] {
            #expect(registry.owningApplicationID(for: id) == ScreenshotApplication.applicationID)
        }
    }

    #if DEBUG
    @Test
    func generatedDebugCaptureProvidesValidReviewBytesForEachModeWithoutSystemInputs() async throws {
        for kind in ScreenshotKind.allCases {
            let services = ScreenshotDebugFixture.services
            let capture = services.makeCapture()
            let result = try await capture.capture(ScreenshotRequest(kind: kind))
            #expect(result.kind == kind && result.pixelWidth == 800 && result.pixelHeight == 450)
            #expect(result.pngData.starts(with: [137, 80, 78, 71]))
            try await services.copier.copyPNG(result.pngData)
            capture.cancel()
        }
    }
    #endif
}

@MainActor private final class ScreenshotLaunchPresenter: RegisteredLauncherApplicationPresenting {
    let registry: LauncherApplicationRegistry
    private(set) var sessions: [LauncherApplicationSession] = []
    init(registry: LauncherApplicationRegistry) { self.registry = registry }
    func presentRegisteredApplication(command: ResolvedCommand, context: CommandInvocationContext) async -> CommandResult? {
        guard let application = registry.application(for: ScreenshotApplication.applicationID) else { return nil }
        let launchContext = LauncherApplicationContext(navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        let launch = command.reference.commandID == ScreenshotApplication.applicationID ? application.launch(in: launchContext)
            : application.launch(toolID: command.reference.commandID, arguments: command.reference.arguments, in: launchContext)
        guard case .present(let session) = launch else { return nil }
        sessions.append(session)
        return .success(message: nil)
    }
}
@MainActor private final class ScreenshotLaunchFactory {
    private(set) var calls = 0
    func make() -> any ScreenshotCapturing { calls += 1; return ScreenshotLaunchCapture() }
}
@MainActor private final class ScreenshotLaunchCapture: ScreenshotCapturing {
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage { throw ScreenshotCaptureError.selectionUnavailable }
    func cancel() {}
}
private actor ScreenshotLaunchPermissions: PermissionServicing {
    private var calls = 0
    func state(for kind: PermissionKind) -> PermissionState { calls += 1; return .authorized }
    func request(_ kind: PermissionKind) -> PermissionState { calls += 1; return .authorized }
    func count() -> Int { calls }
}
nonisolated private struct ScreenshotLaunchCopier: ScreenshotCopying { func copyPNG(_ data: Data) async throws {} }
