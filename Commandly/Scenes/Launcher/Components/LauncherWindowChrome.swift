import AppKit
import SwiftUI
import DesignSystem
import ObjectiveC

/// Configures the launcher as a floating, draggable, vibrancy panel without traffic lights.
struct LauncherWindowConfigurator: NSViewRepresentable {
    var presentationRequest: WindowPresentationRequest
    var onRequestClose: () -> Void
    /// Called for Escape while the launcher window is key. Return `true` to consume the event.
    var onEscape: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            presentationRequest: presentationRequest,
            onRequestClose: onRequestClose,
            onEscape: onEscape
        )
    }

    func makeNSView(context: Context) -> WindowAttachmentProbeView {
        let view = WindowAttachmentProbeView(frame: .zero)
        view.isHidden = true
        context.coordinator.updatePresentationRequest(presentationRequest)
        context.coordinator.onRequestClose = onRequestClose
        context.coordinator.onEscape = onEscape
        installAttachmentCallback(on: view, coordinator: context.coordinator)
        view.attachIfPossible()
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentProbeView, context: Context) {
        context.coordinator.updatePresentationRequest(presentationRequest)
        context.coordinator.onRequestClose = onRequestClose
        context.coordinator.onEscape = onEscape
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

    /// Applies borderless floating chrome while keeping the window able to become key.
    ///
    /// Stock `.borderless` windows return `false` from `canBecomeKey`, so reopen after
    /// hide cannot accept typing. Patch `canBecomeKey` / `canBecomeMain` for launcher
    /// windows (by identifier) without titled chrome or `object_setClass` isa swaps.
    @MainActor
    static func applyChrome(
        to window: NSWindow,
        screenTarget: WindowPresentationTarget?,
        centerIfNeeded: inout Bool
    ) {
        window.identifier = CommandlyWindowIdentifier.launcher
        // Borderless removes leftover title-bar / safe-area chrome that titled+hidden
        // titlebar still reserves (empty bottom strip in the launcher panel).
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
        ActiveSpaceWindowPresenter.applyOverlayBehavior(to: window)
        window.animationBehavior = .utilityWindow
        window.toolbar = nil

        applyRoundedContentMask(to: window)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        ensureKeyable(window)

        if centerIfNeeded == false {
            return
        }
        center(window, screenTarget: screenTarget)
        centerIfNeeded = false
    }

    /// Clips the AppKit hosting surface, not only the SwiftUI content.
    ///
    /// SwiftUI shape clips do not necessarily mask the private hosting and vibrancy
    /// layers installed by `Window`. Without this layer mask, those layers can leave
    /// dark rectangular pixels visible behind the launcher's rounded corners.
    @MainActor
    static func applyRoundedContentMask(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = CornerRadius.xl.rawValue
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        window.invalidateShadow()
    }

    /// Makes a borderless launcher window keyable via identifier-aware method patches.
    ///
    /// Avoids `object_setClass` (unsafe when SwiftUI owns a private `NSWindow` subclass and
    /// crashes the test host on teardown). Patches the live class hierarchy once so only
    /// windows identified as the launcher return `true` from `canBecomeKey` / `canBecomeMain`.
    @MainActor
    static func ensureKeyable(_ window: NSWindow) {
        window.identifier = CommandlyWindowIdentifier.launcher
        LauncherKeyableWindowSupport.installIfNeeded(for: window)
    }

    @MainActor
    static func center(
        _ window: NSWindow,
        screenTarget: WindowPresentationTarget? = nil
    ) {
        guard let visibleFrame = screenTarget?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame else {
            return
        }
        let size = NSSize(
            width: LayoutConstants.launcherIdealWidth,
            height: LayoutConstants.launcherIdealHeight
        )
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// AppKit event monitors and notification callbacks are nonisolated / Sendable.
    /// Mutable state is only read or written on the main queue.
    final class Coordinator: @unchecked Sendable {
        private(set) var presentationRequest: WindowPresentationRequest
        var onRequestClose: () -> Void
        var onEscape: () -> Bool
        private weak var window: NSWindow?
        private var localMouseMonitor: Any?
        private var globalMouseMonitor: Any?
        private var escapeKeyMonitor: Any?
        private var needsCentering = true
        private var needsPresentation = true
        private var isClosing = false
        private var isAttaching = false
        private var attachingGeneration: UInt64?
        private weak var deferredWindow: NSWindow?

        init(
            presentationRequest: WindowPresentationRequest,
            onRequestClose: @escaping () -> Void,
            onEscape: @escaping () -> Bool
        ) {
            self.presentationRequest = presentationRequest
            self.onRequestClose = onRequestClose
            self.onEscape = onEscape
        }

        @MainActor
        func updatePresentationRequest(_ request: WindowPresentationRequest) {
            if request.generation != presentationRequest.generation {
                needsCentering = true
                needsPresentation = true
                isClosing = false
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

                var shouldCenter = needsCentering
                let shouldPresent = needsPresentation
                needsCentering = false
                needsPresentation = false

                LauncherWindowConfigurator.applyChrome(
                    to: currentWindow,
                    screenTarget: request.screenTarget,
                    centerIfNeeded: &shouldCenter
                )
                // Preserve a newer request that arrived synchronously while AppKit changed
                // the style mask or frame. The nested attachment is intentionally ignored for
                // the same generation, but a newer generation receives another pass below.
                needsCentering = needsCentering || shouldCenter
                installMonitorsIfNeeded()
                if shouldPresent {
                    if presentationRequest.generation == request.generation {
                        ActiveSpaceWindowPresenter.present(currentWindow)
                    } else {
                        needsPresentation = true
                    }
                }

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
            needsCentering = true
            needsPresentation = true
            isClosing = false
        }

        @MainActor
        private func installMonitorsIfNeeded() {
            guard localMouseMonitor == nil else { return }

            let mouseDownEvents: NSEvent.EventTypeMask = [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
            ]
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: mouseDownEvents
            ) { [weak self] event in
                // Local monitors run on the main thread for clicks in Commandly-owned windows.
                self?.handleMouseDownOnMain(event)
                return event
            }

            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: mouseDownEvents
            ) { [weak self] _ in
                // A global monitor reports clicks delivered to other applications. Avoid moving
                // the NSEvent across isolation and carry only its screen-space location.
                let screenPoint = NSEvent.mouseLocation
                DispatchQueue.main.async {
                    self?.handleOutsideClick(at: screenPoint)
                }
            }

            // TextField's field editor swallows Escape before SwiftUI `.onKeyPress` /
            // `.onExitCommand` reliably see it. Intercept at AppKit so Esc can leave
            // applications and hide the launcher.
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
        }

        @MainActor
        private func handleEscapeOnMain() -> Bool {
            guard let window, window.isKeyWindow, window.isVisible, isClosing == false else {
                return false
            }
            return onEscape()
        }

        @MainActor
        private func handleMouseDownOnMain(_ event: NSEvent) {
            guard let window else { return }
            if event.window == window {
                return
            }

            if let eventWindow = event.window {
                handleOutsideClick(
                    at: eventWindow.convertPoint(toScreen: event.locationInWindow)
                )
                return
            }

            handleOutsideClick(at: NSEvent.mouseLocation)
        }

        /// Handles the screen-space portion of local/global mouse monitoring.
        ///
        /// Internal visibility keeps this deterministic in AppKit regression tests without
        /// synthesizing system-wide input or granting an input-monitoring permission.
        @MainActor
        func handleOutsideClick(at screenPoint: NSPoint) {
            guard let window, window.frame.contains(screenPoint) == false else { return }
            requestCloseOnMain()
        }

        @MainActor
        private func requestCloseOnMain() {
            guard isClosing == false else { return }
            guard let window, window.isVisible else { return }
            isClosing = true
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
            if let escapeKeyMonitor {
                NSEvent.removeMonitor(escapeKeyMonitor)
                self.escapeKeyMonitor = nil
            }
        }
    }
}

