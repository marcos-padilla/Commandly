import AIKit
import AppCore
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
    @ObservationIgnored
    private let globalShortcutMonitor = GlobalShortcutMonitor()
    @ObservationIgnored
    private var globalShortcutRoutes: [GlobalShortcutID: RuntimeGlobalShortcutRoute] = [:]
    @ObservationIgnored
    private var activeWheelShortcutSessions: [GlobalShortcutID: CommandWheelSessionToken] = [:]
    @ObservationIgnored
    private var commandCatalogIsReadyForWheel = false
    @ObservationIgnored
    private var applicationTerminationObserver: NSObjectProtocol?
    private var pendingApplicationID: CommandID?
    private var pendingDirectPresentationApplicationID: CommandID?
    private var pendingCommandWheelStatusMessage: String?
    private(set) var applicationHotkeyIssues: [CommandID: ApplicationHotkeyRegistrationIssue] = [:]
    private(set) var commandWheelShortcutIssues: [UUID: GlobalShortcutRegistrationIssue] = [:]
    @ObservationIgnored
    let applicationRegistry: LauncherApplicationRegistry
    @ObservationIgnored
    private let commandAvailabilityEvaluator: ProductionCommandAvailabilityEvaluator
    @ObservationIgnored
    private let installedApplicationQuery: any InstalledApplicationQuerying
    @ObservationIgnored
    let commandCoordinator: SharedCommandExecutionCoordinator
    @ObservationIgnored
    let commandWheelProfileStore: CommandWheelProfileStore
    @ObservationIgnored
    private let commandWheelCoordinator: CommandWheelCoordinator
    @ObservationIgnored
    private let commandWheelFeedbackRelay: CommandWheelResultFeedbackRelay
    @ObservationIgnored
    private let registeredApplicationPresentationHandler:
        RegisteredLauncherApplicationPresentationHandler
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
    @ObservationIgnored
    private let frontmostApplicationContextProvider: any FrontmostApplicationContextProviding
    private var launcherFrontmostApplicationContext: FrontmostApplicationContext?

    init(
        container: AppContainer = .bootstrap(),
        frontmostApplicationContextProvider: any FrontmostApplicationContextProviding =
            WorkspaceFrontmostApplicationContextProvider(),
        windowPresentationTargetProvider: @escaping @MainActor () -> WindowPresentationTarget? = {
            WindowPresentationTargetResolver.activeTarget()
        }
    ) {
        self.container = container
        self.frontmostApplicationContextProvider = frontmostApplicationContextProvider
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
        let applicationRegistry = LauncherApplicationRegistry.makeBuiltIn(
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
        self.applicationRegistry = applicationRegistry
        let installedApplicationQuery = WorkspaceInstalledApplicationQuery()
        self.installedApplicationQuery = installedApplicationQuery
        let commandAvailabilityEvaluator = ProductionCommandAvailabilityEvaluator(
            applicationRegistry: applicationRegistry,
            permissionService: container.dependencies.permissionService,
            installedApplicationQuery: installedApplicationQuery
        )
        self.commandAvailabilityEvaluator = commandAvailabilityEvaluator
        let registeredApplicationPresentationHandler =
            RegisteredLauncherApplicationPresentationHandler()
        self.registeredApplicationPresentationHandler = registeredApplicationPresentationHandler
        let commandCoordinator = container.makeSharedCommandExecutionCoordinator(
            applicationRegistry: applicationRegistry,
            presentationHandler: registeredApplicationPresentationHandler,
            availabilityEvaluator: commandAvailabilityEvaluator
        )
        self.commandCoordinator = commandCoordinator
        let commandWheelProfileStore: CommandWheelProfileStore
        #if DEBUG
        if CommandWheelDebugFixture.isSettingsPresentationRequested {
            let fixtureConfiguration = CommandWheelDebugFixture.settingsConfiguration
            commandWheelProfileStore = CommandWheelProfileStore(
                repository: InMemoryCommandWheelProfileRepository(
                    configuration: fixtureConfiguration,
                    uuidProvider: container.dependencies.uuidProvider
                ),
                initialConfiguration: fixtureConfiguration,
                uuidProvider: container.dependencies.uuidProvider
            )
        } else {
            commandWheelProfileStore = CommandWheelProfileStore(
                repository: JSONCommandWheelProfileRepository(
                    uuidProvider: container.dependencies.uuidProvider
                ),
                uuidProvider: container.dependencies.uuidProvider
            )
        }
        #else
        commandWheelProfileStore = CommandWheelProfileStore(
            repository: JSONCommandWheelProfileRepository(
                uuidProvider: container.dependencies.uuidProvider
            ),
            uuidProvider: container.dependencies.uuidProvider
        )
        #endif
        self.commandWheelProfileStore = commandWheelProfileStore
        let commandWheelFeedbackRelay = CommandWheelResultFeedbackRelay()
        self.commandWheelFeedbackRelay = commandWheelFeedbackRelay
        self.commandWheelCoordinator = CommandWheelCoordinator(
            configuration: commandWheelProfileStore.configurationSnapshot(),
            frontmostContextProvider: frontmostApplicationContextProvider,
            resolver: container.dependencies.commandRegistry,
            usageHistory: container.dependencies.commandUsageHistory,
            installedApplicationQuery: installedApplicationQuery,
            commandCoordinator: commandCoordinator,
            resultFeedback: commandWheelFeedbackRelay
        )
        let applicationPreferencesStore = container.dependencies.applicationPreferencesStore
        self.applicationPreferencesStore = applicationPreferencesStore
        self.autoQuitService = AutoQuitService(preferencesStore: applicationPreferencesStore)
        registeredApplicationPresentationHandler.install { [weak self] commandID in
            self?.handleRegisteredApplicationPresentation(commandID)
        }
        commandWheelFeedbackRelay.install(
            onCompletion: { [weak self] result, context in
                self?.handleCommandWheelCompletion(result, context: context)
            },
            onFailure: { [weak self] error, context in
                self?.handleCommandWheelFailure(error, context: context)
            }
        )
        commandWheelProfileStore.onConfigurationChange = { [weak self] configuration in
            self?.commandWheelConfigurationDidChange(configuration)
        }
        refreshGlobalShortcuts()
        prepareCommandWheelRuntime()
        applicationTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tearDown()
            }
        }
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
        let availabilityEvaluator = commandAvailabilityEvaluator
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
            commandWheelProfileStore: commandWheelProfileStore,
            commandWheelCatalog: CommandWheelCommandCatalogSnapshot(
                availabilityEvaluator.initialSnapshot()
            ),
            commandWheelCatalogProvider: {
                await availabilityEvaluator.snapshot()
            },
            commandWheelInstalledApplicationQuery: installedApplicationQuery,
            commandWheelShortcutIssues: { [weak self] in
                self?.commandWheelShortcutIssues ?? [:]
            },
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
            cachedLauncherViewModel.onOpenCommandWheelSettings = { [weak self] location in
                self?.openCommandWheelSettings(
                    at: location,
                    onOpenSettings: onOpenSettings
                )
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
            applicationOpener: container.dependencies.applicationOpener,
            commandCoordinator: commandCoordinator,
            commandWheelAssignmentStore: commandWheelProfileStore,
            invocationContextProvider: { [weak self] source in
                self?.makeCommandInvocationContext(source: source)
                    ?? CommandInvocationContext(source: source)
            },
            applicationQuery: installedApplicationQuery,
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
            onOpenCommandWheelSettings: { [weak self] location in
                self?.openCommandWheelSettings(
                    at: location,
                    onOpenSettings: onOpenSettings
                )
            },
            onQuit: quit
        )
        cachedLauncherViewModel = viewModel
        return viewModel
    }

    private func openCommandWheelSettings(
        at location: CommandWheelSlotLocation,
        onOpenSettings: () -> Void
    ) {
        let settingsViewModel = makeSettingsViewModel()
        settingsViewModel.selectedPane = .commandWheel
        _ = settingsViewModel.commandWheel.reveal(location)
        onOpenSettings()
    }

    private func handleRegisteredApplicationPresentation(
        _ commandID: CommandID
    ) -> CommandResult? {
        if showsLauncher, let cachedLauncherViewModel {
            return cachedLauncherViewModel.presentRegisteredApplication(commandID)
        }
        guard showsOnboarding == false,
              applicationRegistry.enabledApplication(for: commandID) != nil else {
            return nil
        }
        pendingDirectPresentationApplicationID = commandID
        showLauncher()
        if let cachedLauncherViewModel {
            // A reused ordered-out SwiftUI window may not emit `onAppear`. Consume after the
            // presentation turn as a fallback; the pending-ID clear keeps this idempotent with UI.
            DispatchQueue.main.async { [weak self, weak cachedLauncherViewModel] in
                guard let self, let cachedLauncherViewModel else { return }
                self.consumePendingApplicationLaunch(using: cachedLauncherViewModel)
            }
        }
        return .success(message: nil)
    }

    private func makeCommandInvocationContext(
        source: CommandInvocationSource
    ) -> CommandInvocationContext {
        CommandInvocationContext(
            source: source,
            frontmostApplicationBundleIdentifier:
                launcherFrontmostApplicationContext?.bundleIdentifier,
            timestamp: container.dependencies.dateProvider.now()
        )
    }

    func consumePendingApplicationLaunch(using viewModel: LauncherViewModel) {
        if let pendingDirectPresentationApplicationID {
            self.pendingDirectPresentationApplicationID = nil
            // Defer until the presentation/onAppear turn completes so
            // `prepareForPresentation()` cannot reset the newly-created session.
            DispatchQueue.main.async { [weak self, weak viewModel] in
                guard let self, self.showsLauncher, let viewModel else { return }
                _ = viewModel.presentRegisteredApplication(
                    pendingDirectPresentationApplicationID
                )
            }
        }
        if let pendingApplicationID {
            self.pendingApplicationID = nil
            Task { @MainActor [weak viewModel] in
                await viewModel?.executeRegisteredApplication(
                    pendingApplicationID,
                    source: .applicationHotKey
                )
            }
        }

        consumePendingCommandWheelStatus(using: viewModel)
    }

    private func consumePendingCommandWheelStatus(using viewModel: LauncherViewModel) {
        guard let pendingCommandWheelStatusMessage else { return }
        self.pendingCommandWheelStatusMessage = nil
        DispatchQueue.main.async { [weak self, weak viewModel] in
            guard let self, self.showsLauncher, let viewModel else { return }
            viewModel.statusMessage = pendingCommandWheelStatusMessage
        }
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
        launcherFrontmostApplicationContext = frontmostApplicationContextProvider.snapshot()
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
        pendingApplicationID = nil
        pendingDirectPresentationApplicationID = nil
        pendingCommandWheelStatusMessage = nil
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

    private func applicationPreferencesDidChange() {
        refreshCommandCatalog()
        if let cachedSettingsViewModel {
            Task { @MainActor in
                await cachedSettingsViewModel.commandWheel.refreshCatalog()
            }
        }
        cachedLauncherViewModel?.applicationPreferencesDidChange()
        cachedDocumentationViewModel?.refresh()
    }

    private func prepareCommandWheelRuntime() {
        let store = commandWheelProfileStore
        let logger = container.dependencies.logger
        Task { @MainActor [weak self] in
            await store.preload()
            guard let self else { return }
            commandWheelCoordinator.updateConfiguration(store.configurationSnapshot())
            do {
                try await synchronizeCommandCatalog()
                commandCatalogIsReadyForWheel = true
            } catch {
                commandCatalogIsReadyForWheel = false
                logger.error("The shared command catalog could not be prepared for Command Wheel")
            }
            refreshGlobalShortcuts()
        }
    }

    private func commandWheelConfigurationDidChange(
        _ configuration: CommandWheelConfiguration
    ) {
        commandWheelCoordinator.updateConfiguration(configuration)
        refreshGlobalShortcuts()
    }

    private func refreshGlobalShortcuts() {
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

        var wheelConfiguration = commandWheelProfileStore.configurationSnapshot()
        if commandCatalogIsReadyForWheel == false {
            wheelConfiguration.isEnabled = false
        }
        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: applicationHotKeys,
            wheelConfiguration: wheelConfiguration
        )
        let routes = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.registration.id, $0.route) }
        )
        let issues = globalShortcutMonitor.replace(
            bindings.map(\.registration)
        ) { [weak self] event in
            self?.handleGlobalShortcutEvent(event)
        }
        globalShortcutRoutes = routes
        activeWheelShortcutSessions = activeWheelShortcutSessions.filter { id, token in
            routes[id] != nil && commandWheelCoordinator.activeSessionToken == token
        }
        mapGlobalShortcutIssues(issues, routes: routes)
    }

    private func handleGlobalShortcutEvent(_ event: GlobalShortcutEvent) {
        guard event.generation == globalShortcutMonitor.generation,
              let route = globalShortcutRoutes[event.id] else {
            return
        }

        switch route {
        case .launcher:
            if event.phase == .pressed { toggleLauncher() }

        case .shelf(let shortcut):
            if event.phase == .pressed {
                showFloatingShelf(entryMode: shortcut.entryMode)
            }

        case .application(let commandID):
            if event.phase == .pressed { openApplicationFromHotKey(commandID) }

        case .commandWheel(let profileID, let allowsContextOverride):
            handleCommandWheelShortcutEvent(
                event,
                profileID: profileID,
                allowsContextOverride: allowsContextOverride
            )
        }
    }

    private func handleCommandWheelShortcutEvent(
        _ event: GlobalShortcutEvent,
        profileID: UUID,
        allowsContextOverride: Bool
    ) {
        switch event.phase {
        case .pressed:
            let token = commandWheelCoordinator.shortcutPressed(
                explicitProfileID: profileID,
                allowsContextOverride: allowsContextOverride
            )
            activeWheelShortcutSessions[event.id] = token

        case .released:
            guard let token = activeWheelShortcutSessions[event.id] else { return }
            commandWheelCoordinator.shortcutReleased(sessionToken: token)
            if commandWheelCoordinator.activeSessionToken != token {
                activeWheelShortcutSessions[event.id] = nil
            }

        case .cancelled:
            guard let token = activeWheelShortcutSessions.removeValue(
                forKey: event.id
            ) else {
                return
            }
            commandWheelCoordinator.shortcutCancelled(sessionToken: token)
        }
    }

    private func mapGlobalShortcutIssues(
        _ issues: [GlobalShortcutID: GlobalShortcutRegistrationIssue],
        routes: [GlobalShortcutID: RuntimeGlobalShortcutRoute]
    ) {
        var applicationIssues = [CommandID: ApplicationHotkeyRegistrationIssue]()
        var wheelIssues = [UUID: GlobalShortcutRegistrationIssue]()

        for (registrationID, issue) in issues {
            guard let route = routes[registrationID] else { continue }
            switch route {
            case .application(let commandID):
                if case .duplicate(let ownerID) = issue,
                   case .application(let ownerCommandID)? = routes[ownerID] {
                    applicationIssues[commandID] = .duplicate(ownerCommandID)
                } else {
                    applicationIssues[commandID] = .unavailable
                }
            case .commandWheel(let profileID, _):
                wheelIssues[profileID] = issue
            case .launcher, .shelf:
                break
            }
        }
        applicationHotkeyIssues = applicationIssues
        commandWheelShortcutIssues = wheelIssues
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

    /// Replaces the shared command catalog atomically from current effective application settings.
    func synchronizeCommandCatalog() async throws {
        try await commandCoordinator.refreshCatalog()
    }

    private func refreshCommandCatalog() {
        let logger = container.dependencies.logger
        commandCatalogIsReadyForWheel = false
        if let token = commandWheelCoordinator.activeSessionToken {
            commandWheelCoordinator.shortcutCancelled(sessionToken: token)
        }
        activeWheelShortcutSessions.removeAll()
        refreshGlobalShortcuts()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await synchronizeCommandCatalog()
                commandCatalogIsReadyForWheel = true
                refreshGlobalShortcuts()
            } catch {
                logger.error("The shared command catalog could not be refreshed")
            }
        }
    }

    private func handleCommandWheelCompletion(
        _ result: CommandResult,
        context _: CommandInvocationContext
    ) {
        switch result {
        case .success(let message):
            if let message { presentCommandWheelStatus(message) }
        case .failure(let message):
            presentCommandWheelStatus(message)
        case .cancelled:
            presentCommandWheelStatus("Command cancelled.")
        }
    }

    private func handleCommandWheelFailure(
        _ error: any Error,
        context _: CommandInvocationContext
    ) {
        let message = (error as? SharedCommandExecutionCoordinatorError)?
            .userFacingMessage ?? "Command couldn’t be completed."
        presentCommandWheelStatus(message)
    }

    private func presentCommandWheelStatus(_ message: String) {
        pendingCommandWheelStatusMessage = message
        showLauncher()
        if let cachedLauncherViewModel {
            DispatchQueue.main.async { [weak self, weak cachedLauncherViewModel] in
                guard let self, let cachedLauncherViewModel else { return }
                self.consumePendingApplicationLaunch(using: cachedLauncherViewModel)
            }
        }
    }

    /// Explicitly stops app-lifetime shortcut, wheel, and feedback resources at termination.
    func tearDown() {
        globalShortcutMonitor.stop()
        globalShortcutRoutes.removeAll()
        activeWheelShortcutSessions.removeAll()
        commandWheelCoordinator.tearDown()
        commandWheelFeedbackRelay.tearDown()
        clipboardHistoryStore.stopMonitoring()
        autoQuitService.stop()
        if let applicationTerminationObserver {
            NotificationCenter.default.removeObserver(applicationTerminationObserver)
            self.applicationTerminationObserver = nil
        }
    }

}
