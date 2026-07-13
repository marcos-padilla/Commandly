import CommandKit
import Foundation
import Testing
@testable import Commandly

struct SystemActivityApplicationTests {
    @Test @MainActor func protectionTrackerPreservesTheAppActiveBeforeCommandly() {
        let frontmostProcessIdentifier = SystemActivityProcessIdentifierBox(value: 101)
        let tracker = SystemActivityProtectionTracker(
            commandlyProcessIdentifier: 999,
            frontmostProcessIdentifier: { frontmostProcessIdentifier.value }
        )

        #expect(tracker.protectedProcessIdentifier == 101)

        frontmostProcessIdentifier.value = 999
        tracker.captureFrontmostApplication()
        #expect(tracker.protectedProcessIdentifier == 101)

        frontmostProcessIdentifier.value = 202
        tracker.captureFrontmostApplication()
        #expect(tracker.protectedProcessIdentifier == 202)
    }

    @Test @MainActor func applicationBuildsSessionAndLoadsImmutableSnapshot() async throws {
        let expected = makeSnapshot(
            applications: [
                application(pid: 301, name: "Notes", bundleIdentifier: "com.apple.Notes")
            ]
        )
        let service = FakeSystemActivityService(snapshot: expected)
        let application = SystemActivityApplication(service: service)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )

        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected System Activity to present an application session")
            return
        }
        let model = try #require(session.model(as: SystemActivityViewModel.self))
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        #expect(application.definition.id == SystemActivityApplicationID.command)
        #expect(application.definition.kind == .application)
        #expect(application.definition.commandManifest?.mode == .view)
        #expect(model.snapshot == expected)
        #expect(model.selectedApplication?.localizedName == "Notes")
    }

    @Test @MainActor func forceQuitRequiresExplicitConfirmationBeforeServiceCall() async throws {
        let target = application(
            pid: 401,
            name: "Drafts",
            bundleIdentifier: "com.example.Drafts"
        )
        let service = FakeSystemActivityService(snapshot: makeSnapshot(applications: [target]))
        let model = makeModel(service: service)
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()
        model.setMode(.applications)

        model.requestForceQuitSelectedApplication()

        #expect(model.pendingConfirmation == .forceQuit(target))
        #expect(await service.recordedTerminations().isEmpty)

        model.confirmPendingAction()
        await model.waitForOperationForTesting()

        #expect(model.pendingConfirmation == nil)
        #expect(
            await service.recordedTerminations()
                == [TerminationCall(processIdentifier: 401, mode: .force)]
        )
        #expect(model.statusMessage == "Force quit Drafts.")
    }

    @Test @MainActor func quitAllProtectsCommandlyFinderAndFrontmostAndReportsFailures() async throws {
        let commandly = application(
            pid: 900,
            name: "Commandly",
            bundleIdentifier: "com.example.Commandly"
        )
        let finder = application(
            pid: 901,
            name: "Finder",
            bundleIdentifier: "com.apple.finder"
        )
        let frontmost = application(
            pid: 902,
            name: "Pages",
            bundleIdentifier: "com.apple.Pages",
            isFrontmost: true
        )
        let succeeds = application(
            pid: 903,
            name: "Preview",
            bundleIdentifier: "com.apple.Preview"
        )
        let fails = application(
            pid: 904,
            name: "Messages",
            bundleIdentifier: "com.apple.MobileSMS"
        )
        let service = FakeSystemActivityService(
            snapshot: makeSnapshot(
                applications: [commandly, finder, frontmost, succeeds, fails]
            ),
            terminationResults: [903: true, 904: false]
        )
        let model = makeModel(service: service)
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        model.requestQuitAllApplications()
        guard case .quitAll(let candidates) = model.pendingConfirmation else {
            Issue.record("Expected an explicit quit-all confirmation")
            return
        }
        #expect(candidates.map(\.processIdentifier) == [903, 904])
        #expect(await service.recordedTerminations().isEmpty)

        model.confirmPendingAction()
        await model.waitForOperationForTesting()

        #expect(
            await service.recordedTerminations()
                == [
                    TerminationCall(processIdentifier: 903, mode: .graceful),
                    TerminationCall(processIdentifier: 904, mode: .graceful)
                ]
        )
        #expect(model.statusMessage?.contains("Quit 1 application.") == true)
        #expect(model.statusMessage?.contains("Couldn’t quit Messages.") == true)
    }

    @Test @MainActor func activationUsesServiceAndDismissesOnlyOnSuccess() async {
        let target = application(
            pid: 501,
            name: "Calendar",
            bundleIdentifier: "com.apple.iCal"
        )
        let service = FakeSystemActivityService(
            snapshot: makeSnapshot(applications: [target]),
            activationResults: [501: true]
        )
        var didDismiss = false
        let model = SystemActivityViewModel(
            service: service,
            commandlyProcessIdentifier: 900,
            commandlyBundleIdentifier: "com.example.Commandly",
            onGoBack: {},
            onDismiss: { didDismiss = true }
        )
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        model.activateSelectedApplication()
        await model.waitForOperationForTesting()

        #expect(await service.recordedActivations() == [501])
        #expect(didDismiss)
    }

    @Test @MainActor func applicationFilteringSupportsNameBundleIdentifierAndPID() async {
        let service = FakeSystemActivityService(
            snapshot: makeSnapshot(
                applications: [
                    application(
                        pid: 601,
                        name: "TextEdit",
                        bundleIdentifier: "com.apple.TextEdit"
                    ),
                    application(
                        pid: 602,
                        name: "Preview",
                        bundleIdentifier: "com.apple.Preview"
                    )
                ]
            )
        )
        let model = makeModel(service: service)
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        model.query = "preview"
        #expect(model.filteredApplications.map(\.processIdentifier) == [602])
        model.query = "TextEdit"
        #expect(model.filteredApplications.map(\.processIdentifier) == [601])
        model.query = "602"
        #expect(model.filteredApplications.map(\.processIdentifier) == [602])
    }

    @MainActor
    private func makeModel(service: FakeSystemActivityService) -> SystemActivityViewModel {
        SystemActivityViewModel(
            service: service,
            commandlyProcessIdentifier: 900,
            commandlyBundleIdentifier: "com.example.Commandly",
            onGoBack: {},
            onDismiss: {}
        )
    }

    private func makeSnapshot(
        applications: [SystemApplicationSnapshot]
    ) -> SystemActivitySnapshot {
        SystemActivitySnapshot(
            resources: SystemResourceSnapshot(
                sampledAt: Date(timeIntervalSince1970: 1_800_000_000),
                cpuUsage: 0.25,
                memoryUsedBytes: 8_000,
                memoryTotalBytes: 16_000,
                diskUsedBytes: 200_000,
                diskTotalBytes: 500_000,
                systemUptime: 86_400,
                thermalState: .nominal
            ),
            applications: applications
        )
    }

    private func application(
        pid: Int32,
        name: String,
        bundleIdentifier: String,
        isFrontmost: Bool = false
    ) -> SystemApplicationSnapshot {
        SystemApplicationSnapshot(
            processIdentifier: pid,
            bundleIdentifier: bundleIdentifier,
            localizedName: name,
            isFrontmost: isFrontmost,
            isHidden: false
        )
    }
}

