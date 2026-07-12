import AppKit
import SwiftUI

enum CommandlyWindowIdentifier {
    static let settings = NSUserInterfaceItemIdentifier("commandly.settings")
    static let launcher = NSUserInterfaceItemIdentifier("commandly.launcher")
}

/// Activates the app and brings the hosting `NSWindow` to the front when it first attaches.
///
/// Does not change window level (no permanent floating panel). Use
/// ``raiseWindows(with:)`` when re-presenting an already-open window (e.g. Settings…).
struct BringHostingWindowToFront: NSViewRepresentable {
    var identifier: NSUserInterfaceItemIdentifier?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        scheduleConfigure(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfigure(for: nsView, coordinator: context.coordinator)
    }

    private func scheduleConfigure(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.configure(view.window, identifier: identifier)
        }
    }

    /// Activates Commandly and orders matching windows front (and deminiaturizes if needed).
    @MainActor
    static func raiseWindows(with identifier: NSUserInterfaceItemIdentifier) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier == identifier {
            raise(window)
        }
    }

    @MainActor
    static func raise(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        // Accessory (LSUIElement) apps often need this so the window appears above others
        // even while activation is settling; it does not keep a floating window level.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        @MainActor
        func configure(_ window: NSWindow?, identifier: NSUserInterfaceItemIdentifier?) {
            guard let window else { return }

            if let identifier {
                window.identifier = identifier
            }

            // Only auto-raise when the hosting window first becomes available — not on
            // every SwiftUI update (that would steal focus from other apps).
            guard configuredWindow !== window else { return }
            configuredWindow = window
            BringHostingWindowToFront.raise(window)
        }
    }
}

extension View {
    /// Marks the hosting window (optional) and brings it to the front when presented.
    func bringHostingWindowToFront(
        identifier: NSUserInterfaceItemIdentifier? = nil
    ) -> some View {
        background(BringHostingWindowToFront(identifier: identifier))
    }
}
