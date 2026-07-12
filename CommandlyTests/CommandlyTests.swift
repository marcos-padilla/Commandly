import Testing
@testable import Commandly
import AppCore

struct CommandlyTests {
    @Test @MainActor func dependencyContainerBootstraps() {
        let container = AppContainer.bootstrap()
        #expect(container.dependencies.metadata.name == "Commandly")
        #expect(container.appState.route == .root)
        let viewModel = container.makeRootViewModel()
        #expect(viewModel.status == "Foundation ready")
        #expect(viewModel.message == "Feature development has not started yet.")
    }

    @Test @MainActor func routerUpdatesAppState() {
        let container = AppContainer.bootstrap()
        container.router.navigate(to: .settings)
        #expect(container.appState.route == .settings)
    }
}
