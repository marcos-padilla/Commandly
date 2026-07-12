import AppKit
import Observability

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon; onboarding/settings windows can still appear.
        NSApp.setActivationPolicy(.accessory)
        Loggers.lifecycle.info("Application did finish launching as menu bar agent")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Loggers.lifecycle.info("Application will terminate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running after onboarding/settings windows close.
        false
    }
}
