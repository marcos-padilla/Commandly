import AppKit
import SwiftUI

/// Lets Escape clear documentation search even while AppKit's field editor owns the event.
struct DocumentationEscapeKeyInterceptor: NSViewRepresentable {
    let onEscape: @MainActor () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.onEscape = onEscape
        scheduleAttach(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
        scheduleAttach(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    private func scheduleAttach(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.attach(to: view.window)
        }
    }

    /// AppKit owns the monitor callback. Its state is installed, read, and removed on the main queue.
    final class Coordinator: @unchecked Sendable {
        var onEscape: @MainActor () -> Bool
        private weak var window: NSWindow?
        private var keyMonitor: Any?

        init(onEscape: @escaping @MainActor () -> Bool) {
            self.onEscape = onEscape
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }
            if self.window !== window {
                tearDown()
                self.window = window
            }
            guard keyMonitor == nil else { return }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53 else { return event }
                guard event.modifierFlags
                    .intersection([.command, .option, .control, .shift])
                    .isEmpty
                else {
                    return event
                }

                var consumed = false
                if Thread.isMainThread {
                    consumed = self.handleEscapeOnMain()
                } else {
                    DispatchQueue.main.sync {
                        consumed = self.handleEscapeOnMain()
                    }
                }
                return consumed ? nil : event
            }
        }

        @MainActor
        func tearDown() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            window = nil
        }

        @MainActor
        private func handleEscapeOnMain() -> Bool {
            guard let window, window.isKeyWindow, window.isVisible else { return false }
            return onEscape()
        }
    }
}
