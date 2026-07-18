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

    /// Builds the single shared command execution path used by every invocation surface.
    func makeSharedCommandExecutionCoordinator(
        applicationRegistry: LauncherApplicationRegistry,
        presentationHandler: RegisteredLauncherApplicationPresentationHandler,
        availabilityEvaluator: ProductionCommandAvailabilityEvaluator
    ) -> SharedCommandExecutionCoordinator {
        let commandRegistry = dependencies.commandRegistry
        let executor = SharedCommandExecutor(
            applicationOpener: dependencies.applicationOpener,
            registeredApplicationPresenter: presentationHandler,
            installedApplicationUsageRecorder:
                ApplicationPreferencesInstalledApplicationUsageRecorder(
                    preferencesStore: dependencies.applicationPreferencesStore
                )
        )
        let catalogSynchronizer: SharedCommandExecutionCoordinator.CatalogSynchronizer = {
            @MainActor in
            let snapshot = await availabilityEvaluator.snapshot()
            try await commandRegistry.replaceCatalog(
                with: snapshot.manifests,
                availability: snapshot.availability
            )
        }
        return SharedCommandExecutionCoordinator(
            resolver: commandRegistry,
            executor: executor,
            usageHistory: dependencies.commandUsageHistory,
            dateProvider: dependencies.dateProvider,
            catalogSynchronizer: catalogSynchronizer
        )
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
        aiSettingsModel: AISettingsModel? = nil,
        onMenuBarIconChange: @escaping (Bool) -> Void = { _ in },
        onTextSizeChange: @escaping (AppTextSizePreference) -> Void = { _ in },
        onViewModeChange: @escaping (AppViewModePreference) -> Void = { _ in },
        applicationRegistry: LauncherApplicationRegistry? = nil,
        commandWheelProfileStore: CommandWheelProfileStore? = nil,
        commandWheelCatalog: CommandWheelCommandCatalogSnapshot? = nil,
        commandWheelCatalogProvider:
            (@MainActor @Sendable () async -> CommandCatalogSnapshot)? = nil,
        commandWheelInstalledApplicationQuery: any InstalledApplicationQuerying =
            InMemoryInstalledApplicationQuery(),
        commandWheelShortcutIssues:
            (@MainActor () -> [UUID: GlobalShortcutRegistrationIssue])? = nil,
        onApplicationPreferencesChange: @escaping () -> Void = {},
        applicationHotkeyIssues: @escaping () -> [CommandID: ApplicationHotkeyRegistrationIssue] = { [:] }
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsStore: dependencies.appSettingsStore,
            loginItemManager: dependencies.loginItemManager,
            permissionService: dependencies.permissionService,
            privacySettingsOpener: dependencies.privacySettingsOpener,
            metadata: dependencies.metadata,
            aiSettingsModel: aiSettingsModel,
            applicationRegistry: applicationRegistry,
            commandWheelProfileStore: commandWheelProfileStore,
            commandWheelCatalog: commandWheelCatalog,
            commandWheelCatalogProvider: commandWheelCatalogProvider,
            commandWheelInstalledApplicationQuery: commandWheelInstalledApplicationQuery,
            commandWheelShortcutIssues: commandWheelShortcutIssues,
            onApplicationPreferencesChange: onApplicationPreferencesChange,
            applicationHotkeyIssues: applicationHotkeyIssues,
            onMenuBarIconChange: onMenuBarIconChange,
            onTextSizeChange: onTextSizeChange,
            onViewModeChange: onViewModeChange
        )
    }

    static func bootstrap() -> AppContainer {
        AppBootstrapper.bootstrap()
    }
}
