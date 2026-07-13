import Foundation
import Observation
import Infrastructure
import AppKit
import CommandKit
import Observability

/// Observable app runtime for scene-level UI that must react to onboarding completion.
@Observable
@MainActor
final class AppRuntime {
    let container: AppContainer
    var showsOnboarding: Bool
    var showMenuBarIcon: Bool
    var textSize: AppTextSizePreference
    var viewMode: AppViewModePreference
    var showsLauncher: Bool = false
    /// Registered by a live SwiftUI scene so hotkeys can open the launcher window.
    var openLauncherWindow: (() -> Void)?
    var dismissLauncherWindow: (() -> Void)?
    private var cachedSettingsViewModel: SettingsViewModel?
    private var cachedLauncherViewModel: LauncherViewModel?
    private let hotkeyMonitor = OptionSpaceHotkeyMonitor()
    private let applicationHotkeyMonitor = ApplicationHotkeyMonitor()
    private var pendingApplicationID: CommandID?
    private(set) var applicationHotkeyIssues: [CommandID: ApplicationHotkeyRegistrationIssue] = [:]
    @ObservationIgnored
    let applicationRegistry: LauncherApplicationRegistry
    /// Pasteboard monitoring must not invalidate scene/`@Bindable` runtime UI.
    /// Views that need history observe the store through application models.
    @ObservationIgnored
    let clipboardHistoryStore: ClipboardHistoryStore
    @ObservationIgnored
    let fileSearchService: PersistentFileSearchService
    @ObservationIgnored
    let calculatorSessionStore: CalculatorSessionStore
    @ObservationIgnored
    private let fileSearchApplicationServices: FileSearchApplicationServices
    @ObservationIgnored
    private let windowLayoutService: AccessibilityWindowLayoutService
    @ObservationIgnored
    private let systemActivityProtectionTracker: SystemActivityProtectionTracker
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    private let autoQuitService: AutoQuitService

    init(container: AppContainer = .bootstrap()) {
        self.container = container
        let settings = container.dependencies.appSettingsStore.load()
        self.showsOnboarding = CommandlyDebugLaunchOptions.skipsOnboarding
            ? false
            : container.appState.route == .onboarding
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.textSize = settings.textSize
        self.viewMode = settings.viewMode
        let clipboardHistoryStore = ClipboardHistoryStore(
            enricher: VisionClipboardContentEnricher()
        )
        self.clipboardHistoryStore = clipboardHistoryStore
        #if DEBUG
        let fixture = CommandlyFileSearchDebugFixture.prepareIfRequested()
        let fileSearchService = PersistentFileSearchService(
            folderAccessStore: container.dependencies.folderAccessStore,
            databaseURL: fixture?.databaseURL,
            directAuthorizedScopes: fixture.map { [$0.rootURL] } ?? []
        )
        #else
        let fileSearchService = PersistentFileSearchService(
            folderAccessStore: container.dependencies.folderAccessStore
        )
        #endif
        self.fileSearchService = fileSearchService
        let calculatorSessionStore = CalculatorSessionStore()
        self.calculatorSessionStore = calculatorSessionStore
        let pasteboard = SystemPasteboard()
        let fileSearchApplicationServices = FileSearchApplicationServices(
            searchService: fileSearchService,
            urlOpener: WorkspaceURLOpener(),
            fileRevealer: WorkspaceFileRevealer(),
            fileActionService: WorkspaceFileActionService(),
            finderInfoPresenter: FinderAppleScriptInfoPresenter(),
            pasteboard: pasteboard
        )
        self.fileSearchApplicationServices = fileSearchApplicationServices
        let productivityLibraryServices = ProductivityLibraryApplicationServices(
            persistence: JSONProductivityLibraryStore(),
            pasteboard: pasteboard,
            urlOpener: fileSearchApplicationServices.urlOpener
        )
        let offlineToolsServices = OfflineToolsServices(pasteboard: pasteboard)
        let windowLayoutService = AccessibilityWindowLayoutService(
            permissionService: container.dependencies.permissionService
        )
        self.windowLayoutService = windowLayoutService
        let windowLayoutsServices = WindowLayoutsApplicationServices(
            layoutService: windowLayoutService,
            customStore: UserDefaultsCustomWindowLayoutStore()
        )
        let systemActivityProtectionTracker = SystemActivityProtectionTracker()
        self.systemActivityProtectionTracker = systemActivityProtectionTracker
        self.applicationRegistry = .makeBuiltIn(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchServices: fileSearchApplicationServices,
            calculatorSessionStore: calculatorSessionStore,
            timerStore: TimerStore(),
            productivityLibraryServices: productivityLibraryServices,
            offlineToolsServices: offlineToolsServices,
            windowLayoutsServices: windowLayoutsServices,
            systemActivityService: NativeSystemActivityService(
                protectionTracker: systemActivityProtectionTracker
            ),
            preferencesStore: container.dependencies.launcherApplicationPreferencesStore
        )
        let applicationPreferencesStore = container.dependencies.applicationPreferencesStore
        self.applicationPreferencesStore = applicationPreferencesStore
        self.autoQuitService = AutoQuitService(preferencesStore: applicationPreferencesStore)
        startHotkeyMonitor()
        refreshApplicationHotkeys()
        registerApplicationManifests()
        clipboardHistoryStore.startMonitoring()
        if showsOnboarding == false {
            autoQuitService.start()
        }
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        container.makeOnboardingViewModel { [weak self] in
            self?.onboardingDidFinish()
        }
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        if let cachedSettingsViewModel {
            return cachedSettingsViewModel
        }
        let viewModel = container.makeSettingsViewModel(
            onMenuBarIconChange: { [weak self] showIcon in
                self?.showMenuBarIcon = showIcon
            },
            onTextSizeChange: { [weak self] textSize in
                self?.textSize = textSize
            },
            onViewModeChange: { [weak self] viewMode in
                self?.viewMode = viewMode
            },
            applicationRegistry: applicationRegistry,
            onApplicationPreferencesChange: { [weak self] in
                self?.applicationPreferencesDidChange()
            },
            applicationHotkeyIssues: { [weak self] in
                self?.applicationHotkeyIssues ?? [:]
            }
        )
        cachedSettingsViewModel = viewModel
        return viewModel
    }

