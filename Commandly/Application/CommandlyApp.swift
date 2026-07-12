import SwiftUI
import Observability
import DesignSystem
import AppKit

@main
struct CommandlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime()

    var body: some Scene {
        @Bindable var runtime = runtime

        MenuBarExtra("Commandly", systemImage: "command", isInserted: $runtime.showMenuBarIcon) {
            StatusBarMenu(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
        }
        .menuBarExtraStyle(.menu)

        Window("Commandly Setup", id: AppWindowID.onboarding) {
            OnboardingWindowHost(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: LayoutConstants.onboardingIdealWidth,
            height: LayoutConstants.onboardingIdealHeight
        )
        .defaultLaunchBehavior(runtime.showsOnboarding ? .presented : .suppressed)

        Settings {
            SettingsRootView(viewModel: runtime.makeSettingsViewModel())
                .commandlyContentSize(runtime.textSize)
        }
        .defaultSize(
            width: LayoutConstants.settingsMinWidth,
            height: LayoutConstants.settingsMinHeight
        )
    }
}

enum AppWindowID {
    static let onboarding = "onboarding"
}

/// Hosts onboarding and dismisses the setup window when onboarding completes.
private struct OnboardingWindowHost: View {
    @Bindable var runtime: AppRuntime
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if runtime.showsOnboarding {
                OnboardingRootView(viewModel: runtime.makeOnboardingViewModel())
                    .environment(runtime.container.appState)
                    .onAppear {
                        NSApp.activate(ignoringOtherApps: true)
                    }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: runtime.showsOnboarding) { _, isShowing in
            if isShowing == false {
                dismissWindow(id: AppWindowID.onboarding)
            }
        }
    }
}
