import Foundation
import AppKit
import Testing
@testable import Commandly
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability
import Infrastructure

struct CommandlyTests {
    @Test @MainActor func dependencyContainerBootstrapsToRootWhenOnboarded() {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        #expect(container.dependencies.metadata.name == "Commandly")
        #expect(container.appState.route == .root)
        let viewModel = container.makeRootViewModel()
        #expect(viewModel.status == "Foundation ready")
        #expect(viewModel.message == "Feature development has not started yet.")
    }

    @Test @MainActor func bootstrapShowsOnboardingWhenIncomplete() {
        let container = makeTestContainer(hasCompletedOnboarding: false)
        #expect(container.appState.route == .onboarding)
    }

    @Test @MainActor func routerUpdatesAppState() {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        container.router.navigate(to: .settings)
        #expect(container.appState.route == .settings)
    }

    @Test @MainActor func onboardingViewModelAdvancesToReady() {
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener()
        )

        #expect(viewModel.step == .welcome)
        #expect(viewModel.primaryActionTitle == "Start Setup")
        #expect(viewModel.canGoBack == false)

        viewModel.advance()
        #expect(viewModel.step == .features)
        #expect(viewModel.canGoBack == true)

        viewModel.goBack()
        #expect(viewModel.step == .welcome)

        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        #expect(viewModel.step == .ready)
        #expect(viewModel.primaryActionTitle == "Open Commandly")

