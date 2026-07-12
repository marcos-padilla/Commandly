import Foundation

@MainActor
final class AppRouter {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func navigate(to route: AppRoute) {
        appState.route = route
    }
}
