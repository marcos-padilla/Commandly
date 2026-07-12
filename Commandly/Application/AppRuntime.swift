import Foundation
import Observation
import Infrastructure
import AppKit
import CommandKit

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
    let commandCatalog: CommandCatalog
    /// Pasteboard monitoring must not invalidate scene/`@Bindable` runtime UI.
    /// Views that need history observe the store through command view models.
    @ObservationIgnored
    let clipboardHistoryStore: ClipboardHistoryStore
    @ObservationIgnored
    let fileSearchService: SpotlightFileSearchService
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    private let autoQuitService: AutoQuitService

    init(container: AppContainer = .bootstrap()) {
        self.container = container
        let settings = container.dependencies.appSettingsStore.load()
        self.showsOnboarding = container.appState.route == .onboarding
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.textSize = settings.textSize
        self.viewMode = settings.viewMode
        self.commandCatalog = .makeBuiltIn()
        self.clipboardHistoryStore = ClipboardHistoryStore(
            enricher: VisionClipboardContentEnricher()
        )
        self.fileSearchService = SpotlightFileSearchService(
            folderAccessStore: container.dependencies.folderAccessStore
        )
        let applicationPreferencesStore = container.dependencies.applicationPreferencesStore
        self.applicationPreferencesStore = applicationPreferencesStore
        self.autoQuitService = AutoQuitService(preferencesStore: applicationPreferencesStore)
        startHotkeyMonitor()
        registerBuiltInCommands()
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
            catalog: commandCatalog,
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchService: fileSearchService,
            urlOpener: WorkspaceURLOpener(),
            applicationOpener: WorkspaceApplicationOpener(),
            applicationQuery: WorkspaceInstalledApplicationQuery(),
            applicationPreferencesStore: applicationPreferencesStore,
            fileRevealer: WorkspaceFileRevealer(),
            fileActionService: WorkspaceFileActionService(),
            bundleManager: WorkspaceApplicationBundleManager(),
            finderInfoPresenter: FinderAppleScriptInfoPresenter(),
            uninstallDiscoverer: WorkspaceApplicationUninstallDiscoverer(),
            onDismiss: { [weak self] in
                self?.hideLauncher()
            },
            onOpenSettings: onOpenSettings,
            onQuit: quit
        )
        cachedLauncherViewModel = viewModel
        return viewModel
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

        Task {
            try? await dependencies.loginItemManager.setEnabled(false)
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

    private func registerBuiltInCommands() {
        let registry = container.dependencies.commandRegistry
        let manifests = commandCatalog.allManifests()
        Task {
            for manifest in manifests {
                try? await registry.register(manifest)
            }
        }
        clipboardHistoryStore.startMonitoring()
    }

}
