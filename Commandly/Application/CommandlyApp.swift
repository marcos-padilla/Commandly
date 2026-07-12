import SwiftUI
import Observability

@main
struct CommandlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: container.makeRootViewModel())
                .environment(container.appState)
        }

        Settings {
            SettingsRootView()
        }
    }
}
