import AppKit
import SwiftUI
import DesignSystem
import ObjectiveC

/// Configures the launcher as a floating, draggable, vibrancy panel without traffic lights.
struct LauncherWindowConfigurator: NSViewRepresentable {
    var onRequestClose: () -> Void
    /// Called for Escape while the launcher window is key. Return `true` to consume the event.
    var onEscape: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequestClose: onRequestClose, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.onRequestClose = onRequestClose
        context.coordinator.onEscape = onEscape
        scheduleConfigure(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onRequestClose = onRequestClose
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

    /// Applies borderless floating chrome while keeping the window able to become key.
    ///
    /// Stock `.borderless` windows return `false` from `canBecomeKey`, so reopen after
    /// hide cannot accept typing. Patch `canBecomeKey` / `canBecomeMain` for launcher
    /// windows (by identifier) without titled chrome or `object_setClass` isa swaps.
    @MainActor
    static func applyChrome(to window: NSWindow, centerIfNeeded: inout Bool) {
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
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
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
        center(window)
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
    private static func center(_ window: NSWindow) {
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

    /// AppKit event monitors and notification callbacks are nonisolated / Sendable.
    /// Mutable state is only read or written on the main queue.
    final class Coordinator: @unchecked Sendable {
        var onRequestClose: () -> Void
        var onEscape: () -> Bool
        private weak var window: NSWindow?
        private var localMouseMonitor: Any?
        private var globalMouseMonitor: Any?
        private var escapeKeyMonitor: Any?
        private var resignKeyObserver: NSObjectProtocol?
        private var resignActiveObserver: NSObjectProtocol?
        private var needsCentering = true
        private var isClosing = false

        init(onRequestClose: @escaping () -> Void, onEscape: @escaping () -> Bool) {
            self.onRequestClose = onRequestClose
            self.onEscape = onEscape
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else { return }
            self.window = window
            isClosing = false
            LauncherWindowConfigurator.applyChrome(to: window, centerIfNeeded: &needsCentering)
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
            needsCentering = true
            isClosing = false
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

            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // Defer so we do not dismiss mid resign-key bookkeeping.
                DispatchQueue.main.async {
                    self?.requestCloseAfterFocusLoss()
                }
            }

            // Accessory (LSUIElement) apps often keep a floating window key when the
            // user clicks another app; app deactivation is the reliable dismiss signal.
            resignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestCloseAfterFocusLoss()
                }
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
            guard isClosing == false else { return }
            guard let window, window.isVisible else { return }
            isClosing = true
            onRequestClose()
        }

        /// Dismiss after resign-key / resign-active, ignoring stale callbacks if we
        /// were already re-activated (e.g. hotkey reopen before the deferred close runs).
        @MainActor
        private func requestCloseAfterFocusLoss() {
            guard isClosing == false else { return }
            guard let window, window.isVisible else { return }
            if NSApp.isActive, window.isKeyWindow {
                return
            }
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
            if let resignKeyObserver {
                NotificationCenter.default.removeObserver(resignKeyObserver)
                self.resignKeyObserver = nil
            }
            if let resignActiveObserver {
                NotificationCenter.default.removeObserver(resignActiveObserver)
                self.resignActiveObserver = nil
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
               window.identifier == CommandlyWindowIdentifier.launcher {
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
    func launcherWindowChrome(
        onRequestClose: @escaping () -> Void,
        onEscape: @escaping () -> Bool
    ) -> some View {
        background(
            LauncherWindowConfigurator(
                onRequestClose: onRequestClose,
                onEscape: onEscape
            )
        )
    }
}
