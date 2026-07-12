import Foundation
import Observation
import Infrastructure
import AppKit

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

    init(container: AppContainer = .bootstrap()) {
        self.container = container
        let settings = container.dependencies.appSettingsStore.load()
        self.showsOnboarding = container.appState.route == .onboarding
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.textSize = settings.textSize
        self.viewMode = settings.viewMode
        startHotkeyMonitor()
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        container.makeOnboardingViewModel { [weak self] in
            self?.showsOnboarding = false
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
        if let cachedLauncherViewModel {
            cachedLauncherViewModel.onDismiss = { [weak self] in
                self?.hideLauncher()
            }
            cachedLauncherViewModel.onOpenSettings = onOpenSettings
            return cachedLauncherViewModel
        }
        let viewModel = LauncherViewModel(
            onDismiss: { [weak self] in
                self?.hideLauncher()
            },
            onOpenSettings: onOpenSettings
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
        }
    }

    func hideLauncher() {
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

        Task {
            try? await dependencies.loginItemManager.setEnabled(false)
        }
    }

    private func startHotkeyMonitor() {
        hotkeyMonitor.start { [weak self] in
            Task { @MainActor in
                self?.toggleLauncher()
            }
        }
    }
}
