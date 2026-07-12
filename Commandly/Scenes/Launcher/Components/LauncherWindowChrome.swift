import AppKit
import SwiftUI
import DesignSystem

/// Configures the launcher as a floating, draggable, vibrancy panel without traffic lights.
struct LauncherWindowConfigurator: NSViewRepresentable {
    var onRequestClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequestClose: onRequestClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.onRequestClose = onRequestClose
        scheduleConfigure(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onRequestClose = onRequestClose
        scheduleConfigure(for: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    private func scheduleConfigure(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.attach(to: view.window)
        }
    }

    /// AppKit event monitors and notification callbacks are nonisolated / Sendable.
    /// Mutable state is only read or written on the main queue.
    final class Coordinator: @unchecked Sendable {
        var onRequestClose: () -> Void
        private weak var window: NSWindow?
        private var localMouseMonitor: Any?
        private var globalMouseMonitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var hasCentered = false

        init(onRequestClose: @escaping () -> Void) {
            self.onRequestClose = onRequestClose
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }
            self.window = window
            applyChrome(to: window)
            installMonitorsIfNeeded()
            // Do not raise or activate here. `updateNSView` calls `attach` on ordinary
            // SwiftUI refreshes — including `@Observable` clipboard history updates —
            // and raising would steal focus on every system-wide copy. Explicit open
            // paths (`AppRuntime.showLauncher` / `LauncherPresentationBridge`) own
            // activation and ordering front.
        }

        @MainActor
        func tearDown() {
            removeMonitors()
            window = nil
            hasCentered = false
        }

        @MainActor
        private func applyChrome(to window: NSWindow) {
            window.identifier = CommandlyWindowIdentifier.launcher
            // Borderless removes the leftover title-bar strip above the search field.
            window.styleMask = [.borderless, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
            window.animationBehavior = .utilityWindow
            window.toolbar = nil

            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            if hasCentered == false {
                center(window)
                hasCentered = true
            }
        }

        @MainActor
        private func center(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let size = NSSize(
                width: LayoutConstants.launcherIdealWidth,
                height: LayoutConstants.launcherIdealHeight
            )
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        @MainActor
        private func installMonitorsIfNeeded() {
            guard localMouseMonitor == nil else { return }

            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                // Local monitors run on the main thread for the active app.
                self?.handleMouseDownOnMain(event)
                return event
            }

            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // Avoid capturing NSEvent across isolation; only pass a screen point.
                let screenPoint = NSEvent.mouseLocation
                DispatchQueue.main.async {
                    self?.handleOutsideClick(at: screenPoint)
                }
            }

            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // Clicking another app/window should dismiss the launcher.
                self?.requestCloseOnMain()
            }
        }

        @MainActor
        private func handleMouseDownOnMain(_ event: NSEvent) {
            guard let window else { return }
            if event.window == window {
                return
            }

            if let eventWindow = event.window {
                let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
                handleOutsideClick(at: screenPoint)
                return
            }

            handleOutsideClick(at: NSEvent.mouseLocation)
        }

        @MainActor
        private func handleOutsideClick(at screenPoint: NSPoint) {
            guard let window else { return }
            if window.frame.contains(screenPoint) == false {
                requestCloseOnMain()
            }
        }

        @MainActor
        private func requestCloseOnMain() {
            onRequestClose()
        }

        @MainActor
        private func removeMonitors() {
            if let localMouseMonitor {
                NSEvent.removeMonitor(localMouseMonitor)
                self.localMouseMonitor = nil
            }
            if let globalMouseMonitor {
                NSEvent.removeMonitor(globalMouseMonitor)
                self.globalMouseMonitor = nil
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
        }
    }
}

struct LauncherVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

extension View {
    func launcherWindowChrome(onRequestClose: @escaping () -> Void) -> some View {
        background(LauncherWindowConfigurator(onRequestClose: onRequestClose))
    }
}