    func makeLauncherViewModel(
        onOpenSettings: @escaping () -> Void
    ) -> LauncherViewModel {
        let quit: () -> Void = {
            NSApplication.shared.terminate(nil)
        }
        if let cachedLauncherViewModel {
            cachedLauncherViewModel.onDismiss = { [weak self] in
                self?.hideLauncher()
            }
            cachedLauncherViewModel.onOpenSettings = onOpenSettings
            cachedLauncherViewModel.onQuit = quit
            return cachedLauncherViewModel
        }
        let viewModel = LauncherViewModel(
            applicationRegistry: applicationRegistry,
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchService: fileSearchService,
            urlOpener: fileSearchApplicationServices.urlOpener,
            applicationOpener: WorkspaceApplicationOpener(),
            applicationQuery: WorkspaceInstalledApplicationQuery(),
            applicationPreferencesStore: applicationPreferencesStore,
            fileRevealer: fileSearchApplicationServices.fileRevealer,
            fileActionService: fileSearchApplicationServices.fileActionService,
            bundleManager: WorkspaceApplicationBundleManager(),
            finderInfoPresenter: fileSearchApplicationServices.finderInfoPresenter,
            uninstallDiscoverer: WorkspaceApplicationUninstallDiscoverer(),
            pasteboard: fileSearchApplicationServices.pasteboard,
            calculatorSession: calculatorSessionStore,
            onDismiss: { [weak self] in
                self?.hideLauncher()
            },
            onOpenSettings: onOpenSettings,
            onQuit: quit
        )
        cachedLauncherViewModel = viewModel
        return viewModel
    }

    func consumePendingApplicationLaunch(using viewModel: LauncherViewModel) {
        guard let pendingApplicationID else { return }
        self.pendingApplicationID = nil
        viewModel.launch(pendingApplicationID)
    }

    func toggleLauncher() {
        if showsOnboarding {
            return
        }
        if showsLauncher {
            hideLauncher()
        } else {
            showLauncher()
        }
    }

