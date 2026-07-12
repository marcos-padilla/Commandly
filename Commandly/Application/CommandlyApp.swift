import SwiftUI
import Observability
import DesignSystem

@main
struct CommandlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            AppSceneRoot(container: container)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: LayoutConstants.onboardingIdealWidth,
            height: LayoutConstants.onboardingIdealHeight
        )

        Settings {
            SettingsRootView()
        }
    }
}

/// Observes `AppState` so onboarding completion can swap the root surface.
private struct AppSceneRoot: View {
    let container: AppContainer
    @Bindable private var appState: AppState

    init(container: AppContainer) {
        self.container = container
        self.appState = container.appState
    }

    var body: some View {
        Group {
            switch appState.route {
            case .onboarding:
                OnboardingRootView(viewModel: container.makeOnboardingViewModel())
            case .root, .settings:
                RootView(viewModel: container.makeRootViewModel())
            }
        }
        .environment(appState)
    }
}
