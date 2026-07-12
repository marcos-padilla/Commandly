import AppKit
import SwiftUI

/// Makes the hosting window titlebar-less while keeping close and minimize controls.
struct CompactWindowChrome: NSViewRepresentable {
    var hidesZoomButton: Bool = true

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        scheduleConfigure(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfigure(for: nsView)
    }

    private func scheduleConfigure(for view: NSView) {
        DispatchQueue.main.async {
            Self.applyChrome(to: view.window, hidesZoomButton: hidesZoomButton)
        }
    }

    private static func applyChrome(to window: NSWindow?, hidesZoomButton: Bool) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.toolbar = nil

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = hidesZoomButton
    }
}

extension View {
    /// Hides the title bar and zoom control; leaves close and minimize visible.
    func compactWindowChrome(hidesZoomButton: Bool = true) -> some View {
        background(CompactWindowChrome(hidesZoomButton: hidesZoomButton))
    }
}
