import SwiftUI
import AppKit

/// Menu bar dropdown for the always-on Commandly status item.
struct StatusBarMenu: View {
    @Bindable var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Commandly")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .accessibilityAddTraits(.isHeader)

            Divider()

            Button("Open Commandly") {
                runtime.showLauncher()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Button("Settings…") {
                presentSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            #if DEBUG
            Divider()

            Button("Restart Onboarding (dev)") {
                runtime.restartOnboarding()
                openWindow(id: AppWindowID.onboarding)
                NSApp.activate(ignoringOtherApps: true)
            }
            #endif

            Divider()

            Button("Quit Commandly") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        BringHostingWindowToFront.raiseWindows(with: CommandlyWindowIdentifier.settings)
    }
}

#Preview {
    StatusBarMenu(runtime: AppRuntime())
        .frame(width: 240)
}
