import SwiftUI
import Observability
import DesignSystem
import AppKit
import CommandKit

@main
struct CommandlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime()

    var body: some Scene {
        @Bindable var runtime = runtime

        MenuBarExtra("Commandly", systemImage: "command", isInserted: $runtime.showMenuBarIcon) {
            StatusBarMenu(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
                .background(LauncherPresentationBridge(runtime: runtime))
        }
        .menuBarExtraStyle(.menu)

        Window("Commandly", id: AppWindowID.launcher) {
            LauncherWindowHost(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: LayoutConstants.launcherIdealWidth,
            height: LayoutConstants.launcherIdealHeight
        )
        .defaultLaunchBehavior(CommandlyDebugLaunchOptions.showsLauncherAtLaunch ? .presented : .suppressed)
        .commands {
            DocumentationCommands()
        }

        Window("Commandly Documentation", id: AppWindowID.documentation) {
            DocumentationWindowHost(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: LayoutConstants.documentationIdealWidth,
            height: LayoutConstants.documentationIdealHeight
        )
        .defaultLaunchBehavior(.suppressed)
        .commands {
            DocumentationCommands()
        }

        Window("Commandly Setup", id: AppWindowID.onboarding) {
            OnboardingWindowHost(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: LayoutConstants.onboardingIdealWidth,
            height: LayoutConstants.onboardingIdealHeight
        )
        .defaultLaunchBehavior(runtime.showsOnboarding ? .presented : .suppressed)
        .commands {
            DocumentationCommands()
        }

        Settings {
            SettingsRootView(viewModel: runtime.makeSettingsViewModel())
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
                .background(LauncherPresentationBridge(runtime: runtime))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: LayoutConstants.settingsIdealWidth,
            height: LayoutConstants.settingsIdealHeight
        )
        .commands {
            DocumentationCommands()
        }
    }
}

enum CommandlyDebugLaunchOptions {
    #if DEBUG
    static let showsLauncherAtLaunch = ProcessInfo.processInfo.arguments.contains(
        "--commandly-show-launcher"
    )
    static let fileSearchQuery: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--commandly-file-search-query"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
    }()
    static let usesFileSearchFixture = ProcessInfo.processInfo.arguments.contains(
        "--commandly-file-search-fixture"
    )
    static let skipsOnboarding = ProcessInfo.processInfo.arguments.contains(
        "--commandly-skip-onboarding"
    )
    #else
    static let showsLauncherAtLaunch = false
    static let fileSearchQuery: String? = nil
    static let usesFileSearchFixture = false
    static let skipsOnboarding = false
    #endif
}

enum AppWindowID {
    static let onboarding = "onboarding"
    static let launcher = "launcher"
    static let documentation = "documentation"
}

/// Adds a standard Help-menu route that works whenever a Commandly window is active.
private struct DocumentationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Commandly Documentation") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppWindowID.documentation)
                DispatchQueue.main.async {
                    BringHostingWindowToFront.raiseWindows(
                        with: CommandlyWindowIdentifier.documentation
                    )
                }
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// Opens / dismisses the launcher window when `AppRuntime.showsLauncher` changes.
private struct LauncherPresentationBridge: View {
    @Bindable var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                runtime.openLauncherWindow = {
                    openWindow(id: AppWindowID.launcher)
                }
                runtime.dismissLauncherWindow = {
                    dismissWindow(id: AppWindowID.launcher)
                }
            }
            .onChange(of: runtime.showsLauncher) { _, isShowing in
                if isShowing {
                    openWindow(id: AppWindowID.launcher)
                    NSApp.activate(ignoringOtherApps: true)
                    // Defer raise until SwiftUI has materialised / reused the window.
                    DispatchQueue.main.async {
                        BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.launcher)
                    }
                } else {
                    dismissWindow(id: AppWindowID.launcher)
                }
            }
    }
}

/// Hosts the launcher panel and keeps runtime visibility in sync when the window closes.
private struct LauncherWindowHost: View {
    @Bindable var runtime: AppRuntime
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let viewModel = runtime.makeLauncherViewModel(
            onOpenSettings: presentSettings,
            onOpenDocumentation: presentDocumentation
        )
        LauncherRootView(viewModel: viewModel)
        .onAppear {
            runtime.showsLauncher = true
            runtime.consumePendingApplicationLaunch(using: viewModel)
            if let query = CommandlyDebugLaunchOptions.fileSearchQuery,
               viewModel.route == .root {
                viewModel.launch(BuiltInCommandID.searchFiles)
                viewModel.activeApplicationModel(as: FileSearchViewModel.self)?.query = query
            }
        }
        .onDisappear {
            // Window was dismissed (Esc, outside click, or programmatic close).
            if runtime.showsLauncher {
                runtime.showsLauncher = false
            }
        }
    }

    private func presentSettings() {
        runtime.hideLauncher()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.settings)
    }

    private func presentDocumentation() {
        runtime.hideLauncher()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppWindowID.documentation)
        DispatchQueue.main.async {
            BringHostingWindowToFront.raiseWindows(
                with: CommandlyWindowIdentifier.documentation
            )
        }
    }
}

private struct DocumentationWindowHost: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        DocumentationRootView(viewModel: runtime.makeDocumentationViewModel())
    }
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
