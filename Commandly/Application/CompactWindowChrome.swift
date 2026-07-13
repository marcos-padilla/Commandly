import AppKit
import SwiftUI

/// Makes the hosting window titlebar-less while keeping close and minimize controls.
struct CompactWindowChrome: NSViewRepresentable {
    var hidesZoomButton: Bool = true

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
            coordinator.configure(view.window, hidesZoomButton: hidesZoomButton)
        }
    }

    @MainActor
    final class Coordinator {
        func configure(_ window: NSWindow?, hidesZoomButton: Bool) {
            guard let window else { return }

            if window.title.isEmpty == false {
                window.title = ""
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if window.titlebarAppearsTransparent == false {
                window.titlebarAppearsTransparent = true
            }
            if window.styleMask.contains(.fullSizeContentView) == false {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.isMovableByWindowBackground == false {
                window.isMovableByWindowBackground = true
            }
            if window.toolbar != nil {
                window.toolbar = nil
            }

            setHidden(false, for: .closeButton, in: window)
            setHidden(false, for: .miniaturizeButton, in: window)
            setHidden(hidesZoomButton, for: .zoomButton, in: window)
        }

        private func setHidden(
            _ isHidden: Bool,
            for button: NSWindow.ButtonType,
            in window: NSWindow
        ) {
            guard let control = window.standardWindowButton(button),
                  control.isHidden != isHidden else {
                return
            }
            control.isHidden = isHidden
        }
    }
}

extension View {
    /// Hides the title bar and zoom control; leaves close and minimize visible.
    func compactWindowChrome(hidesZoomButton: Bool = true) -> some View {
        background(CompactWindowChrome(hidesZoomButton: hidesZoomButton))
    }
}