    func showLauncher() {
        guard showsOnboarding == false else { return }
        systemActivityProtectionTracker.captureFrontmostApplication()
        windowLayoutService.captureTargetApplication()
        let alreadyShowing = showsLauncher
        showsLauncher = true
        openLauncherWindow?()
        NSApp.activate(ignoringOtherApps: true)
        // Always re-raise after the next runloop turn so reopen works when SwiftUI
        // reuses an existing NSWindow that was previously ordered out.
        DispatchQueue.main.async {
            BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.launcher)
            // If the window was already "showing" but invisible, force another open.
            if alreadyShowing {
                self.openLauncherWindow?()
                BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.launcher)
            }
            // `onAppear` may not fire when SwiftUI reuses an ordered-out window.
            // Bump search focus after the window has been raised so the field can
            // reclaim first responder on every presentation.
            self.cachedLauncherViewModel?.requestSearchFocus()
        }
    }

    func hideLauncher() {
        // Drop command-surface observation (e.g. clipboard entries) so background
        // pasteboard polls cannot refresh a dismissed launcher view hierarchy.
        cachedLauncherViewModel?.resetAfterDismiss()
        guard showsLauncher else {
            dismissLauncherWindow?()
            return
        }
        showsLauncher = false
        dismissLauncherWindow?()
    }

    /// DEBUG helper: clears first-run progress and presents onboarding again.
    func restartOnboarding() {
        let dependencies = container.dependencies
        dependencies.onboardingStatusStore.resetOnboardingCompletion()
        dependencies.appSettingsStore.save(.default)
        dependencies.folderAccessStore.saveBookmarks([])
        container.clearOnboardingViewModelCache()
        cachedSettingsViewModel = nil
        cachedLauncherViewModel = nil
        hideLauncher()
        container.router.navigate(to: .onboarding)
        showsOnboarding = true
        showMenuBarIcon = true
        textSize = .standard
        viewMode = .comfortable
        autoQuitService.stop()

        let logger = dependencies.logger
        Task {
            do {
                try await dependencies.loginItemManager.setEnabled(false)
            } catch {
                logger.error("Could not disable the login item while resetting onboarding")
            }
        }
    }

    /// Called when onboarding finishes so background services can start.
    func onboardingDidFinish() {
        showsOnboarding = false
        autoQuitService.start()
    }

    private func startHotkeyMonitor() {
        hotkeyMonitor.start { [weak self] in
            Task { @MainActor in
                self?.toggleLauncher()
            }
        }
    }

    private func applicationPreferencesDidChange() {
        refreshApplicationHotkeys()
        cachedLauncherViewModel?.applicationPreferencesDidChange()
    }

    private func refreshApplicationHotkeys() {
        let hotKeys: [(CommandID, LauncherHotKey)] = applicationRegistry
            .allDefinitions()
            .compactMap { definition -> (CommandID, LauncherHotKey)? in
                guard applicationRegistry.isEffectivelyEnabled(definition.id),
                      let hotKey = applicationRegistry.resolvedSettings(for: definition.id)?.hotKey,
                      applicationRegistry.application(for: definition.id) != nil else {
                    return nil
                }
                return (definition.id, hotKey)
            }
        applicationHotkeyIssues = applicationHotkeyMonitor.replace(hotKeys) { [weak self] id in
            self?.openApplicationFromHotKey(id)
        }
    }

    private func openApplicationFromHotKey(_ id: CommandID) {
        guard applicationRegistry.isEffectivelyEnabled(id) else { return }
        pendingApplicationID = id
        showLauncher()
        DispatchQueue.main.async { [weak self] in
            guard let self, let viewModel = self.cachedLauncherViewModel else { return }
            self.consumePendingApplicationLaunch(using: viewModel)
        }
    }

    private func registerApplicationManifests() {
        let registry = container.dependencies.commandRegistry
        let manifests = applicationRegistry.allManifests()
        let logger = container.dependencies.logger
        Task {
            do {
                for manifest in manifests {
                    try await registry.register(manifest)
                }
            } catch {
                logger.error("A built-in launcher application manifest failed registration")
            }
        }
    }

}
