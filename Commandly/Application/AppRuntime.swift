import Foundation
import Observation
import Infrastructure

/// Observable app runtime for scene-level UI that must react to onboarding completion.
@Observable
@MainActor
final class AppRuntime {
    let container: AppContainer
    var showsOnboarding: Bool
    var showMenuBarIcon: Bool
    private var cachedSettingsViewModel: SettingsViewModel?

    init(container: AppContainer = .bootstrap()) {
        self.container = container
        self.showsOnboarding = container.appState.route == .onboarding
        self.showMenuBarIcon = container.dependencies.appSettingsStore.load().showMenuBarIcon
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
        let viewModel = container.makeSettingsViewModel { [weak self] showIcon in
            self?.showMenuBarIcon = showIcon
        }
        cachedSettingsViewModel = viewModel
        return viewModel
    }

    /// DEBUG helper: clears first-run progress and presents onboarding again.
    func restartOnboarding() {
        let dependencies = container.dependencies
        dependencies.onboardingStatusStore.resetOnboardingCompletion()
        dependencies.appSettingsStore.save(.default)
        dependencies.folderAccessStore.saveBookmarks([])
        container.clearOnboardingViewModelCache()
        cachedSettingsViewModel = nil
        container.router.navigate(to: .onboarding)
        showsOnboarding = true
        showMenuBarIcon = true

        Task {
            try? await dependencies.loginItemManager.setEnabled(false)
        }
    }
}
