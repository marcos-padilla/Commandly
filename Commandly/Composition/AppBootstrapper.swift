import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability

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

        let dependencies = AppDependencies(
            metadata: metadata,
            dateProvider: SystemDateProvider(),
            uuidProvider: SystemUUIDProvider(),
            commandRegistry: CommandRegistry(),
            persistenceStore: InMemoryPersistenceStore(),
            permissionChecker: InMemoryPermissionChecker(),
            logger: Loggers.application
        )

        dependencies.logger.info("Bootstrapping Commandly foundation")
        return AppContainer(dependencies: dependencies)
    }
}
