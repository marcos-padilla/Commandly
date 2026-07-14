import AppKit
import DesignSystem
import SwiftUI

/// Configures Shelf as a small floating, draggable board without traffic lights.
struct ShelfWindowConfigurator: NSViewRepresentable {
    var preferredCorner: ShelfPreferredCorner
    var presentationRequest: ShelfPresentationRequest
    var interaction: ShelfBoardInteractionState
    var onEscape: () -> Bool
    var onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            preferredCorner: preferredCorner,
            presentationRequest: presentationRequest,
            interaction: interaction,
            onEscape: onEscape,
            onKeyDown: onKeyDown
        )
    }

    func makeNSView(context: Context) -> WindowAttachmentProbeView {
        let view = WindowAttachmentProbeView(frame: .zero)
        view.isHidden = true
        context.coordinator.preferredCorner = preferredCorner
        context.coordinator.updatePresentationRequest(presentationRequest)
        context.coordinator.interaction = interaction
        context.coordinator.onEscape = onEscape
        context.coordinator.onKeyDown = onKeyDown
        installAttachmentCallback(on: view, coordinator: context.coordinator)
        view.attachIfPossible()
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentProbeView, context: Context) {
        context.coordinator.preferredCorner = preferredCorner
        context.coordinator.updatePresentationRequest(presentationRequest)
        context.coordinator.interaction = interaction
        context.coordinator.onEscape = onEscape
        context.coordinator.onKeyDown = onKeyDown
        installAttachmentCallback(on: nsView, coordinator: context.coordinator)
        nsView.attachIfPossible()
    }

    static func dismantleNSView(_ nsView: WindowAttachmentProbeView, coordinator: Coordinator) {
        nsView.onWindowAttached = nil
        coordinator.tearDown()
    }

    private func installAttachmentCallback(
        on view: WindowAttachmentProbeView,
        coordinator: Coordinator
    ) {
        view.onWindowAttached = { [weak coordinator] window in
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    static func applyChrome(
        to window: NSWindow,
        preferredCorner: ShelfPreferredCorner,
        screenTarget: WindowPresentationTarget?,
        placeIfNeeded: inout Bool
    ) {
        window.identifier = CommandlyWindowIdentifier.shelf
        window.styleMask = [.borderless, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        ActiveSpaceWindowPresenter.applyOverlayBehavior(to: window)
        window.animationBehavior = .utilityWindow
        window.toolbar = nil

        applyRoundedContentMask(to: window)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        LauncherKeyableWindowSupport.installIfNeeded(for: window)

        if placeIfNeeded {
            place(window, in: preferredCorner, screenTarget: screenTarget)
            placeIfNeeded = false
        }
    }

    /// Clips the private SwiftUI hosting and vibrancy layers to Shelf's visible shape.
    ///
    /// A SwiftUI `clipShape` alone does not mask every AppKit-owned layer. Keeping the host layer
    /// rounded prevents rectangular pixels from appearing outside Shelf's continuous corners.
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
    static func place(
        _ window: NSWindow,
        in corner: ShelfPreferredCorner,
        screenTarget: WindowPresentationTarget? = nil
    ) {
        let size = NSSize(
            width: LayoutConstants.shelfBoardSize,
            height: LayoutConstants.shelfBoardSize
        )
        let margin = LayoutConstants.shelfScreenMargin
        guard let visible = screenTarget?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame else {
            return
        }
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

    /// AppKit owns these monitor callbacks. Every mutation is explicitly marshalled to MainActor.
    final class Coordinator: @unchecked Sendable {
        var preferredCorner: ShelfPreferredCorner
        private(set) var presentationRequest: ShelfPresentationRequest
        var interaction: ShelfBoardInteractionState
        var onEscape: () -> Bool
        var onKeyDown: (NSEvent) -> Bool
        private weak var window: NSWindow?
        private var escapeKeyMonitor: Any?
        private var becomeKeyObserver: NSObjectProtocol?
        private var resignKeyObserver: NSObjectProtocol?
        private var becomeActiveObserver: NSObjectProtocol?
        private var resignActiveObserver: NSObjectProtocol?
        private var needsPlacement = true
        private var needsPresentation = true
        private var isAttaching = false
        private var attachingGeneration: UInt64?
        private weak var deferredWindow: NSWindow?

        init(
            preferredCorner: ShelfPreferredCorner,
            presentationRequest: ShelfPresentationRequest,
            interaction: ShelfBoardInteractionState,
            onEscape: @escaping () -> Bool,
            onKeyDown: @escaping (NSEvent) -> Bool
        ) {
            self.preferredCorner = preferredCorner
            self.presentationRequest = presentationRequest
            self.interaction = interaction
            self.onEscape = onEscape
            self.onKeyDown = onKeyDown
        }

        @MainActor
        func updatePresentationRequest(_ request: ShelfPresentationRequest) {
            if request.generation != presentationRequest.generation {
                needsPlacement = true
                needsPresentation = true
            }
            presentationRequest = request
            if isAttaching, attachingGeneration != request.generation {
                deferredWindow = window
            }
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }
            if isAttaching {
                if attachingGeneration != presentationRequest.generation
                    || self.window !== window {
                    deferredWindow = window
                }
                return
            }

            isAttaching = true
            var nextWindow: NSWindow? = window

            while let currentWindow = nextWindow {
                deferredWindow = nil
                let request = presentationRequest
                attachingGeneration = request.generation
                self.window = currentWindow

                var shouldPlace = needsPlacement
                let shouldPresent = needsPresentation
                needsPlacement = false
                needsPresentation = false

                ShelfWindowConfigurator.applyChrome(
                    to: currentWindow,
                    preferredCorner: preferredCorner,
                    screenTarget: request.screenTarget,
                    placeIfNeeded: &shouldPlace
                )
                // AppKit can synchronously reattach the probe while changing style/frame.
                // Keep any newer request flags and process that generation in a fresh pass.
                needsPlacement = needsPlacement || shouldPlace
                installMonitorsIfNeeded()
                if shouldPresent {
                    if presentationRequest.generation == request.generation {
                        ActiveSpaceWindowPresenter.present(currentWindow)
                    } else {
                        needsPresentation = true
                    }
                }
                refreshFocusState()

                if presentationRequest.generation != request.generation,
                   deferredWindow == nil {
                    deferredWindow = currentWindow
                }
                nextWindow = deferredWindow
            }

            attachingGeneration = nil
            isAttaching = false
        }

        @MainActor
        func tearDown() {
            removeMonitors()
            window = nil
            deferredWindow = nil
            attachingGeneration = nil
            isAttaching = false
            needsPlacement = true
            needsPresentation = true
        }

        @MainActor
        private func installMonitorsIfNeeded() {
            guard escapeKeyMonitor == nil else { return }

            escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                var consumed = false
                if Thread.isMainThread {
                    consumed = self.handleKeyDownOnMain(event)
                } else {
                    DispatchQueue.main.sync {
                        consumed = self.handleKeyDownOnMain(event)
                    }
                }
                return consumed ? nil : event
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
                }
            }
        }

        @MainActor
        private func handleKeyDownOnMain(_ event: NSEvent) -> Bool {
            guard let window, window.isKeyWindow, window.isVisible else {
                return false
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53, modifiers.isEmpty {
                return onEscape()
            }
            return onKeyDown(event)
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
        presentationRequest: ShelfPresentationRequest,
        interaction: ShelfBoardInteractionState,
        onEscape: @escaping () -> Bool,
        onKeyDown: @escaping (NSEvent) -> Bool = { _ in false }
    ) -> some View {
        background(
            ShelfWindowConfigurator(
                preferredCorner: preferredCorner,
                presentationRequest: presentationRequest,
                interaction: interaction,
                onEscape: onEscape,
                onKeyDown: onKeyDown
            )
        )
    }
}
