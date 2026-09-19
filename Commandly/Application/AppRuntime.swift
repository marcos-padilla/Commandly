import AICommandBridge
import ClipboardToolsModule
import AIKit
import AppCore
import Foundation
import Observation
import Infrastructure
import AppKit
import CommandKit
import MarkdownPreviewKit
import ModuleKit
import ModuleRuntime
import Observability
import TimersModule

/// Observable app runtime for scene-level UI that must react to onboarding completion.
@Observable
@MainActor
final class AppRuntime {
    let container: AppContainer
    let floatingNotes: FloatingNoteCoordinator
    let screenRecording: ScreenRecordingCoordinator
    let displayResolution: DisplayResolutionApplicationServices
    let menuBarShortcuts: MenuBarShortcutController
    let keyboardTriggerSettings: KeyboardTriggerSettingsModel
    let systemCompanion: SystemCompanionApplicationServices
    let auxiliaryWindowAppearance: AuxiliaryWindowAppearance
    @ObservationIgnored
    let writingServiceProvider: NativeWritingServiceProvider
    /// Keep Awake session state shown in the menu bar panel.
    let keepAwake: KeepAwakeCoordinator
    /// Output, input, and per-application audio shown in the menu bar panel.
    let volumeMixer: VolumeMixerModel
    private let preciseVolumeSteps: PreciseVolumeStepMonitor
    /// Processor, graphics, and memory load shown in the menu bar panel.
    let systemMetrics: SystemMetricsMonitor
    /// Live network throughput shown in the menu bar panel.
    let networkMetrics: NetworkMetricsMonitor
    /// Mounted volumes and disk throughput shown in the menu bar panel.
    let diskMetrics: DiskMetricsMonitor
    /// Battery and power draw shown in the menu bar panel.
    let powerMetrics: PowerMetricsMonitor
    /// Fan speeds and, where the hardware allows it, fan control.
    let fanControl: FanControlMonitor
    /// Everyday macOS switches shown in the menu bar panel.
    let quickToggles: QuickTogglesModel
    /// Behaviors the menu bar panel can switch on and off.
    let controls: ControlsModel
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
    private var isRecordingInstalledApplicationShortcut = false
    @ObservationIgnored
    private var installedShortcutRegistrationOrder: [String] = []
    @ObservationIgnored
    private var activeInstalledApplicationShortcutBundles: Set<String> = []
    private(set) var installedApplicationHotkeyIssues: [String: GlobalShortcutRegistrationIssue] = [:]
    @ObservationIgnored
    private var activeWheelShortcutSessions: [GlobalShortcutID: CommandWheelSessionToken] = [:]
    @ObservationIgnored
    private var backgroundInvocationTasks: [CommandID: Task<CommandResult, Never>] = [:]
    @ObservationIgnored
    private var backgroundInvocationTokens: [CommandID: UUID] = [:]
    @ObservationIgnored
    private var backgroundShortcutTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var commandCatalogIsReadyForWheel = false
    @ObservationIgnored
    private var applicationTerminationObserver: NSObjectProtocol?
    private var pendingCommandReference: CommandReference?
    private var pendingDirectPresentationReference: CommandReference?
    private var pendingCommandWheelStatusMessage: String?
    private(set) var applicationHotkeyIssues: [CommandID: ApplicationHotkeyRegistrationIssue] = [:]
    private(set) var commandWheelShortcutIssues: [UUID: GlobalShortcutRegistrationIssue] = [:]
    @ObservationIgnored
    let applicationRegistry: LauncherApplicationRegistry
    @ObservationIgnored
    private let aiAgentsServices: AIAgentsApplicationServices
    @ObservationIgnored
    private let commandAvailabilityEvaluator: ProductionCommandAvailabilityEvaluator
    @ObservationIgnored
    private let installedApplicationQuery: any InstalledApplicationQuerying
    @ObservationIgnored
    let commandCoordinator: SharedCommandExecutionCoordinator
    /// Generic host for compiled-in feature modules.
    ///
    /// `AppRuntime` retains the host itself, not a property per feature: a module's services are
    /// created by its own assembly when the host first needs them.
    @ObservationIgnored
    let moduleHost: ModuleHost
    /// Default-deny projection of module commands onto the AI tool contracts.
    @ObservationIgnored
    let aiCommandBridge: AICommandBridge
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
    private let windowLayoutService: CompanionWindowLayoutService
    @ObservationIgnored
    private let systemActivityProtectionTracker: SystemActivityProtectionTracker
    @ObservationIgnored
    private let highlightModeService: any HighlightModeControlling
    @ObservationIgnored
    private let windowSwitcherCoordinator: WindowSwitcherCoordinator
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    private let autoQuitService: AutoQuitService
    @ObservationIgnored
    private let scheduleAutoJoin: ScheduleAutoJoinCoordinator
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
        let auxiliaryWindowAppearance = AuxiliaryWindowAppearance(textSize: settings.textSize)
        self.auxiliaryWindowAppearance = auxiliaryWindowAppearance
        #if DEBUG
        self.systemCompanion = CommandlyDebugLaunchOptions.usesProductivityFixture
            && !CommandlyDebugLaunchOptions.usesLiveCompanion ? .inMemory() : .live()
        #else
        self.systemCompanion = .live()
        #endif
        self.showsOnboarding = CommandlyDebugLaunchOptions.skipsOnboarding
            ? false
            : container.appState.route == .onboarding
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.keepAwake = KeepAwakeCoordinator(
            permissions: container.dependencies.permissionService
        )
        self.volumeMixer = VolumeMixerModel()
        self.preciseVolumeSteps = PreciseVolumeStepMonitor()
        let systemMetricsMonitor = SystemMetricsMonitor()
        self.systemMetrics = systemMetricsMonitor
        self.networkMetrics = NetworkMetricsMonitor()
        let diskMetricsMonitor = DiskMetricsMonitor()
        self.diskMetrics = diskMetricsMonitor
        self.powerMetrics = PowerMetricsMonitor()
        self.fanControl = FanControlMonitor(temperatures: systemMetricsMonitor)
        self.quickToggles = QuickTogglesModel(
            microphone: NativeMicrophoneControlService(),
            disks: diskMetricsMonitor,
            settings: SystemSettingsApplicationServices.live.opener,
            permissions: container.dependencies.permissionService
        )
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
        #if DEBUG
        let productivityFixture = CommandlyDebugLaunchOptions.usesProductivityFixture
            ? CommandlyProductivityDebugFixture() : nil
        let clipboardHistoryStore = productivityFixture?.clipboard ?? ClipboardHistoryStore(
            enricher: VisionClipboardContentEnricher()
        )
        #else
        let clipboardHistoryStore = ClipboardHistoryStore(
            enricher: VisionClipboardContentEnricher()
        )
        #endif
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
        let fileSearchApplicationServices = CommandlyDebugLaunchOptions.usesProductivityFixture
            ? FileSearchApplicationServices.inMemory : FileSearchApplicationServices(
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
        let liveFinderAIServices = FinderAIApplicationServices(
            runtime: aiProviderRuntime,
            workspace: finderAIWorkspace,
            toolExecutor: FinderAIToolExecutor(
                workspace: finderAIWorkspace,
                approvalCoordinator: finderAIWorkspace
            )
        )
        #if DEBUG
        let finderAIServices = productivityFixture == nil ? liveFinderAIServices : FinderAIImageDebugFixture().services
        #else
        let finderAIServices = liveFinderAIServices
        #endif
        let liveQuickAIServices = QuickAIApplicationServices.live(
            connectionStore: container.dependencies.aiConnectionStore,
            credentialStore: aiCredentialStore,
            registry: aiRegistry
        )
        #if DEBUG
        let writingToolsServices: WritingToolsApplicationServices = productivityFixture == nil
            ? .live : WritingToolsDebugFixture.services
        let translationServices: TranslationApplicationServices = productivityFixture == nil
            ? .live : TranslationDebugFixture.services
        #else
        let writingToolsServices = WritingToolsApplicationServices.live
        let translationServices = TranslationApplicationServices.live
        #endif
        self.writingServiceProvider = NativeWritingServiceProvider(checker: writingToolsServices.checker)
        #if DEBUG
        let quickAIServices = productivityFixture?.quickAI ?? liveQuickAIServices
        let emojiServices: EmojiSearchApplicationServices = productivityFixture == nil
            ? .live(pasteboard: fileSearchApplicationServices.pasteboard, quickAI: quickAIServices.chat)
            : EmojiSearchDebugFixture.services(pasteboard: fileSearchApplicationServices.pasteboard)
        let dictationServices: DictationApplicationServices = productivityFixture == nil
            ? .live(pasteboard: fileSearchApplicationServices.pasteboard, quickAI: quickAIServices.chat)
            : DictationDebugFixture.services(pasteboard: fileSearchApplicationServices.pasteboard, quickAI: quickAIServices.chat)
        let gifSearchServices: GIFSearchApplicationServices = productivityFixture == nil
            ? .live(secureStore: container.dependencies.secureStore)
            : GIFSearchDebugFixture.services()
        let finderPathServices: FinderPathApplicationServices = productivityFixture == nil || CommandlyDebugLaunchOptions.usesLiveFinderPath
            ? .live : FinderPathDebugFixture.services()
        let slackEmojiServices: SlackEmojiApplicationServices = productivityFixture == nil
            ? .live(secureStore: container.dependencies.secureStore)
            : SlackEmojiDebugFixture.services()
        let notionWorkspaceServices: NotionWorkspaceApplicationServices = productivityFixture == nil
            ? .live(store: container.dependencies.secureStore) : .unavailable
        let externalAgentServices: ExternalAgentApplicationServices = productivityFixture == nil
            ? .live(store: container.dependencies.secureStore) : .unavailable
        #else
        let quickAIServices = liveQuickAIServices
        let emojiServices = EmojiSearchApplicationServices.live(
            pasteboard: fileSearchApplicationServices.pasteboard, quickAI: quickAIServices.chat
        )
        let dictationServices = DictationApplicationServices.live(
            pasteboard: fileSearchApplicationServices.pasteboard, quickAI: quickAIServices.chat
        )
        let gifSearchServices = GIFSearchApplicationServices.live(secureStore: container.dependencies.secureStore)
        let finderPathServices = FinderPathApplicationServices.live
        let slackEmojiServices = SlackEmojiApplicationServices.live(secureStore: container.dependencies.secureStore)
        let notionWorkspaceServices = NotionWorkspaceApplicationServices.live(store: container.dependencies.secureStore)
        let externalAgentServices = ExternalAgentApplicationServices.live(store: container.dependencies.secureStore)
        #endif
        let aiAgentsServices: AIAgentsApplicationServices = CommandlyDebugLaunchOptions.usesProductivityFixture
            ? .inMemory : .live(chat: quickAIServices.chat)
        self.aiAgentsServices = aiAgentsServices
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
        #if DEBUG
        let baseLibraryServices = productivityFixture?.library ?? ProductivityLibraryApplicationServices(
            persistence: JSONProductivityLibraryStore(),
            pasteboard: pasteboard,
            urlOpener: fileSearchApplicationServices.urlOpener
        )
        #else
        let baseLibraryServices = ProductivityLibraryApplicationServices(
            persistence: JSONProductivityLibraryStore(),
            pasteboard: pasteboard,
            urlOpener: fileSearchApplicationServices.urlOpener
        )
        #endif
        let floatingNotes = FloatingNoteCoordinator(
            persistence: baseLibraryServices.persistence,
            makeWindow: { FloatingNoteWindowController(appearance: auxiliaryWindowAppearance) }
        )
        self.floatingNotes = floatingNotes
        #if DEBUG
        let recordingCapture: any ScreenRecordingCapturing = productivityFixture == nil
            ? NativeScreenRecordingCaptureService() : ScreenRecordingDebugFixture.capture()
        let recordingSessionLabel: String? = productivityFixture == nil ? nil : ScreenRecordingDebugFixture.label
        #else
        let recordingCapture: any ScreenRecordingCapturing = NativeScreenRecordingCaptureService()
        let recordingSessionLabel: String? = nil
        #endif
        let screenRecording = ScreenRecordingCoordinator(
            capture: recordingCapture, storage: NativeScreenRecordingStore(), sessionLabel: recordingSessionLabel,
            makeWindow: { ScreenRecordingWindowController(appearance: auxiliaryWindowAppearance) }
        )
        self.screenRecording = screenRecording
        let displayResolution: DisplayResolutionApplicationServices = CommandlyDebugLaunchOptions.usesProductivityFixture
            ? .inMemory(appearance: auxiliaryWindowAppearance) : .live(appearance: auxiliaryWindowAppearance)
        self.displayResolution = displayResolution
        let productivityLibraryServices = baseLibraryServices.withFloatingNotes(floatingNotes)
        let financeServices = FinanceApplicationServices.live
        let markdownPreviewServices = MarkdownPreviewApplicationServices.live
        let offlineToolsServices = OfflineToolsServices(pasteboard: pasteboard)
        let scheduleReader = NativeScheduleService(permissions: container.dependencies.permissionService)
        let scheduleAutoJoin = ScheduleAutoJoinCoordinator(
            reader: scheduleReader, opener: fileSearchApplicationServices.urlOpener
        )
        let liveScheduleServices = ScheduleApplicationServices(
                reader: scheduleReader,
                permissions: container.dependencies.permissionService,
                privacySettings: container.dependencies.privacySettingsOpener,
                autoJoin: scheduleAutoJoin
            )
        #if DEBUG
        let scheduleServices = productivityFixture?.schedule ?? liveScheduleServices
        let fileBrowserOverride: (any FileBrowsing)? = productivityFixture?.fileBrowser
        let cameraServices = productivityFixture?.camera ?? CameraApplicationServices.live(
            permissions: container.dependencies.permissionService,
            privacySettingsOpener: container.dependencies.privacySettingsOpener
        )
        let screenshotServices = productivityFixture?.screenshot ?? ScreenshotApplicationServices.live(
            permissions: container.dependencies.permissionService,
            privacySettings: container.dependencies.privacySettingsOpener
        )
        #else
        let scheduleServices = liveScheduleServices
        let fileBrowserOverride: (any FileBrowsing)? = nil
        let cameraServices = CameraApplicationServices.live(
            permissions: container.dependencies.permissionService,
            privacySettingsOpener: container.dependencies.privacySettingsOpener
        )
        let screenshotServices = ScreenshotApplicationServices.live(
            permissions: container.dependencies.permissionService,
            privacySettings: container.dependencies.privacySettingsOpener
        )
        #endif
        let visualAIServices: VisualAIApplicationServices
        #if DEBUG
        visualAIServices = productivityFixture == nil ? .live(screenshots: screenshotServices,
            connections: container.dependencies.aiConnectionStore, credentials: aiCredentialStore, registry: aiRegistry) : .inMemory
        #else
        visualAIServices = .live(screenshots: screenshotServices,
            connections: container.dependencies.aiConnectionStore, credentials: aiCredentialStore, registry: aiRegistry)
        #endif
        self.scheduleAutoJoin = scheduleServices.autoJoin
        let windowLayoutService = CompanionWindowLayoutService(client: systemCompanion.windowLayouts)
        self.windowLayoutService = windowLayoutService
        let windowLayoutsServices = WindowLayoutsApplicationServices(
            layoutService: windowLayoutService,
            customStore: UserDefaultsCustomWindowLayoutStore()
        )
        let systemActivityProtectionTracker = SystemActivityProtectionTracker()
        self.systemActivityProtectionTracker = systemActivityProtectionTracker
        let highlightModeService = NativeHighlightModeService(
            permissionService: container.dependencies.permissionService
        )
        self.highlightModeService = highlightModeService
        let windowService = AccessibilityWindowService()
        let windowSwitcherCoordinator = WindowSwitcherCoordinator(
            queryService: windowService,
            controlService: windowService,
            thumbnailService: ScreenCaptureWindowThumbnailService(
                permissionService: container.dependencies.permissionService
            ),
            permissionService: container.dependencies.permissionService
        )
        self.windowSwitcherCoordinator = windowSwitcherCoordinator
        let shelfLaunchController = ShelfLaunchController()
        self.shelfLaunchController = shelfLaunchController
        let installedApplicationQuery: any InstalledApplicationQuerying =
            CommandlyDebugLaunchOptions.usesProductivityFixture
            ? InMemoryInstalledApplicationQuery(applications: [
                InstalledApplication(
                    bundleIdentifier: "com.commandly.fixture.canvas", name: "Sample Canvas",
                    path: "/Applications/CommandlySampleCanvas.app"
                )
            ]) : WorkspaceInstalledApplicationQuery()
        self.installedApplicationQuery = installedApplicationQuery
        let menuBarShortcuts = MenuBarShortcutController(
            store: CommandlyDebugLaunchOptions.usesProductivityFixture
                ? InMemoryMenuBarShortcutStore() : UserDefaultsMenuBarShortcutStore(),
            presenter: NativeMenuBarShortcutPresenter()
        )
        self.menuBarShortcuts = menuBarShortcuts
        // One store backs both the Timers module's `timers.start` handler and the launcher's
        // Timers UI, so a countdown started from either side is the same countdown.
        let timerStore = TimerStore()
        let applicationRegistry = LauncherApplicationRegistry.makeBuiltIn(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchServices: fileSearchApplicationServices,
            fileBrowserFolderAccessStore: CommandlyDebugLaunchOptions.usesProductivityFixture
                ? InMemoryFolderAccessStore() : container.dependencies.folderAccessStore,
            fileBrowserServiceOverride: fileBrowserOverride,
            calculatorSessionStore: calculatorSessionStore,
            timerStore: timerStore,
            clipboardToolsOperations: ClipboardToolsOperations(
                pasteboard: SystemPasteboard(),
                clearing: SystemPasteboard()
            ),
            financeServices: financeServices,
            markdownPreviewServices: markdownPreviewServices,
            productivityLibraryServices: productivityLibraryServices,
            scheduleServices: scheduleServices,
            cameraServices: cameraServices,
            screenshotServices: screenshotServices,
            screenRecordingPresenter: screenRecording,
            displayResolutionServices: displayResolution,
            systemSettingsServices: .live,
            menuBarShortcutController: menuBarShortcuts,
            offlineToolsServices: offlineToolsServices,
            finderAIServices: finderAIServices,
            quickAIServices: quickAIServices,
            aiAgentsServices: aiAgentsServices,
            visualAIServices: visualAIServices,
            externalAgentServices: externalAgentServices,
            emojiServices: emojiServices,
            dictationServices: dictationServices,
            gifSearchServices: gifSearchServices,
            slackEmojiServices: slackEmojiServices,
            notionWorkspaceServices: notionWorkspaceServices,
            finderPathServices: finderPathServices,
            appMenusServices: CommandlyDebugLaunchOptions.usesProductivityFixture ? .unavailable : .live(client: systemCompanion.appMenus),
            writingToolsServices: writingToolsServices,
            translationServices: translationServices,
            windowLayoutsServices: windowLayoutsServices,
            systemActivityService: NativeSystemActivityService(
                protectionTracker: systemActivityProtectionTracker
            ),
            storageCleanupScanner: WorkspaceStorageCleanupScanner(
                installedApplicationQuery: installedApplicationQuery
            ),
            storageCleanupDirectoryChooser: WorkspaceStorageCleanupDirectoryChooser(),
            storageCleanupTrashManager: WorkspaceApplicationBundleManager(),
            highlightModeService: highlightModeService,
            windowSwitcherServices: WindowSwitcherApplicationServices(
                presenter: windowSwitcherCoordinator
            ),
            // Cross-application Accessibility enumeration/control is incompatible with the
            // App-Sandbox-enabled Commandly target. Keep the reviewed foundation dormant until an
            // explicitly approved companion/distribution architecture supplies that capability.
            includesWindowSwitcher: false,
            preferencesStore: container.dependencies.launcherApplicationPreferencesStore,
            shelfLaunchController: shelfLaunchController
        )
        self.applicationRegistry = applicationRegistry
        if let markdownSettings = applicationRegistry.resolvedSettings(
            for: MarkdownPreviewApplication.applicationID
        ) {
            do {
                try MarkdownPreferenceStore().save(
                    MarkdownPreviewApplication.configuration(from: markdownSettings)
                )
            } catch {
                container.dependencies.logger.error(
                    "Markdown Preview settings could not be shared with Quick Look"
                )
            }
        }
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
        let clipboardToolsDependencies = ClipboardToolsDependencies.live(
            registry: applicationRegistry
        )
        let moduleHost = BuiltInModules.makeHost(
            timerStore: timerStore,
            clipboardTools: clipboardToolsDependencies,
            enablement: LauncherRegistryModuleEnablementProvider(
                registry: applicationRegistry,
                manifests: BuiltInModules.assemblies(
                    timerStore: timerStore,
                    clipboardTools: clipboardToolsDependencies
                ).map(\.manifest)
            )
        )
        self.moduleHost = moduleHost
        self.aiCommandBridge = AICommandBridge(
            definitions: { moduleHost.commandDefinitions() },
            dispatcher: SharedCommandModuleDispatcher(
                coordinator: commandCoordinator,
                host: moduleHost
            ),
            eligibility: ModuleHostAIEligibilityEvaluator(host: moduleHost)
        )
        self.keyboardTriggerSettings = KeyboardTriggerSettingsModel(operation: systemCompanion.keyboardTriggers,
            persistence: CommandlyDebugLaunchOptions.usesProductivityFixture ? InMemoryKeyboardTriggerPreferencesStore() : JSONKeyboardTriggerPreferencesStore(),
            library: productivityLibraryServices.persistence, executor: commandCoordinator,
            opener: productivityLibraryServices.urlOpener,
            commandOptions: { [weak applicationRegistry] in
                applicationRegistry?.allManifests().filter { $0.arguments.isEmpty }.map { KeyboardTriggerCommandOption(reference: CommandReference(commandID: $0.id), title: $0.title) } ?? []
            })
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
        let applicationPreferencesStore: any ApplicationPreferencesStoring =
            CommandlyDebugLaunchOptions.usesProductivityFixture
            ? InMemoryApplicationPreferencesStore() : container.dependencies.applicationPreferencesStore
        self.applicationPreferencesStore = applicationPreferencesStore
        self.autoQuitService = AutoQuitService(preferencesStore: applicationPreferencesStore)
        self.controls = ControlsModel(
            registry: applicationRegistry,
            commandWheel: commandWheelProfileStore,
            keyboardTriggers: keyboardTriggerSettings,
            permissions: container.dependencies.permissionService
        )
        controls.onApplicationPreferencesChange = { [weak self] in
            self?.applicationPreferencesDidChange()
        }
        registeredApplicationPresentationHandler.install { [weak self] command, context in
            await self?.handleRegisteredApplicationPresentation(command, context: context)
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
        configureWindowSwitcher()
        menuBarShortcuts.start(
            catalog: { [weak applicationRegistry] in
                guard let applicationRegistry else { return [] }
                return MenuBarShortcutCatalog.items(in: applicationRegistry)
            }, execute: { [weak self] id in await self?.invokeMenuBarCommand(id) },
            manage: { [weak self] in self?.openApplicationFromHotKey(MenuBarShortcutsApplication.id) }
        )
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
        aiAgentsServices.library.onCatalogChange = { [weak self] in
            guard let self else { return }
            try self.applicationRegistry.refreshTools(for: AIAgentsApplication.id)
            self.applicationPreferencesDidChange()
        }
        Task { await aiAgentsServices.library.loadForLauncher() }
        windowLayoutsServices.commandCatalog.onCatalogChange = { [weak self] in
            guard let self else { return }
            try self.applicationRegistry.refreshTools(for: WindowLayoutsApplication.id)
            self.applicationPreferencesDidChange()
        }
        shelfLaunchController.onPresent = { [weak self] mode in
            self?.showFloatingShelf(entryMode: mode)
        }
        if !CommandlyDebugLaunchOptions.usesProductivityFixture {
            clipboardHistoryStore.startMonitoring()
        }
        if showsOnboarding == false && !CommandlyDebugLaunchOptions.usesProductivityFixture {
            autoQuitService.start()
        }
        keepAwake.start()
        startVolumeMixer()
    }

    /// Brings the mixer up and keeps the two preferences that reach outside it — the finer
    /// volume steps event tap and the output-cycling shortcut — in step with its settings.
    /// Starts modules whose activation policy is `atLaunchWhenEnabled`.
    ///
    /// Called once after SwiftUI installs its scene actions, not during `AppRuntime.init`, so
    /// constructing the runtime never starts background behavior. Modules that fail are isolated:
    /// the host records the failure as availability and the rest still start.
    ///
    /// No shipping module uses this policy yet; Clipboard History is its first intended consumer.
    func startBackgroundModules() async {
        await moduleHost.activateLaunchModules()
    }

    /// Enabled applications shown in the menu bar panel's Utilities tab.
    ///
    /// Built from registry metadata only: no module is activated, no service is constructed, and
    /// no permission is requested by reading this. Disabled applications are omitted, which keeps
    /// the Window Switcher gate and every user enablement choice intact.
    var utilitiesPanelApplications: [LauncherApplicationDefinition] {
        applicationRegistry
            .children(of: BuiltInLauncherApplicationGroup.catalogID)
            .filter { definition in
                definition.kind == .application
                    && applicationRegistry.isEffectivelyEnabled(definition.id)
            }
    }

    private func startVolumeMixer() {
        volumeMixer.onFinerVolumeStepsChange = { [weak self] enabled in
            self?.preciseVolumeSteps.setEnabled(enabled)
        }
        volumeMixer.onOutputShortcutChange = { [weak self] _ in
            self?.refreshGlobalShortcuts()
        }
        guard CommandlyDebugLaunchOptions.usesProductivityFixture == false else { return }
        // Watching the audio system costs HAL listeners and a process enumeration per change.
        // A mixer with nothing saved has no tap to hold, so it waits for the panel to open.
        if volumeMixer.hasWorkAtLaunch { volumeMixer.start() }
        if volumeMixer.settings.usesFinerVolumeSteps {
            preciseVolumeSteps.setEnabled(true)
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
                self?.auxiliaryWindowAppearance.textSize = textSize
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
            fileSearchService: fileSearchApplicationServices.searchService,
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
            onQuit: quit,
            saveInstalledApplicationShortcut: { [weak self] bundleID, hotKey in
                guard let self else { return "Application shortcuts are unavailable." }
                return self.saveInstalledApplicationShortcut(hotKey, for: bundleID)
            },
            onInstalledApplicationPreferencesChange: { [weak self] in
                self?.refreshGlobalShortcuts()
            },
            onInstalledShortcutRecordingChange: { [weak self] recording in
                self?.setInstalledShortcutRecording(recording)
            },
            installedApplicationShortcutIssue: { [weak self] bundleID in
                guard let issue = self?.installedApplicationHotkeyIssues[bundleID] else { return nil }
                return InstalledApplicationShortcuts.message(for: issue)
            }
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
        _ command: ResolvedCommand,
        context: CommandInvocationContext
    ) async -> CommandResult? {
        let reference = command.reference
        guard let applicationID = applicationRegistry.owningApplicationID(
            for: reference.commandID
        ),
        applicationRegistry.isEffectivelyEnabled(reference.commandID),
        let application = applicationRegistry.enabledApplication(for: applicationID),
        let settings = applicationRegistry.resolvedSettings(for: applicationID) else {
            return nil
        }

        if reference.commandID == applicationID,
           (context.source == .applicationHotKey || context.source == .menuBar),
           let backgroundApplication = application
                as? any LauncherApplicationBackgroundInvoking {
            return await invokeBackgroundCommand(reference.commandID) {
                await backgroundApplication.invokeInBackground(settings: settings)
            }
        }
        if let backgroundTools = application
            as? any LauncherApplicationToolBackgroundInvoking,
           backgroundTools.backgroundToolIDs.contains(reference.commandID) {
            if context.source == .search {
                hideLauncher()
            }
            let result = await invokeBackgroundCommand(reference.commandID) {
                await backgroundTools.invokeToolInBackground(
                    toolID: reference.commandID,
                    arguments: reference.arguments,
                    settings: settings
                )
            }
            if context.source == .search, case .failure(let message) = result {
                presentCommandWheelStatus(message)
            }
            return result
        }
        if showsLauncher, let cachedLauncherViewModel {
            return cachedLauncherViewModel.presentRegisteredCommand(reference)
        }
        guard showsOnboarding == false,
              applicationRegistry.isEffectivelyEnabled(reference.commandID) else {
            return nil
        }
        pendingDirectPresentationReference = reference
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
        if let pendingDirectPresentationReference {
            self.pendingDirectPresentationReference = nil
            // Defer until the presentation/onAppear turn completes so
            // `prepareForPresentation()` cannot reset the newly-created session.
            DispatchQueue.main.async { [weak self, weak viewModel] in
                guard let self, self.showsLauncher, let viewModel else { return }
                _ = viewModel.presentRegisteredCommand(pendingDirectPresentationReference)
            }
        }
        if let pendingCommandReference {
            self.pendingCommandReference = nil
            Task { @MainActor [weak viewModel] in
                await viewModel?.executeRegisteredCommand(
                    pendingCommandReference,
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

    /// Opens the registered Window Switcher from menu-bar UI without activating the launcher.
    func showWindowSwitcher() {
        guard showsOnboarding == false,
              applicationRegistry.isEffectivelyEnabled(
                  WindowSwitcherApplication.applicationID
              ) else {
            return
        }
        windowSwitcherCoordinator.presentCurrentConfiguration()
    }

    var isWindowSwitcherEnabled: Bool {
        applicationRegistry.isEffectivelyEnabled(
            WindowSwitcherApplication.applicationID
        )
    }

    var isWindowSwitcherAvailable: Bool {
        applicationRegistry.definition(for: WindowSwitcherApplication.applicationID) != nil
    }

    /// Opens the floating Shelf board from the menu bar.
    func openNewShelf() {
        showFloatingShelf(entryMode: .empty)
    }

    /// Opens the floating Shelf board in the clipboard entry layout from the menu bar.
    func openNewShelfFromClipboard() {
        showFloatingShelf(entryMode: .fromClipboard)
    }

    /// Current effective shortcut for a registered application or tool.
    func resolvedHotKey(for commandID: CommandID) -> LauncherHotKey? {
        guard applicationRegistry.isEffectivelyEnabled(commandID) else { return nil }
        return applicationRegistry.resolvedSettings(for: commandID)?.hotKey
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
        pendingCommandReference = nil
        pendingDirectPresentationReference = nil
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
        menuBarShortcuts.refresh()
        if applicationRegistry.isEffectivelyEnabled(HighlightModeApplication.applicationID) == false {
            highlightModeService.stop()
        } else if let settings = applicationRegistry.resolvedSettings(
            for: HighlightModeApplication.applicationID
        ) {
            highlightModeService.updateConfiguration(
                HighlightModeApplication.configuration(from: settings)
            )
        }
        configureWindowSwitcher()
        synchronizeMarkdownPreviewPreferences()
        refreshCommandCatalog()
        if let cachedSettingsViewModel {
            Task { @MainActor in
                await cachedSettingsViewModel.commandWheel.refreshCatalog()
            }
        }
        cachedLauncherViewModel?.applicationPreferencesDidChange()
        cachedDocumentationViewModel?.refresh()
    }

    private func configureWindowSwitcher() {
        let id = WindowSwitcherApplication.applicationID
        let configuration = applicationRegistry.resolvedSettings(for: id)
            .map(WindowSwitcherConfiguration.init(settings:)) ?? .default
        windowSwitcherCoordinator.configure(
            configuration,
            isEnabled: applicationRegistry.isEffectivelyEnabled(id)
        )
    }

    private func synchronizeMarkdownPreviewPreferences() {
        guard let settings = applicationRegistry.resolvedSettings(
            for: MarkdownPreviewApplication.applicationID
        ) else {
            return
        }
        do {
            try MarkdownPreferenceStore().save(
                MarkdownPreviewApplication.configuration(from: settings)
            )
        } catch {
            container.dependencies.logger.error(
                "Markdown Preview settings could not be shared with Quick Look"
            )
        }
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
        guard !CommandlyDebugLaunchOptions.usesProductivityFixture else { return }
        if isRecordingInstalledApplicationShortcut {
            globalShortcutMonitor.stop()
            globalShortcutRoutes.removeAll()
            activeWheelShortcutSessions.removeAll()
            return
        }
        let applicationHotKeys: [(CommandID, LauncherHotKey)] = applicationRegistry
            .allDefinitions()
            .compactMap { definition -> (CommandID, LauncherHotKey)? in
                guard applicationRegistry.isEffectivelyEnabled(definition.id),
                      let hotKey = applicationRegistry.resolvedSettings(for: definition.id)?.hotKey,
                      applicationRegistry.isLaunchableCommand(definition.id) else {
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
            wheelConfiguration: wheelConfiguration,
            installedApplicationHotKeys: InstalledApplicationShortcuts.orderedBindings(
                in: applicationPreferencesStore.load(), previousOwners: installedShortcutRegistrationOrder
            ),
            cyclesSoundOutput: volumeMixer.settings.switchesOutputsWithShortcut
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
        installedShortcutRegistrationOrder = bindings.compactMap { binding in
            guard issues[binding.registration.id] == nil,
                  case .installedApplication(let bundleID) = binding.route else { return nil }
            return bundleID
        }
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

        case .application(let commandID):
            if event.phase == .pressed { openApplicationFromHotKey(commandID) }

        case .installedApplication(let bundleIdentifier):
            if event.phase == .pressed { openInstalledApplicationFromHotKey(bundleIdentifier) }

        case .commandWheel(let profileID, let allowsContextOverride):
            handleCommandWheelShortcutEvent(
                event,
                profileID: profileID,
                allowsContextOverride: allowsContextOverride
            )

        case .soundOutputCycle:
            if event.phase == .pressed { volumeMixer.switchToNextOutput() }
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
        var installedIssues = [String: GlobalShortcutRegistrationIssue]()

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
            case .installedApplication(let bundleIdentifier):
                installedIssues[bundleIdentifier] = issue
            case .commandWheel(let profileID, _):
                wheelIssues[profileID] = issue
            case .launcher, .soundOutputCycle:
                // These have no per-item settings row to flag; the panel reports the mixer's
                // own failures inline.
                break
            }
        }
        applicationHotkeyIssues = applicationIssues
        installedApplicationHotkeyIssues = installedIssues
        commandWheelShortcutIssues = wheelIssues
    }

    private func setInstalledShortcutRecording(_ recording: Bool) {
        guard recording != isRecordingInstalledApplicationShortcut else { return }
        isRecordingInstalledApplicationShortcut = recording
        refreshGlobalShortcuts()
    }

    private func saveInstalledApplicationShortcut(_ hotKey: LauncherHotKey?, for bundleID: String) -> String? {
        guard !isRecordingInstalledApplicationShortcut else { return "Finish recording before saving the shortcut." }
        return InstalledApplicationShortcuts.save(hotKey, for: bundleID, store: applicationPreferencesStore) {
            refreshGlobalShortcuts()
            return installedApplicationHotkeyIssues
        }
    }

    private func openInstalledApplicationFromHotKey(_ bundleID: String) {
        let preferences = applicationPreferencesStore.load()
        guard preferences.hotKeys[bundleID] != nil, !preferences.isDisabled(bundleID),
              !activeInstalledApplicationShortcutBundles.contains(bundleID) else { return }
        activeInstalledApplicationShortcutBundles.insert(bundleID)
        let taskID = UUID()
        let context = makeCommandInvocationContext(source: .applicationHotKey)
        backgroundShortcutTasks[taskID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                activeInstalledApplicationShortcutBundles.remove(bundleID)
                backgroundShortcutTasks[taskID] = nil
            }
            guard !Task.isCancelled else { return }
            do {
                let result = try await commandCoordinator.execute(
                    reference: BuiltInCommandReference.openInstalledApplication(bundleIdentifier: bundleID),
                    context: context
                )
                if case .failure(let message) = result { presentCommandWheelStatus(message) }
            } catch is CancellationError {
                return
            } catch {
                presentCommandWheelStatus("Couldn’t open that application. It may have been moved or removed.")
            }
        }
    }

    /// Opens a registered application from a surface other than a global shortcut.
    ///
    /// The menu-bar panel uses this so a panel click is recorded as a menu-bar invocation rather
    /// than borrowing the shortcut path's provenance.
    func openRegisteredApplication(
        _ id: CommandID,
        source: CommandInvocationSource = .menuBar
    ) {
        openApplicationFromHotKey(id, source: source)
    }

    private func openApplicationFromHotKey(
        _ id: CommandID,
        source: CommandInvocationSource = .applicationHotKey
    ) {
        guard applicationRegistry.isEffectivelyEnabled(id) else { return }
        if id == ShelfApplication.applicationID {
            showFloatingShelf(entryMode: .empty)
            return
        }
        if applicationRegistry.isBackgroundInvokingCommand(id) {
            executeBackgroundApplicationFromHotKey(id, source: source)
            return
        }
        pendingCommandReference = CommandReference(commandID: id)
        showLauncher()
        DispatchQueue.main.async { [weak self] in
            guard let self, let viewModel = self.cachedLauncherViewModel else { return }
            self.consumePendingApplicationLaunch(using: viewModel)
        }
    }

    private func executeBackgroundApplicationFromHotKey(
        _ id: CommandID,
        source: CommandInvocationSource = .applicationHotKey
    ) {
        let context = makeCommandInvocationContext(source: source)
        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { backgroundShortcutTasks[taskID] = nil }
            do {
                let result = try await commandCoordinator.execute(
                    reference: CommandReference(commandID: id),
                    context: context
                )
                if case .failure(let message) = result {
                    presentCommandWheelStatus(message)
                }
            } catch {
                let message = (error as? SharedCommandExecutionCoordinatorError)?
                    .userFacingMessage ?? "Command couldn’t be completed."
                presentCommandWheelStatus(message)
            }
        }
        backgroundShortcutTasks[taskID] = task
    }

    private func invokeMenuBarCommand(_ id: CommandID) async {
        guard applicationRegistry.isEffectivelyEnabled(id) else { return }
        let foreground = frontmostApplicationContextProvider.snapshot()
        let context = CommandInvocationContext(source: .menuBar,
            frontmostApplicationBundleIdentifier: foreground?.bundleIdentifier,
            timestamp: container.dependencies.dateProvider.now())
        do {
            try await synchronizeCommandCatalog()
            try Task.checkCancellation()
            guard applicationRegistry.isEffectivelyEnabled(id) else { return }
            let result = try await commandCoordinator.execute(reference: CommandReference(commandID: id), context: context)
            if case .failure(let message) = result { presentCommandWheelStatus(message) }
        } catch is CancellationError {
            // Runtime teardown explicitly cancels pending menu actions.
        } catch {
            presentCommandWheelStatus((error as? SharedCommandExecutionCoordinatorError)?.userFacingMessage
                ?? "Command couldn’t be completed.")
        }
    }

    private func invokeBackgroundCommand(
        _ commandID: CommandID,
        operation: @escaping @MainActor () async -> CommandResult
    ) async -> CommandResult {
        let predecessor = backgroundInvocationTasks[commandID]
        let token = UUID()
        let task = Task { @MainActor in
            if let predecessor {
                _ = await predecessor.value
            }
            guard Task.isCancelled == false else { return CommandResult.cancelled }
            return await operation()
        }
        backgroundInvocationTasks[commandID] = task
        backgroundInvocationTokens[commandID] = token

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if backgroundInvocationTokens[commandID] == token {
            backgroundInvocationTasks[commandID] = nil
            backgroundInvocationTokens[commandID] = nil
        }
        return result
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
        let companionManager = systemCompanion.manager
        Task { await companionManager.disconnect() }
        menuBarShortcuts.stop()
        globalShortcutMonitor.stop()
        globalShortcutRoutes.removeAll()
        activeWheelShortcutSessions.removeAll()
        backgroundShortcutTasks.values.forEach { $0.cancel() }
        backgroundShortcutTasks.removeAll()
        backgroundInvocationTasks.values.forEach { $0.cancel() }
        backgroundInvocationTasks.removeAll()
        backgroundInvocationTokens.removeAll()
        commandWheelCoordinator.tearDown()
        commandWheelFeedbackRelay.tearDown()
        highlightModeService.stop()
        windowSwitcherCoordinator.tearDown()
        clipboardHistoryStore.stopMonitoring()
        autoQuitService.stop()
        keepAwake.tearDown()
        volumeMixer.tearDown()
        preciseVolumeSteps.stop()
        systemMetrics.stop()
        networkMetrics.stop()
        diskMetrics.stop()
        powerMetrics.stop()
        fanControl.tearDown()
        quickToggles.tearDown()
        scheduleAutoJoin.cancel()
        if let applicationTerminationObserver {
            NotificationCenter.default.removeObserver(applicationTerminationObserver)
            self.applicationTerminationObserver = nil
        }
    }

}
