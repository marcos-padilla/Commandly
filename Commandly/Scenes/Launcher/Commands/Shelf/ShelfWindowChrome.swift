import AppKit
import DesignSystem
import SwiftUI

/// Configures Shelf as a small floating, draggable board without traffic lights.
struct ShelfWindowConfigurator: NSViewRepresentable {
    var preferredCorner: ShelfPreferredCorner
    var interaction: ShelfBoardInteractionState
    var onEscape: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            preferredCorner: preferredCorner,
            interaction: interaction,
            onEscape: onEscape
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.preferredCorner = preferredCorner
        context.coordinator.interaction = interaction
        context.coordinator.onEscape = onEscape
        scheduleConfigure(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.preferredCorner = preferredCorner
        context.coordinator.interaction = interaction
        context.coordinator.onEscape = onEscape
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

    @MainActor
    static func applyChrome(
        to window: NSWindow,
        preferredCorner: ShelfPreferredCorner,
        placeIfNeeded: inout Bool
    ) {
        window.identifier = CommandlyWindowIdentifier.shelf
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

        applyRoundedContentMask(to: window)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        LauncherKeyableWindowSupport.installIfNeeded(for: window)

        if placeIfNeeded {
            place(window, in: preferredCorner)
            placeIfNeeded = false
        }
    }

    @MainActor
    static func applyRoundedContentMask(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = LayoutConstants.shelfCornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        window.invalidateShadow()
    }

    @MainActor
    static func place(_ window: NSWindow, in corner: ShelfPreferredCorner) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let size = NSSize(
            width: LayoutConstants.shelfBoardSize,
            height: LayoutConstants.shelfBoardSize
        )
        let margin = LayoutConstants.shelfScreenMargin
        let visible = screen.visibleFrame
        let origin: NSPoint
        switch corner {
        case .bottomRight:
            origin = NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.minY + margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.minY + margin
            )
        case .topRight:
            origin = NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin
            )
        case .topLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.maxY - size.height - margin
            )
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    final class Coordinator: @unchecked Sendable {
        var preferredCorner: ShelfPreferredCorner
        var interaction: ShelfBoardInteractionState
        var onEscape: () -> Bool
        private weak var window: NSWindow?
        private var escapeKeyMonitor: Any?
        private var mouseDownMonitor: Any?
        private var mouseDraggedMonitor: Any?
        private var mouseUpMonitor: Any?
        private var becomeKeyObserver: NSObjectProtocol?
        private var resignKeyObserver: NSObjectProtocol?
        private var becomeActiveObserver: NSObjectProtocol?
        private var resignActiveObserver: NSObjectProtocol?
        private var needsPlacement = true
        private var isTrackingDrag = false

        init(
            preferredCorner: ShelfPreferredCorner,
            interaction: ShelfBoardInteractionState,
            onEscape: @escaping () -> Bool
        ) {
            self.preferredCorner = preferredCorner
            self.interaction = interaction
            self.onEscape = onEscape
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }
            self.window = window
            ShelfWindowConfigurator.applyChrome(
                to: window,
                preferredCorner: preferredCorner,
                placeIfNeeded: &needsPlacement
            )
            refreshFocusState()
            installMonitorsIfNeeded()
        }

        @MainActor
        func tearDown() {
            removeMonitors()
            window = nil
            needsPlacement = true
            isTrackingDrag = false
        }

        @MainActor
        private func installMonitorsIfNeeded() {
            guard escapeKeyMonitor == nil else { return }

            escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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

            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                DispatchQueue.main.async {
                    self?.handleMouseDownOnMain(event)
                }
                return event
            }

            mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                DispatchQueue.main.async {
                    self?.handleMouseDraggedOnMain(event)
                }
                return event
            }

            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                DispatchQueue.main.async {
                    self?.endDragTracking()
                }
                return event
            }

            becomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshFocusState()
                }
            }

            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshFocusState()
                    self?.endDragTracking()
                }
            }

            becomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshFocusState()
                }
            }

            resignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshFocusState()
                    self?.endDragTracking()
                }
            }
        }

        @MainActor
        private func handleEscapeOnMain() -> Bool {
            guard let window, window.isKeyWindow, window.isVisible else {
                return false
            }
            return onEscape()
        }

        @MainActor
        private func handleMouseDownOnMain(_ event: NSEvent) {
            guard let window, event.window == window else {
                isTrackingDrag = false
                return
            }
            isTrackingDrag = true
        }

        @MainActor
        private func handleMouseDraggedOnMain(_ event: NSEvent) {
            guard isTrackingDrag else { return }
            guard let window else { return }
            // Background-driven window moves may report nil or another event window.
            if let eventWindow = event.window, eventWindow != window {
                return
            }
            if interaction.isDragging == false {
                interaction.isDragging = true
            }
        }

        @MainActor
        private func endDragTracking() {
            isTrackingDrag = false
            if interaction.isDragging {
                interaction.isDragging = false
            }
        }

        @MainActor
        private func refreshFocusState() {
            let isFocused: Bool
            if let window {
                isFocused = window.isKeyWindow && NSApp.isActive
            } else {
                isFocused = false
            }
            if interaction.isFocused != isFocused {
                interaction.isFocused = isFocused
            }
        }

        @MainActor
        private func removeMonitors() {
            if let escapeKeyMonitor {
                NSEvent.removeMonitor(escapeKeyMonitor)
                self.escapeKeyMonitor = nil
            }
            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
                self.mouseDownMonitor = nil
            }
            if let mouseDraggedMonitor {
                NSEvent.removeMonitor(mouseDraggedMonitor)
                self.mouseDraggedMonitor = nil
            }
            if let mouseUpMonitor {
                NSEvent.removeMonitor(mouseUpMonitor)
                self.mouseUpMonitor = nil
            }
            if let becomeKeyObserver {
                NotificationCenter.default.removeObserver(becomeKeyObserver)
                self.becomeKeyObserver = nil
            }
            if let resignKeyObserver {
                NotificationCenter.default.removeObserver(resignKeyObserver)
                self.resignKeyObserver = nil
            }
            if let becomeActiveObserver {
                NotificationCenter.default.removeObserver(becomeActiveObserver)
                self.becomeActiveObserver = nil
            }
            if let resignActiveObserver {
                NotificationCenter.default.removeObserver(resignActiveObserver)
                self.resignActiveObserver = nil
            }
        }
    }
}

extension View {
    func shelfWindowChrome(
        preferredCorner: ShelfPreferredCorner,
        interaction: ShelfBoardInteractionState,
        onEscape: @escaping () -> Bool
    ) -> some View {
        background(
            ShelfWindowConfigurator(
                preferredCorner: preferredCorner,
                interaction: interaction,
                onEscape: onEscape
            )
        )
    }
}
