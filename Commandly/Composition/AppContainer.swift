import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability
import Infrastructure

/// Composition root that owns long-lived services.
@MainActor
final class AppContainer {
    let dependencies: AppDependencies
    let appState: AppState
    let router: AppRouter
    private var cachedOnboardingViewModel: OnboardingViewModel?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let initialRoute: AppRoute = dependencies.onboardingStatusStore.hasCompletedOnboarding
            ? .root
            : .onboarding
        self.appState = AppState(metadata: dependencies.metadata, route: initialRoute)
        self.router = AppRouter(appState: appState)
    }

    func makeRootViewModel() -> RootViewModel {
        RootViewModel(metadata: dependencies.metadata)
    }

    func makeOnboardingViewModel(onFinished: @escaping () -> Void = {}) -> OnboardingViewModel {
        if let cachedOnboardingViewModel {
            return cachedOnboardingViewModel
        }
        let viewModel = OnboardingViewModel(
            statusStore: dependencies.onboardingStatusStore,
            settingsStore: dependencies.appSettingsStore,
            loginItemManager: dependencies.loginItemManager,
            permissionService: dependencies.permissionService,
            privacySettingsOpener: dependencies.privacySettingsOpener,
            onFinished: { [weak self] in
                self?.router.navigate(to: .root)
                onFinished()
            }
        )
        cachedOnboardingViewModel = viewModel
        return viewModel
    }

    /// Drops the cached onboarding view model so the next presentation starts at welcome.
    func clearOnboardingViewModelCache() {
        cachedOnboardingViewModel = nil
    }

    func makeSettingsViewModel(
        onMenuBarIconChange: @escaping (Bool) -> Void = { _ in },
        onTextSizeChange: @escaping (AppTextSizePreference) -> Void = { _ in },
        onViewModeChange: @escaping (AppViewModePreference) -> Void = { _ in }
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsStore: dependencies.appSettingsStore,
            loginItemManager: dependencies.loginItemManager,
            permissionService: dependencies.permissionService,
            privacySettingsOpener: dependencies.privacySettingsOpener,
            metadata: dependencies.metadata,
            onMenuBarIconChange: onMenuBarIconChange,
            onTextSizeChange: onTextSizeChange,
            onViewModeChange: onViewModeChange
        )
    }

    static func bootstrap() -> AppContainer {
        AppBootstrapper.bootstrap()
    }
}