        viewModel.advance()
        #expect(viewModel.hotkeyPhase == .celebrating)
        #expect(viewModel.hasConfirmedOptionSpaceHotkey == false)
    }

    @Test @MainActor func optionSpaceHotkeyConfirmsAndCelebrates() async {
        let settings = InMemoryAppSettingsStore()
        var finished = false
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .ready,
            onFinished: { finished = true }
        )

        viewModel.handleOptionSpaceHotkey()
        #expect(viewModel.hotkeyPhase == .celebrating)
        #expect(viewModel.hasConfirmedOptionSpaceHotkey)
        #expect(settings.load().hasConfirmedOptionSpaceHotkey)
        #expect(viewModel.showsPrimaryAction == false)

        await waitUntil(timeoutNanoseconds: 2_500_000_000) { finished }
        #expect(finished)
        #expect(viewModel.hotkeyPhase == .finished)
    }

    @Test @MainActor func pressedKeysUpdateFromMonitorCallback() {
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .ready
        )

        viewModel.updatePressedKeys([.a, .leftShift])
        #expect(viewModel.pressedKeyIDs == [.a, .leftShift])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 0) == [.a])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 49) == [.space])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 58) == [.leftOption])
    }

    @Test @MainActor func finishingOnboardingNavigatesToRoot() {
        let store = InMemoryOnboardingStatusStore()
        let container = makeTestContainer(
            hasCompletedOnboarding: false,
            onboardingStatusStore: store
        )
        #expect(container.appState.route == .onboarding)

        let viewModel = container.makeOnboardingViewModel()
        viewModel.finish()

        #expect(store.hasCompletedOnboarding)
        #expect(container.appState.route == .root)
    }

    @Test @MainActor func appRuntimeHidesOnboardingAfterFinishCallback() {
        let store = InMemoryOnboardingStatusStore()
        let container = makeTestContainer(
            hasCompletedOnboarding: false,
            onboardingStatusStore: store
        )
        let runtime = AppRuntime(container: container)
        #expect(runtime.showsOnboarding)

        let viewModel = runtime.makeOnboardingViewModel()
        viewModel.finish()

        #expect(runtime.showsOnboarding == false)
        #expect(container.appState.route == .root)
    }

    @Test @MainActor func settingsViewModelPersistsGeneralPreferences() {
        let settings = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .testing
            )
        )

        viewModel.setPrefersCommandlyEmojiPicker(true)
        viewModel.setAppearance(.dark)
        viewModel.setTextSize(.larger)
        viewModel.setShowMenuBarIcon(false)

        let loaded = settings.load()
        #expect(loaded.prefersCommandlyEmojiPicker)
        #expect(loaded.appearance == .dark)
        #expect(loaded.textSize == .larger)
        #expect(loaded.showMenuBarIcon == false)
    }

    @Test @MainActor func appRuntimeRestartOnboardingResetsProgress() async {
        let store = InMemoryOnboardingStatusStore(hasCompletedOnboarding: true)
        let settings = InMemoryAppSettingsStore(
            settings: AppSettings(
                opensAtLogin: true,
                prefersCommandlyEmojiPicker: true,
                hasConfirmedOptionSpaceHotkey: true,
                showMenuBarIcon: true,
                appearance: .dark,
                textSize: .larger
            )
        )
        let folderAccess = InMemoryFolderAccessStore(bookmarkData: [Data([0x01])], forceUsable: true)
        let container = makeTestContainer(
            hasCompletedOnboarding: true,
            onboardingStatusStore: store,
            appSettingsStore: settings,
            folderAccessStore: folderAccess
        )
        let runtime = AppRuntime(container: container)
        #expect(runtime.showsOnboarding == false)

        _ = runtime.makeOnboardingViewModel()
        runtime.restartOnboarding()

        #expect(store.hasCompletedOnboarding == false)
        #expect(settings.load() == .default)
        #expect(folderAccess.bookmarkData.isEmpty)
        #expect(runtime.showsOnboarding)
        #expect(container.appState.route == .onboarding)

        let restarted = runtime.makeOnboardingViewModel()
        #expect(restarted.step == .welcome)
    }

    @Test @MainActor func appDelegateKeepsRunningAfterWindowsClose() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
    }

    @Test @MainActor func setupTogglesPersistPreferences() async {
        let settings = InMemoryAppSettingsStore()
        let loginItems = InMemoryLoginItemManager()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: loginItems,
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .preferences
        )

        viewModel.setPrefersCommandlyEmojiPicker(true)
        #expect(settings.load().prefersCommandlyEmojiPicker)

        viewModel.setOpensAtLogin(true)
        await waitUntil {
            await loginItems.status() == .enabled && settings.load().opensAtLogin
        }

        #expect(viewModel.opensAtLogin)
        #expect(settings.load().opensAtLogin)
        #expect(await loginItems.status() == .enabled)

        viewModel.setOpensAtLogin(false)
        await waitUntil {
            await loginItems.status() == .disabled && settings.load().opensAtLogin == false
        }

        #expect(viewModel.opensAtLogin == false)
        #expect(settings.load().opensAtLogin == false)
        #expect(await loginItems.status() == .disabled)
    }

    @Test @MainActor func openAtLoginFailureRevertsPreference() async {
        let settings = InMemoryAppSettingsStore()
        let loginItems = InMemoryLoginItemManager(shouldFail: true)
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: loginItems,
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .preferences
        )

        viewModel.setOpensAtLogin(true)
        await waitUntil {
            viewModel.loginItemErrorMessage != nil
        }

        #expect(viewModel.opensAtLogin == false)
        #expect(settings.load().opensAtLogin == false)
        #expect(viewModel.loginItemErrorMessage != nil)
    }

    @Test @MainActor func permissionGrantUpdatesStatus() async {
        let permissions = InMemoryPermissionService()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: permissions,
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .permissions
        )

        await viewModel.preparePermissionsStep()
        #expect(viewModel.status(for: .filesAndFolders).state == .notDetermined)

        viewModel.handlePermissionAction(.filesAndFolders)
        await waitUntil {
            viewModel.status(for: .filesAndFolders).state == .authorized
        }

        #expect(viewModel.status(for: .filesAndFolders).state == .authorized)
        #expect(await permissions.state(for: .files) == .authorized)
    }

    @Test @MainActor func deniedPermissionOpensSettingsRecovery() async {
        let permissions = InMemoryPermissionService(states: [.accessibility: .denied])
        let opener = RecordingPrivacySettingsOpener()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: permissions,
            privacySettingsOpener: opener,
            initialStep: .permissions
        )

        await viewModel.preparePermissionsStep()
        #expect(viewModel.status(for: .accessibility).state == .denied)

        viewModel.handlePermissionAction(.accessibility)
        await waitUntil {
            opener.openedPanes.contains(.accessibility)
        }

        #expect(opener.openedPanes == [.accessibility])
    }

    @MainActor
    private func makeTestContainer(
        hasCompletedOnboarding: Bool,
        onboardingStatusStore: InMemoryOnboardingStatusStore? = nil,
        appSettingsStore: InMemoryAppSettingsStore? = nil,
        folderAccessStore: InMemoryFolderAccessStore? = nil
    ) -> AppContainer {
        let store = onboardingStatusStore
            ?? InMemoryOnboardingStatusStore(hasCompletedOnboarding: hasCompletedOnboarding)
        let metadata = ApplicationMetadata(
            name: "Commandly",
            version: "1.0",
            build: "1",
            bundleIdentifier: "com.businessmate360.Commandly",
            environment: .testing
        )
        let fixedUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")
            ?? UUID()
        let dependencies = AppDependencies(
            metadata: metadata,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1_700_000_000)),
            uuidProvider: FixedUUIDProvider(uuid: fixedUUID),
            commandRegistry: CommandRegistry(),
            persistenceStore: InMemoryPersistenceStore(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            onboardingStatusStore: store,
            appSettingsStore: appSettingsStore ?? InMemoryAppSettingsStore(),
            folderAccessStore: folderAccessStore ?? InMemoryFolderAccessStore(),
            loginItemManager: InMemoryLoginItemManager(),
            logger: Loggers.application
        )
        return AppContainer(dependencies: dependencies)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let started = ContinuousClock.now
        while ContinuousClock.now - started < .nanoseconds(timeoutNanoseconds) {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// Test double that records privacy pane open requests.
private final class RecordingPrivacySettingsOpener: PrivacySettingsOpening, @unchecked Sendable {
    private(set) var openedPanes: [PrivacySettingsPane] = []

    func open(_ pane: PrivacySettingsPane) async {
        openedPanes.append(pane)
    }
}
