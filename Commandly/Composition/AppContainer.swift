import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability

/// Composition root that owns long-lived services.
@MainActor
final class AppContainer {
    let dependencies: AppDependencies
    let appState: AppState
    let router: AppRouter

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.appState = AppState(metadata: dependencies.metadata)
        self.router = AppRouter(appState: appState)
    }

    func makeRootViewModel() -> RootViewModel {
        RootViewModel(metadata: dependencies.metadata)
    }

    static func bootstrap() -> AppContainer {
        AppBootstrapper.bootstrap()
    }
}
