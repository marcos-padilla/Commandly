import AppKit
import Observability

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var floatingNotes: FloatingNoteCoordinator? {
        didSet { terminationCoordinator.floatingNotes = floatingNotes }
    }
    weak var screenRecording: ScreenRecordingCoordinator? {
        didSet { terminationCoordinator.screenRecording = screenRecording }
    }
    weak var displayResolution: DisplayResolutionCoordinator? {
        didSet { terminationCoordinator.displayResolution = displayResolution }
    }
    weak var writingServices: NativeWritingServiceProvider? {
        didSet {
            if hasFinishedLaunching { NSApp.servicesProvider = writingServices }
        }
    }
    private var hasFinishedLaunching = false
    private let terminationCoordinator = ApplicationTerminationCoordinator()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationCoordinator.isReviewing == false else { return .terminateLater }
        guard terminationCoordinator.requiresReview else { return .terminateNow }
        terminationCoordinator.review { [weak sender] shouldTerminate in
            sender?.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon; onboarding/settings windows can still appear.
        NSApp.setActivationPolicy(.accessory)
        hasFinishedLaunching = true
        NSApp.servicesProvider = writingServices
        Loggers.lifecycle.info("Application did finish launching as menu bar agent")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.servicesProvider = nil
        Loggers.lifecycle.info("Application will terminate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running after onboarding/settings windows close.
        false
    }
}
