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

        MenuBarExtra(isInserted: $runtime.showMenuBarIcon) {
            StatusBarMenu(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
        } label: {
            Label("Commandly", systemImage: "command")
        }
        .menuBarExtraStyle(.menu)

        Window("", id: AppWindowID.presentationHost) {
            WindowPresentationHost(runtime: runtime)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
        .defaultLaunchBehavior(.presented)

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

        Window("Commandly Shelf", id: AppWindowID.shelf) {
            ShelfWindowHost(runtime: runtime)
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: LayoutConstants.shelfBoardSize,
            height: LayoutConstants.shelfBoardSize
        )
        .defaultLaunchBehavior(.suppressed)
        .commands {
            DocumentationCommands()
        }

        Settings {
            SettingsRootView(viewModel: runtime.makeSettingsViewModel())
                .commandlyContentSize(runtime.textSize)
                .commandlyViewMode(runtime.viewMode)
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
    static let presentationHost = "window-presentation-host"
    static let onboarding = "onboarding"
    static let launcher = "launcher"
    static let documentation = "documentation"
    static let shelf = "shelf"
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

/// Keeps scene actions available for global shortcuts even when the menu-bar icon is hidden.
private struct WindowPresentationHost: View {
    @Bindable var runtime: AppRuntime
    @State private var hasInstalledActions = false

    var body: some View {
        ZStack {
            LauncherPresentationBridge(
                runtime: runtime,
                onInstalled: {
                    hasInstalledActions = true
                }
            )

            if hasInstalledActions {
                PresentationHostWindowHider()
            }
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
    }
}

/// Opens / dismisses the launcher and Shelf windows for runtime presentation requests.
private struct LauncherPresentationBridge: View {
    @Bindable var runtime: AppRuntime
    var onInstalled: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var owner = UUID()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                runtime.installWindowPresentationActions(
                    owner: owner,
                    openLauncher: {
                        openWindow(id: AppWindowID.launcher)
                    },
                    dismissLauncher: {
                        dismissWindow(id: AppWindowID.launcher)
                    },
                    openShelf: {
                        openWindow(id: AppWindowID.shelf)
                    },
                    dismissShelf: {
                        dismissWindow(id: AppWindowID.shelf)
                    }
                )
                onInstalled()
            }
            .onDisappear {
                runtime.uninstallWindowPresentationActions(owner: owner)
            }
    }
}

/// Makes the app-lifetime action host nonvisual and removes it from normal window behavior.
private struct PresentationHostWindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAttachmentProbeView {
        let view = WindowAttachmentProbeView(frame: .zero)
        view.isHidden = true
        view.onWindowAttached = configure
        view.attachIfPossible()
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentProbeView, context: Context) {
        nsView.onWindowAttached = configure
        nsView.attachIfPossible()
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentProbeView,
        coordinator: Void
    ) {
        nsView.onWindowAttached = nil
    }

    @MainActor
    private func configure(_ window: NSWindow) {
        window.identifier = CommandlyWindowIdentifier.presentationHost
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.ignoresCycle]
        window.setFrame(
            NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            display: false
        )
        // Leave the attachment transaction before ordering out. The host is already transparent,
        // offscreen, noninteractive, and excluded from normal window behavior during this turn.
        DispatchQueue.main.async { [weak window] in
            window?.orderOut(nil)
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
        LauncherRootView(
            viewModel: viewModel,
            presentationRequest: runtime.launcherPresentationRequest
        )
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
            // Window was dismissed explicitly (Escape, hotkey toggle, or programmatic close).
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

/// Hosts the floating Shelf board and keeps runtime visibility in sync when it closes.
private struct ShelfWindowHost: View {
    @Bindable var runtime: AppRuntime
    @State private var boardModel: ShelfBoardModel?
    @State private var interaction = ShelfBoardInteractionState()

    var body: some View {
        Group {
            if let boardModel {
                ShelfBoardView(model: boardModel, interaction: interaction)
                    .id(runtime.shelfPresentationRequest.generation)
            } else {
                Color.clear
                    .frame(
                        width: LayoutConstants.shelfBoardSize,
                        height: LayoutConstants.shelfBoardSize
                    )
                    .accessibilityHidden(true)
            }
        }
        .shelfWindowChrome(
            preferredCorner: runtime.shelfPreferredCorner,
            presentationRequest: runtime.shelfPresentationRequest,
            interaction: interaction,
            onEscape: {
                runtime.hideShelf()
                return true
            },
            onKeyDown: handleKeyDown
        )
        .onAppear {
            runtime.showsShelf = true
            boardModel = runtime.makeShelfBoardModel(onClose: { runtime.hideShelf() })
        }
        .onChange(of: runtime.shelfPresentationRequest.generation) { _, generation in
            _ = generation
            boardModel?.tearDown()
            interaction.endShelfItemDrag()
            boardModel = runtime.makeShelfBoardModel(onClose: { runtime.hideShelf() })
        }
        .onDisappear {
            boardModel?.tearDown()
            if runtime.showsShelf {
                runtime.showsShelf = false
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let boardModel else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.keyCode == 49, modifiers.isEmpty {
            boardModel.previewSelected()
            return true
        }
        if [51, 117].contains(event.keyCode), modifiers.isEmpty {
            boardModel.clear()
            return true
        }
        if event.keyCode == 48, modifiers.isEmpty, boardModel.items.isEmpty == false {
            boardModel.isShowingDetails.toggle()
            return true
        }
        if event.keyCode == 8, modifiers == .command {
            Task {
                await boardModel.copyItemsToClipboard()
            }
            return true
        }
        if event.keyCode == 9, modifiers == .command {
            Task {
                await boardModel.addFromClipboard()
            }
            return true
        }
        if event.keyCode == 13, modifiers == .command {
            runtime.hideShelf()
            return true
        }
        return false
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
