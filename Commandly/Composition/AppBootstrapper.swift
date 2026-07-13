import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability
import Infrastructure

enum AppBootstrapper {
    @MainActor
    static func bootstrap() -> AppContainer {
        let environment: ApplicationEnvironment
        #if DEBUG
        environment = .development
        #else
        environment = .production
        #endif

        let metadata = ApplicationMetadata(
            name: "Commandly",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.businessmate360.Commandly",
            environment: environment
        )

        let folderAccessStore = UserDefaultsFolderAccessStore()
        let permissionService = SystemPermissionService(folderAccessStore: folderAccessStore)

        let dependencies = AppDependencies(
            metadata: metadata,
            dateProvider: SystemDateProvider(),
            uuidProvider: SystemUUIDProvider(),
            commandRegistry: CommandRegistry(),
            persistenceStore: InMemoryPersistenceStore(),
            permissionService: permissionService,
            privacySettingsOpener: WorkspacePrivacySettingsOpener(),
            onboardingStatusStore: UserDefaultsOnboardingStatusStore(),
            appSettingsStore: UserDefaultsAppSettingsStore(),
            launcherApplicationPreferencesStore: UserDefaultsLauncherApplicationPreferencesStore(),
            applicationPreferencesStore: UserDefaultsApplicationPreferencesStore(),
            folderAccessStore: folderAccessStore,
            loginItemManager: SMAppServiceLoginItemManager(),
            logger: Loggers.application
        )

        dependencies.logger.info("Bootstrapping Commandly foundation")
        return AppContainer(dependencies: dependencies)
    }
}
