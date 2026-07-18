import AppCore
import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

struct SharedCommandExecutionTests {
    @Test @MainActor
    func disabledRegisteredCommandStaysKnownAndIsRejectedEverywhere() async throws {
        let preferences = InMemoryLauncherApplicationPreferencesStore()
        let applicationRegistry = LauncherApplicationRegistry.makeBuiltIn(
            preferencesStore: preferences
        )
        var disabledPreferences = LauncherApplicationPreferences.empty
        disabledPreferences.isEnabled = false
        applicationRegistry.savePreferences(
            disabledPreferences,
            for: BuiltInCommandID.searchFiles
        )
        let snapshot = await ProductionCommandAvailabilityEvaluator(
            applicationRegistry: applicationRegistry,
            permissionService: InMemoryPermissionService(),
            installedApplicationQuery: InMemoryInstalledApplicationQuery()
        ).snapshot()
        let reference = CommandReference(commandID: BuiltInCommandID.searchFiles)
        let registry = CommandRegistry()
        try await registry.replaceCatalog(
            with: snapshot.manifests,
            availability: snapshot.availability
        )

        #expect(snapshot.manifests.contains { $0.id == reference.commandID })
        #expect(try await registry.resolve(reference: reference).availability == .unavailable(.disabled))
        let slot = try await availabilitySlot(reference: reference, snapshot: snapshot)
        #expect(slot.title == "Search Files")
        #expect(slot.availability == .unavailable(requiresPermission: false))

        let presenter = RecordingRegisteredApplicationPresenter()
        let coordinator = makeAvailabilityCoordinator(registry: registry, presenter: presenter)
        await #expect(
            throws: SharedCommandExecutionCoordinatorError.unavailable(
                commandID: reference.commandID,
                reason: .disabled
            )
        ) {
            try await coordinator.execute(
                reference: reference,
                context: CommandInvocationContext(source: .search)
            )
        }
        #expect(presenter.presentedCommandIDs.isEmpty)
    }

    @Test @MainActor
    func deniedPermissionIsUnavailableInSettingsAndSharedResolution() async throws {
        let applicationRegistry = LauncherApplicationRegistry.makeBuiltIn()
        let snapshot = await ProductionCommandAvailabilityEvaluator(
            applicationRegistry: applicationRegistry,
            permissionService: InMemoryPermissionService(
                states: [.accessibility: .denied]
            ),
            installedApplicationQuery: InMemoryInstalledApplicationQuery()
        ).snapshot()
        let reference = CommandReference(commandID: WindowLayoutsApplication.id)
        let registry = CommandRegistry()
        try await registry.replaceCatalog(
            with: snapshot.manifests,
            availability: snapshot.availability
        )

        #expect(
            try await registry.resolve(reference: reference).availability
                == .unavailable(.missingPermission(identifier: "accessibility"))
        )
        let slot = try await availabilitySlot(reference: reference, snapshot: snapshot)
        #expect(slot.title == "Window Layouts")
        #expect(slot.availability == .unavailable(requiresPermission: true))

        let presenter = RecordingRegisteredApplicationPresenter()
        let coordinator = makeAvailabilityCoordinator(registry: registry, presenter: presenter)
        await #expect(
            throws: SharedCommandExecutionCoordinatorError.unavailable(
                commandID: reference.commandID,
                reason: .missingPermission(identifier: "accessibility")
            )
        ) {
            try await coordinator.execute(
                reference: reference,
                context: CommandInvocationContext(source: .search)
            )
        }
        #expect(presenter.presentedCommandIDs.isEmpty)
    }

    @Test @MainActor
    func uninstalledApplicationReferenceStaysKnownAndIsRejectedBeforeOpening() async throws {
        let applicationRegistry = LauncherApplicationRegistry.makeBuiltIn()
        let snapshot = await ProductionCommandAvailabilityEvaluator(
            applicationRegistry: applicationRegistry,
            permissionService: InMemoryPermissionService(
                states: [.accessibility: .authorized]
            ),
            installedApplicationQuery: InMemoryInstalledApplicationQuery()
        ).snapshot()
        let reference = BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: "com.example.uninstalled"
        )
        let registry = CommandRegistry()
        try await registry.replaceCatalog(
            with: snapshot.manifests,
            availability: snapshot.availability
        )

        #expect(
            try await registry.resolve(reference: reference).availability
                == .unavailable(.missingDependency(identifier: "installed-application"))
        )
        let slot = try await availabilitySlot(reference: reference, snapshot: snapshot)
        #expect(slot.title == "Open Installed Application")
        #expect(slot.availability == .unavailable(requiresPermission: false))

        let opener = RecordingSharedCommandApplicationOpener()
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: registry,
            executor: SharedCommandExecutor(
                applicationOpener: opener,
                registeredApplicationPresenter: RecordingRegisteredApplicationPresenter(),
                installedApplicationUsageRecorder:
                    ApplicationPreferencesInstalledApplicationUsageRecorder(
                        preferencesStore: InMemoryApplicationPreferencesStore()
                    )
            ),
            usageHistory: InMemoryCommandUsageHistory()
        )
        await #expect(
            throws: SharedCommandExecutionCoordinatorError.unavailable(
                commandID: reference.commandID,
                reason: .missingDependency(identifier: "installed-application")
            )
        ) {
            try await coordinator.execute(
                reference: reference,
                context: CommandInvocationContext(source: .search)
            )
        }
        #expect(await opener.openedBundleIdentifiers().isEmpty)
    }

    @Test @MainActor
    func coordinatorErrorsExposeOneSanitizedUserFacingMapping() {
        let commandID = CommandID(rawValue: "test.error-mapping")

        #expect(
            SharedCommandExecutionCoordinatorError.registry(.commandNotFound(commandID))
                .userFacingMessage == "Command is unavailable."
        )
        #expect(
            SharedCommandExecutionCoordinatorError.registry(
                .missingRequiredArgument(commandID: commandID, name: "private-argument")
            ).userFacingMessage == "Command arguments are invalid."
        )
        #expect(
            SharedCommandExecutionCoordinatorError.executor(.applicationOpenFailed)
                .userFacingMessage == "Couldn’t open that application."
        )
        #expect(
            SharedCommandExecutionCoordinatorError.executionFailed(commandID)
                .userFacingMessage == "Command couldn’t be completed."
        )
    }

    @Test @MainActor
    func installedApplicationSearchAndWheelUseTheSameExecutorWithDistinctSources() async throws {
        let bundleIdentifier = "com.example.shared-command"
        let opener = RecordingSharedCommandApplicationOpener()
        let preferences = InMemoryApplicationPreferencesStore()
        let history = InMemoryCommandUsageHistory()
        let presenter = RecordingRegisteredApplicationPresenter()
        let registry = CommandRegistry()
        try await registry.register(BuiltInCommandManifest.openInstalledApplication)
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: registry,
            executor: SharedCommandExecutor(
                applicationOpener: opener,
                registeredApplicationPresenter: presenter,
                installedApplicationUsageRecorder:
                    ApplicationPreferencesInstalledApplicationUsageRecorder(
                        preferencesStore: preferences
                    )
            ),
            usageHistory: history,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 500))
        )
        var dismissCount = 0
        let launcher = LauncherViewModel(
            applicationRegistry: LauncherApplicationRegistry(),
            applicationOpener: opener,
            commandCoordinator: coordinator,
            invocationContextProvider: {
                CommandInvocationContext(
                    source: $0,
                    frontmostApplicationBundleIdentifier: "com.example.frontmost",
                    timestamp: Date(timeIntervalSince1970: 100)
                )
            },
            applicationQuery: InMemoryInstalledApplicationQuery(
                applications: [
                    InstalledApplication(
                        bundleIdentifier: bundleIdentifier,
                        name: "Shared Command",
                        path: "/Applications/Shared Command.app"
                    )
                ]
            ),
            applicationPreferencesStore: preferences,
            placeholderItems: [],
            onDismiss: { dismissCount += 1 }
        )

        launcher.query = "Shared Command"
        await launcher.flushSearchForTesting()
        launcher.selectedID = "app:\(bundleIdentifier)"
        await launcher.confirmSelectionAndWaitForTesting()

        let profileID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let pageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let segmentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))
        let wheelSource = CommandInvocationSource.commandWheel(
            profileID: profileID,
            pageID: pageID,
            segmentID: segmentID
        )
        let reference = BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: bundleIdentifier
        )
        let wheelResult = try await coordinator.execute(
            reference: reference,
            context: CommandInvocationContext(
                source: wheelSource,
                frontmostApplicationBundleIdentifier: "com.example.frontmost",
                timestamp: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(wheelResult == .success(message: nil))
        #expect(await opener.openedBundleIdentifiers() == [bundleIdentifier, bundleIdentifier])
        #expect(dismissCount == 1)
        let records = await history.records(for: BuiltInCommandID.openInstalledApplication)
        #expect(records.count == 2)
        #expect(records.contains { $0.source == .search && $0.outcome == .succeeded })
        #expect(records.contains { $0.source == wheelSource && $0.outcome == .succeeded })
        let summary = try #require(
            await history.summary(for: BuiltInCommandID.openInstalledApplication)
        )
        #expect(summary.successfulExecutionCount == 2)
        #expect(preferences.load().ranking(for: bundleIdentifier).openCount == 2)
        #expect(
            preferences.load().ranking(for: bundleIdentifier).lastOpenedAt
                == Date(timeIntervalSince1970: 200)
        )
    }

    @Test @MainActor
    func registeredCommandsDispatchThroughTheInjectedMainActorPresenter() async throws {
        let commandID = CommandID(rawValue: "test.registered-presentation")
        let registry = CommandRegistry()
        try await registry.register(
            CommandManifest(
                id: commandID,
                title: "Registered Presentation",
                systemImage: "rectangle.on.rectangle",
                category: .productivity,
                mode: .view
            )
        )
        let presenter = RecordingRegisteredApplicationPresenter()
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: registry,
            executor: SharedCommandExecutor(
                applicationOpener: NoOpApplicationOpener(),
                registeredApplicationPresenter: presenter,
                installedApplicationUsageRecorder:
                    ApplicationPreferencesInstalledApplicationUsageRecorder(
                        preferencesStore: InMemoryApplicationPreferencesStore()
                    )
            ),
            usageHistory: InMemoryCommandUsageHistory()
        )

        let result = try await coordinator.execute(
            reference: CommandReference(commandID: commandID),
            context: CommandInvocationContext(source: .search)
        )

        #expect(result == .success(message: nil))
        #expect(presenter.presentedCommandIDs == [commandID])
    }

    @Test @MainActor
    func applicationOpenFailureIsTypedAndPersistsNoSuccessfulUsage() async throws {
        let opener = RecordingSharedCommandApplicationOpener(shouldFail: true)
        let history = InMemoryCommandUsageHistory()
        let registry = CommandRegistry()
        try await registry.register(BuiltInCommandManifest.openInstalledApplication)
        let coordinator = SharedCommandExecutionCoordinator(
            resolver: registry,
            executor: SharedCommandExecutor(
                applicationOpener: opener,
                registeredApplicationPresenter: RecordingRegisteredApplicationPresenter(),
                installedApplicationUsageRecorder:
                    ApplicationPreferencesInstalledApplicationUsageRecorder(
                        preferencesStore: InMemoryApplicationPreferencesStore()
                    )
            ),
            usageHistory: history
        )

        do {
            _ = try await coordinator.execute(
                reference: BuiltInCommandReference.openInstalledApplication(
                    bundleIdentifier: "com.example.failure"
                ),
                context: CommandInvocationContext(source: .search)
            )
            Issue.record("Expected the installed-application adapter failure to be typed")
        } catch let error as SharedCommandExecutionCoordinatorError {
            #expect(error == .executor(.applicationOpenFailed))
        }

        let records = await history.records(for: BuiltInCommandID.openInstalledApplication)
        #expect(records.count == 1)
        #expect(records.first?.outcome == .failed)
        #expect(await history.summary(for: BuiltInCommandID.openInstalledApplication) == nil)
    }

    @Test @MainActor
    func userDefaultsHistoryDurablyRoundTripsAndBoundsPrivacySafeRecords() async throws {
        let suiteName = "CommandlyTests.CommandUsageHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let commandID = CommandID(rawValue: "test.durable-history")
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000202"))
        let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000203"))
        let store = UserDefaultsCommandUsageHistoryStore(
            suiteName: suiteName,
            maximumRecordCount: 3
        )

        await store.record(
            CommandExecutionRecord(
                id: firstID,
                commandID: commandID,
                source: .search,
                outcome: .succeeded,
                timestamp: Date(timeIntervalSince1970: 1)
            )
        )
        await store.record(
            CommandExecutionRecord(
                id: secondID,
                commandID: commandID,
                source: .applicationHotKey,
                outcome: .failed,
                timestamp: Date(timeIntervalSince1970: 2)
            )
        )
        await store.record(
            CommandExecutionRecord(
                id: thirdID,
                commandID: commandID,
                source: .search,
                outcome: .succeeded,
                timestamp: Date(timeIntervalSince1970: 3)
            )
        )

        let reloaded = UserDefaultsCommandUsageHistoryStore(
            suiteName: suiteName,
            maximumRecordCount: 2
        )
        let records = await reloaded.records(for: commandID)
        let summary = try #require(await reloaded.summary(for: commandID))

        #expect(records.map(\.id) == [secondID, thirdID])
        #expect(summary.successfulExecutionCount == 1)
        #expect(summary.lastSuccessfulExecutionAt == Date(timeIntervalSince1970: 3))
    }
}

