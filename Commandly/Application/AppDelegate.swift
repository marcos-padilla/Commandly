import AppKit
import Observability

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Loggers.lifecycle.info("Application did finish launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Loggers.lifecycle.info("Application will terminate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