/// Patches `canBecomeKey` / `canBecomeMain` so borderless launcher windows can accept typing.
///
/// Uses identifier-gated IMP replacements on the window’s live class (and `NSWindow` as a
/// fallback). Does not change an instance’s `isa`, which avoids teardown crashes seen with
/// `object_setClass` against SwiftUI / AppKit window subclasses.
enum LauncherKeyableWindowSupport {
    private static let lock = NSLock()
    private static var patchedClassNames = Set<String>()

    @MainActor
    static func installIfNeeded(for window: NSWindow) {
        let runtimeClass: AnyClass = object_getClass(window) ?? NSWindow.self
        patch(class: runtimeClass)
        // Also patch `NSWindow` so inherited lookups and plain test windows are covered.
        patch(class: NSWindow.self)
    }

    private static func patch(class cls: AnyClass) {
        lock.lock()
        defer { lock.unlock() }

        let name = NSStringFromClass(cls)
        guard patchedClassNames.insert(name).inserted else { return }

        patchGetter(
            on: cls,
            selector: #selector(getter: NSWindow.canBecomeKey)
        )
        patchGetter(
            on: cls,
            selector: #selector(getter: NSWindow.canBecomeMain)
        )
    }

    private static func patchGetter(on cls: AnyClass, selector: Selector) {
        typealias GetterFn = @convention(c) (AnyObject, Selector) -> Bool

        let existingMethod = class_getInstanceMethod(cls, selector)
        let originalIMP: IMP?
        if let existingMethod {
            originalIMP = method_getImplementation(existingMethod)
        } else {
            originalIMP = nil
        }

        let block: @convention(block) (AnyObject) -> Bool = { object in
            if let window = object as? NSWindow,
               window.identifier == CommandlyWindowIdentifier.launcher
                || window.identifier == CommandlyWindowIdentifier.shelf {
                return true
            }
            if let originalIMP {
                return unsafeBitCast(originalIMP, to: GetterFn.self)(object, selector)
            }
            return false
        }
        let newIMP = imp_implementationWithBlock(block)
        let encoding = "B@:"

        // Prefer adding an override on this class when the getter is only inherited.
        if class_addMethod(cls, selector, newIMP, encoding) {
            return
        }
        class_replaceMethod(cls, selector, newIMP, encoding)
    }
}

struct LauncherVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .followsWindowActiveState
        nsView.isEmphasized = false
    }
}

extension View {
    func launcherWindowChrome(
        presentationRequest: WindowPresentationRequest,
        onRequestClose: @escaping () -> Void,
        onEscape: @escaping () -> Bool
    ) -> some View {
        background(
            LauncherWindowConfigurator(
                presentationRequest: presentationRequest,
                onRequestClose: onRequestClose,
                onEscape: onEscape
            )
        )
    }
}