@MainActor
private func makeAvailabilityCoordinator(
    registry: CommandRegistry,
    presenter: RecordingRegisteredApplicationPresenter
) -> SharedCommandExecutionCoordinator {
    SharedCommandExecutionCoordinator(
        resolver: registry,
        executor: SharedCommandExecutor(
            applicationOpener: NoOpApplicationOpener(),
            registeredApplicationPresenter: presenter,
            installedApplicationUsageRecorder:
                ApplicationPreferencesInstalledApplicationUsageRecorder(
                    preferencesStore: InMemoryApplicationPreferencesStore()
                )
        ),
        usageHistory: InMemoryCommandUsageHistory()
    )
}

@MainActor
private func availabilitySlot(
    reference: CommandReference,
    snapshot: CommandCatalogSnapshot
) async throws -> CommandWheelSlotPresentation {
    var configuration = CommandWheelDefaults.configuration
    configuration.isEnabled = true
    configuration.profiles[0].pages[0].segments[0].content = .command(reference)
    let model = CommandWheelSettingsModel(
        store: CommandWheelProfileStore(
            repository: InMemoryCommandWheelProfileRepository(configuration: configuration)
        ),
        catalog: CommandWheelCommandCatalogSnapshot(snapshot)
    )
    await model.load()
    return try #require(model.slotPresentations.first)
}

private enum SharedCommandExecutionTestError: Error {
    case failed
}

private actor RecordingSharedCommandApplicationOpener: ApplicationOpening {
    private let shouldFail: Bool
    private var bundleIdentifiers: [String] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func openApplication(bundleIdentifier: String) async throws {
        if shouldFail { throw SharedCommandExecutionTestError.failed }
        bundleIdentifiers.append(bundleIdentifier)
    }

    func openedBundleIdentifiers() -> [String] {
        bundleIdentifiers
    }
}

@MainActor
private final class RecordingRegisteredApplicationPresenter:
    RegisteredLauncherApplicationPresenting
{
    private(set) var presentedCommandIDs: [CommandID] = []

    func presentRegisteredApplication(commandID: CommandID) -> CommandResult? {
        presentedCommandIDs.append(commandID)
        return .success(message: nil)
    }
}
