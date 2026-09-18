import AppKit
import Infrastructure
import SwiftUI
import SystemCompanionKit

/// Default helper launch owns a visible setup window. It never starts an XPC listener or registers on launch.
@MainActor
enum SystemCompanionSetupApplication {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let model = SystemCompanionSetupModel(service: CompanionSetupService(
            registration: NativeCompanionRegistration(), validation: NativeCompanionSetupValidator()))
        let delegate = SetupDelegate(model: model)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class SetupDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: SystemCompanionSetupModel
    private var window: NSWindow?
    init(model: SystemCompanionSetupModel) { self.model = model }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Companion Setup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Commandly Companion Setup"; window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 490, height: 440)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SystemCompanionSetupView(model: model) { [weak self] in self?.window?.performClose(nil) })
        self.window = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.refresh()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil); return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.permitsClosing() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.permitsClosing() ? .terminateNow : .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
