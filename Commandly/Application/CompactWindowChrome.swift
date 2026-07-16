import AppKit
import SwiftUI

/// Integrates content into a transparent native titlebar while retaining standard controls.
struct CompactWindowChrome: NSViewRepresentable {
    var hidesZoomButton: Bool = true
    var accessibilityLabel: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentProbeView {
        let view = WindowAttachmentProbeView(frame: .zero)
        view.isHidden = true
        installAttachmentCallback(on: view, coordinator: context.coordinator)
        view.attachIfPossible()
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentProbeView, context: Context) {
        installAttachmentCallback(on: nsView, coordinator: context.coordinator)
        nsView.attachIfPossible()
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentProbeView,
        coordinator: Coordinator
    ) {
        nsView.onWindowAttached = nil
    }

    private func installAttachmentCallback(
        on view: WindowAttachmentProbeView,
        coordinator: Coordinator
    ) {
        view.onWindowAttached = { [weak coordinator] window in
            coordinator?.configure(
                window,
                hidesZoomButton: hidesZoomButton,
                accessibilityLabel: accessibilityLabel
            )
        }
    }

    @MainActor
    final class Coordinator {
        func configure(
            _ window: NSWindow?,
            hidesZoomButton: Bool,
            accessibilityLabel: String? = nil
        ) {
            guard let window else { return }

            if let accessibilityLabel {
                window.setAccessibilityLabel(accessibilityLabel)
            }
            if window.title.isEmpty == false {
                window.title = ""
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if window.titlebarAppearsTransparent == false {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.styleMask.contains(.fullSizeContentView) == false {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.isMovableByWindowBackground == false {
                window.isMovableByWindowBackground = true
            }
            // Commandly supplies integrated controls inside its own content. Removing
            // SwiftUI's automatic toolbar also prevents its sidebar toggle from moving
            // over the traffic lights when a split-view sidebar is collapsed.
            if window.toolbar != nil {
                window.toolbar = nil
            }

            window.styleMask.insert([.closable, .miniaturizable])
            if hidesZoomButton == false {
                window.styleMask.insert(.resizable)
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
    /// Integrates content with the titlebar. Fixed windows hide zoom; resizable utility
    /// windows keep standard sizing controls while Commandly owns navigation chrome.
    func compactWindowChrome(
        hidesZoomButton: Bool = true,
        accessibilityLabel: String? = nil
    ) -> some View {
        background(
            CompactWindowChrome(
                hidesZoomButton: hidesZoomButton,
                accessibilityLabel: accessibilityLabel
            )
        )
    }
}