@MainActor
private final class SystemActivityProcessIdentifierBox {
    var value: pid_t?

    init(value: pid_t?) {
        self.value = value
    }
}

private nonisolated struct TerminationCall: Sendable, Equatable {
    let processIdentifier: Int32
    let mode: SystemApplicationTerminationMode
}

private actor FakeSystemActivityService: SystemActivityServicing {
    private let currentSnapshot: SystemActivitySnapshot
    private let activationResults: [Int32: Bool]
    private let terminationResults: [Int32: Bool]
    private var activations: [Int32] = []
    private var terminations: [TerminationCall] = []

    init(
        snapshot: SystemActivitySnapshot,
        activationResults: [Int32: Bool] = [:],
        terminationResults: [Int32: Bool] = [:]
    ) {
        currentSnapshot = snapshot
        self.activationResults = activationResults
        self.terminationResults = terminationResults
    }

    func snapshot() async throws -> SystemActivitySnapshot {
        try Task.checkCancellation()
        return currentSnapshot
    }

    func activate(processIdentifier: Int32) async -> Bool {
        activations.append(processIdentifier)
        return activationResults[processIdentifier] ?? false
    }

    func terminate(
        processIdentifier: Int32,
        mode: SystemApplicationTerminationMode
    ) async -> Bool {
        terminations.append(
            TerminationCall(processIdentifier: processIdentifier, mode: mode)
        )
        return terminationResults[processIdentifier] ?? true
    }

    func recordedActivations() -> [Int32] {
        activations
    }

    func recordedTerminations() -> [TerminationCall] {
        terminations
    }
}
