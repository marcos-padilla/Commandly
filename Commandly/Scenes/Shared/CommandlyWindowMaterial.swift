import AppKit
import SwiftUI

/// Behind-window blur shared by Commandly's standard utility windows.
struct CommandlyWindowVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
        nsView.isEmphasized = false
    }
}

private struct CommandlyWindowMaterialConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAttached(nsView, coordinator: context.coordinator)
    }

    private func configureWhenAttached(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.configure(view.window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        func configure(_ window: NSWindow?) {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
    }
}

extension View {
    /// Makes a standard Commandly window transparent so its native material can sample the desktop.
    func commandlyWindowMaterial() -> some View {
        background(CommandlyWindowMaterialConfigurator())
    }
}
