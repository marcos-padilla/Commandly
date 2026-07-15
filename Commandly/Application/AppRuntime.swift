import AIKit
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
    /// Every explicit launcher open request captures the user's active display before activation.
    private(set) var launcherPresentationRequest: WindowPresentationRequest = .initial
    /// Whether the floating Shelf board is presented.
    var showsShelf: Bool = false
    /// Every explicit open request gets a new generation, even when its entry mode is unchanged.
    private(set) var shelfPresentationRequest: ShelfPresentationRequest = .initial
    /// Registered by a live SwiftUI scene so hotkeys can open the launcher window.
    var openLauncherWindow: (() -> Void)?
    var dismissLauncherWindow: (() -> Void)?
    /// Registered by a live SwiftUI scene so Shelf can open its floating board.
    var openShelfWindow: (() -> Void)?
    var dismissShelfWindow: (() -> Void)?
    private var windowPresentationActionOwner: UUID?
    private var cachedSettingsViewModel: SettingsViewModel?
    private var cachedDocumentationViewModel: DocumentationViewModel?
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
    private let aiConnectionService: any AIConnectionServicing
    @ObservationIgnored
    private let aiCredentialStore: any AIProviderCredentialStoring
    @ObservationIgnored
    private let windowLayoutService: AccessibilityWindowLayoutService
    @ObservationIgnored
    private let systemActivityProtectionTracker: SystemActivityProtectionTracker
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    private let autoQuitService: AutoQuitService
    @ObservationIgnored
    private let shelfLaunchController: ShelfLaunchController
    @ObservationIgnored
    private let shelfApplicationServices: ShelfApplicationServices
    @ObservationIgnored
    private let windowPresentationTargetProvider: @MainActor () -> WindowPresentationTarget?

    init(
        container: AppContainer = .bootstrap(),
        windowPresentationTargetProvider: @escaping @MainActor () -> WindowPresentationTarget? = {
            WindowPresentationTargetResolver.activeTarget()
        }
    ) {
        self.container = container
        self.windowPresentationTargetProvider = windowPresentationTargetProvider
        let settings = container.dependencies.appSettingsStore.load()
        self.showsOnboarding = CommandlyDebugLaunchOptions.skipsOnboarding
            ? false
            : container.appState.route == .onboarding
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.textSize = settings.textSize
        self.viewMode = settings.viewMode
        let aiTransport = URLSessionAIHTTPTransport()
        let aiRegistry: AIProviderRegistry
        do {
            aiRegistry = try AIProviderRegistry.standard(transport: aiTransport)
        } catch {
            preconditionFailure("Commandly's built-in AI provider identifiers must be unique.")
        }
        let aiConnectionService = AIKitConnectionService(
            registry: aiRegistry,
            transport: aiTransport
        )
        self.aiConnectionService = aiConnectionService
        let aiCredentialStore = SecureAIProviderCredentialStore(
            secureStore: container.dependencies.secureStore
        )
        self.aiCredentialStore = aiCredentialStore
        let aiProviderRuntime = AIProviderRuntimeService(
            connectionStore: container.dependencies.aiConnectionStore,
            credentialStore: aiCredentialStore,
            registry: aiRegistry,
            transport: aiTransport
        )
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
        let finderAIWorkspace = FinderAIWorkspaceService(
            folderAccessStore: container.dependencies.folderAccessStore,
            searchService: fileSearchService,
            fileRevealer: fileSearchApplicationServices.fileRevealer
        )
        let finderAIServices = FinderAIApplicationServices(
            runtime: aiProviderRuntime,
            workspace: finderAIWorkspace,
            toolExecutor: FinderAIToolExecutor(
                workspace: finderAIWorkspace,
                approvalCoordinator: finderAIWorkspace
            )
        )
        self.shelfApplicationServices = ShelfApplicationServices(
            metadataReader: WorkspaceFileResourceMetadataReader(),
            fileActions: WorkspaceShelfFileActionService(),
            fileRevealer: fileSearchApplicationServices.fileRevealer,
            urlOpener: fileSearchApplicationServices.urlOpener,
            pasteboard: pasteboard,
            previewPresenter: WorkspaceQuickLookPresenter(),
            dropFeedback: NativeShelfDropFeedbackPlayer(),
            makeTemporaryContentStore: {
                LocalShelfTemporaryContentStore()
            }
        )
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
        let shelfLaunchController = ShelfLaunchController()
        self.shelfLaunchController = shelfLaunchController
        self.applicationRegistry = .makeBuiltIn(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchServices: fileSearchApplicationServices,
            calculatorSessionStore: calculatorSessionStore,
            timerStore: TimerStore(),
            productivityLibraryServices: productivityLibraryServices,
            offlineToolsServices: offlineToolsServices,
            finderAIServices: finderAIServices,
            windowLayoutsServices: windowLayoutsServices,
            systemActivityService: NativeSystemActivityService(
                protectionTracker: systemActivityProtectionTracker
            ),
            preferencesStore: container.dependencies.launcherApplicationPreferencesStore,
            shelfLaunchController: shelfLaunchController
        )
        let applicationPreferencesStore = container.dependencies.applicationPreferencesStore
        self.applicationPreferencesStore = applicationPreferencesStore
        self.autoQuitService = AutoQuitService(preferencesStore: applicationPreferencesStore)
        startHotkeyMonitor()
        refreshApplicationHotkeys()
        registerApplicationManifests()
        shelfLaunchController.onPresent = { [weak self] mode in
            self?.showFloatingShelf(entryMode: mode)
        }
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
            aiSettingsModel: AISettingsModel(
                connectionStore: container.dependencies.aiConnectionStore,
                credentialStore: aiCredentialStore,
                connectionService: aiConnectionService,
                excludeCredentialFromClipboardHistory: { [weak clipboardHistoryStore] credential in
                    clipboardHistoryStore?.excludeSensitiveTextFromHistory(credential)
                }
            ),
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

    func makeDocumentationViewModel() -> DocumentationViewModel {
        if let cachedDocumentationViewModel {
            return cachedDocumentationViewModel
        }
        let viewModel = DocumentationViewModel(registry: applicationRegistry)
        cachedDocumentationViewModel = viewModel
        return viewModel
    }

    func makeLauncherViewModel(
        onOpenSettings: @escaping () -> Void,
        onOpenDocumentation: @escaping () -> Void = {}
    ) -> LauncherViewModel {
        let quit: () -> Void = {
            NSApplication.shared.terminate(nil)
        }
        if let cachedLauncherViewModel {
            cachedLauncherViewModel.onDismiss = { [weak self] in
                self?.hideLauncher()
            }
            cachedLauncherViewModel.onOpenSettings = onOpenSettings
            cachedLauncherViewModel.onOpenAISettings = { [weak self] in
                self?.makeSettingsViewModel().selectedPane = .ai
                onOpenSettings()
            }
            cachedLauncherViewModel.onOpenPermissionsSettings = { [weak self] in
                self?.makeSettingsViewModel().selectedPane = .permissions
                onOpenSettings()
            }
            cachedLauncherViewModel.onOpenDocumentation = onOpenDocumentation
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
            onOpenDocumentation: onOpenDocumentation,
            onOpenSettings: onOpenSettings,
            onOpenAISettings: { [weak self] in
                self?.makeSettingsViewModel().selectedPane = .ai
                onOpenSettings()
            },
            onOpenPermissionsSettings: { [weak self] in
                self?.makeSettingsViewModel().selectedPane = .permissions
                onOpenSettings()
            },
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
        // Capture before Commandly becomes active so reused windows can move to the user's
        // current display and full-screen Space instead of Commandly's previous desktop.
        launcherPresentationRequest = launcherPresentationRequest.next(
            screenTarget: windowPresentationTargetProvider()
        )
        showsLauncher = true
        openLauncherWindow?()
        // The window chrome coordinator presents only after it has installed the active-Space
        // behavior and applied this request's captured geometry.
        DispatchQueue.main.async {
            // `onAppear` may not fire when SwiftUI reuses an ordered-out window. The
            // coordinator presents during this runloop turn; bump focus alongside it.
            self.cachedLauncherViewModel?.requestSearchFocus()
        }
    }

    /// Opens the floating Shelf board from the menu bar.
    func openNewShelf() {
        showFloatingShelf(entryMode: .empty)
    }

    /// Opens the floating Shelf board in the clipboard entry layout from the menu bar.
    func openNewShelfFromClipboard() {
        showFloatingShelf(entryMode: .fromClipboard)
    }

    /// Preferred corner configured for Shelf in Settings → Applications.
    var shelfPreferredCorner: ShelfPreferredCorner {
        shelfConfiguration.preferredCorner
    }

    /// Resolved, non-secret behavior for a newly opened temporary Shelf board.
    var shelfConfiguration: ShelfConfiguration {
        let settings = applicationRegistry.resolvedSettings(for: ShelfApplication.applicationID)
        return ShelfConfiguration(
            clearWhenEmpty: settings?
                .value(for: "clearWhenEmpty")?
                .booleanValue ?? ShelfConfiguration.default.clearWhenEmpty,
            preferredCorner: ShelfPreferredCorner.resolve(
                settings?.value(for: "preferredCorner")?.textValue
            ),
            playDropSound: settings?
                .value(for: "playDropSound")?
                .booleanValue ?? ShelfConfiguration.default.playDropSound
        )
    }

    func makeShelfBoardModel(onClose: @escaping () -> Void) -> ShelfBoardModel {
        ShelfBoardModel(
            entryMode: shelfPresentationRequest.entryMode,
            configuration: shelfConfiguration,
            services: shelfApplicationServices,
            onClose: onClose
        )
    }

    func showFloatingShelf(entryMode: ShelfEntryMode) {
        guard showsOnboarding == false,
              applicationRegistry.isEffectivelyEnabled(ShelfApplication.applicationID) else {
            return
        }
        // Capture the user's active display before activating Commandly changes keyboard focus.
        shelfPresentationRequest = shelfPresentationRequest.next(
            entryMode: entryMode,
            screenTarget: windowPresentationTargetProvider()
        )
        showsShelf = true
        openShelfWindow?()
    }

    /// Installs the SwiftUI scene actions and replays a request made before the bridge mounted.
    ///
    /// This keeps global shortcuts and the first menu command single-shot: a pending request is
    /// opened once when its action becomes available without advancing its presentation generation.
    func installWindowPresentationActions(
        owner: UUID,
        openLauncher: @escaping () -> Void,
        dismissLauncher: @escaping () -> Void,
        openShelf: @escaping () -> Void,
        dismissShelf: @escaping () -> Void
    ) {
        let shouldReplayLauncher = openLauncherWindow == nil && showsLauncher
        let shouldReplayShelf = openShelfWindow == nil && showsShelf

        windowPresentationActionOwner = owner
        openLauncherWindow = openLauncher
        dismissLauncherWindow = dismissLauncher
        openShelfWindow = openShelf
        dismissShelfWindow = dismissShelf

        if shouldReplayLauncher {
            openLauncher()
        }
        if shouldReplayShelf {
            openShelf()
        }
    }

    /// Clears scene actions only when the disappearing bridge still owns the registration.
    func uninstallWindowPresentationActions(owner: UUID) {
        guard windowPresentationActionOwner == owner else { return }
        windowPresentationActionOwner = nil
        openLauncherWindow = nil
        dismissLauncherWindow = nil
        openShelfWindow = nil
        dismissShelfWindow = nil
    }

    func hideShelf() {
        guard showsShelf else {
            dismissShelfWindow?()
            return
        }
        showsShelf = false
        dismissShelfWindow?()
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
        hideShelf()
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
        cachedDocumentationViewModel?.refresh()
    }

    private func refreshApplicationHotkeys() {
        let fixedShelfHotKeys = ShelfGlobalShortcut.allCases.map {
            ($0.commandID, $0.hotKey)
        }
        let applicationHotKeys: [(CommandID, LauncherHotKey)] = applicationRegistry
            .allDefinitions()
            .compactMap { definition -> (CommandID, LauncherHotKey)? in
                guard applicationRegistry.isEffectivelyEnabled(definition.id),
                      let hotKey = applicationRegistry.resolvedSettings(for: definition.id)?.hotKey,
                      applicationRegistry.application(for: definition.id) != nil else {
                    return nil
                }
                return (definition.id, hotKey)
            }
        let hotKeys = fixedShelfHotKeys + applicationHotKeys
        applicationHotkeyIssues = applicationHotkeyMonitor.replace(hotKeys) { [weak self] id in
            guard let self else { return }
            if let shortcut = ShelfGlobalShortcut.resolve(id) {
                self.showFloatingShelf(entryMode: shortcut.entryMode)
            } else {
                self.openApplicationFromHotKey(id)
            }
        }
    }

    private func openApplicationFromHotKey(_ id: CommandID) {
        guard applicationRegistry.isEffectivelyEnabled(id) else { return }
        if id == ShelfApplication.applicationID {
            showFloatingShelf(entryMode: .empty)
            return
        }
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
