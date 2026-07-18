import AppKit
import SwiftUI

@MainActor
protocol CommandWheelFocusRestoring: AnyObject {
    func restoreFocus(to processIdentifier: Int32)
}

@MainActor
final class NSRunningApplicationCommandWheelFocusRestorer: CommandWheelFocusRestoring {
    func restoreFocus(to processIdentifier: Int32) {
        guard processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.isTerminated == false else {
            return
        }
        application.activate(options: [])
    }
}

@MainActor
protocol CommandWheelApplicationActivating: AnyObject {
    func activateForKeyboardInput()
}

@MainActor
final class NSApplicationCommandWheelActivator: CommandWheelApplicationActivating {
    func activateForKeyboardInput() {
        NSApp.activate()
    }
}

/// Narrow panel boundary consumed by the coordinator and replaceable in deterministic tests.
@MainActor
protocol CommandWheelWindowPresenting: AnyObject {
    var isPresented: Bool { get }
    var panelFrame: CGRect? { get }

    func setLifecycleHandlers(
        displayConfigurationChanged: @escaping () -> Void,
        activeSpaceChanged: @escaping () -> Void,
        frontmostApplicationChanged: @escaping (Int32?) -> Void,
        applicationWillTerminate: @escaping () -> Void
    )

    func beginSessionObservation()
    func endSessionObservation()

    func present(
        model: CommandWheelPresentationModel,
        position: CommandWheelPosition,
        activationBehavior: CommandWheelActivationBehavior,
        frontmostProcessIdentifier: Int32?,
        onActivateSlot: @escaping (Int) -> Void,
        onActivateCenter: @escaping () -> Void,
        onKeyboardCommand: @escaping (CommandWheelKeyboardCommand) -> Bool
    )

    func dismiss()
    func tearDown()
}

/// Creates, hosts, and tears down one transparent AppKit panel per visible wheel session.
///
/// The panel never enters normal window cycling or the Window menu. Hold mode orders it without
/// activating Commandly; toggle mode takes only the temporary key focus required for configured
/// keyboard navigation and restores the previously frontmost process when dismissed.
@MainActor
final class CommandWheelWindowController: CommandWheelWindowPresenting {
    static let collectionBehavior = ActiveSpaceWindowPresenter.overlayCollectionBehavior
        .union(.fullScreenAuxiliary)

    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let focusRestorer: any CommandWheelFocusRestoring
    private let applicationActivator: any CommandWheelApplicationActivating

    private var panel: CommandWheelPanel?
    private var dismissingPanel: CommandWheelPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var presentedModel: CommandWheelPresentationModel?
    private var observerTokens = [NSObjectProtocol]()
    private var focusRestorationProcessIdentifier: Int32?
    private var didTakeKeyFocus = false
    private var didTearDown = false

    private var displayConfigurationChanged: (() -> Void)?
    private var activeSpaceChanged: (() -> Void)?
    private var frontmostApplicationChanged: ((Int32?) -> Void)?
    private var applicationWillTerminate: (() -> Void)?

    var isPresented: Bool {
        panel?.isVisible == true
    }

    var panelFrame: CGRect? {
        panel?.frame
    }

    /// Read-only test seam for verifying native window flags without widening mutation access.
    var currentPanel: CommandWheelPanel? { panel }

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        focusRestorer: any CommandWheelFocusRestoring =
            NSRunningApplicationCommandWheelFocusRestorer(),
        applicationActivator: any CommandWheelApplicationActivating =
            NSApplicationCommandWheelActivator()
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.focusRestorer = focusRestorer
        self.applicationActivator = applicationActivator
    }

    func setLifecycleHandlers(
        displayConfigurationChanged: @escaping () -> Void,
        activeSpaceChanged: @escaping () -> Void,
        frontmostApplicationChanged: @escaping (Int32?) -> Void,
        applicationWillTerminate: @escaping () -> Void
    ) {
        self.displayConfigurationChanged = displayConfigurationChanged
        self.activeSpaceChanged = activeSpaceChanged
        self.frontmostApplicationChanged = frontmostApplicationChanged
        self.applicationWillTerminate = applicationWillTerminate
    }

    func beginSessionObservation() {
        guard didTearDown == false else { return }
        installObservers()
    }

    func endSessionObservation() {
        removeObservers()
    }

    func present(
        model: CommandWheelPresentationModel,
        position: CommandWheelPosition,
        activationBehavior: CommandWheelActivationBehavior,
        frontmostProcessIdentifier: Int32?,
        onActivateSlot: @escaping (Int) -> Void,
        onActivateCenter: @escaping () -> Void,
        onKeyboardCommand: @escaping (CommandWheelKeyboardCommand) -> Bool
    ) {
        finishDismissingPanel()
        dismissImmediately()
        if didTearDown {
            didTearDown = false
        }
        beginSessionObservation()

        let panel = makePanel(frame: position.contentFrame)
        let canUseKeyboard = activationBehavior == .toggle
            && model.interaction.allowsKeyboardSelection
        panel.allowsKeyFocus = canUseKeyboard
        panel.ignoresMouseEvents = activationBehavior == .holdAndRelease
        panel.onKeyboardCommand = onKeyboardCommand

        let rootView = AnyView(
            CommandWheelView(
                model: model,
                onActivateSlot: onActivateSlot,
                onActivateCenter: onActivateCenter
            )
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController

        self.panel = panel
        presentedModel = model
        self.hostingController = hostingController
        focusRestorationProcessIdentifier = canUseKeyboard
            ? frontmostProcessIdentifier
            : nil
        didTakeKeyFocus = canUseKeyboard

        if canUseKeyboard {
            applicationActivator.activateForKeyboardInput()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        if model.appearance.animationPreference == .disabled {
            model.visualPhase = .visible
        } else {
            Task { @MainActor [weak self, weak model] in
                guard let self, let model, self.presentedModel === model else { return }
                model.visualPhase = .visible
            }
        }
    }

    func dismiss() {
        guard let panel else {
            endSessionObservation()
            return
        }
        let model = presentedModel
        let processIdentifier = didTakeKeyFocus ? focusRestorationProcessIdentifier : nil
        didTakeKeyFocus = false
        focusRestorationProcessIdentifier = nil
        panel.onKeyboardCommand = nil
        self.panel = nil
        hostingController = nil
        presentedModel = nil
        endSessionObservation()

        if let processIdentifier {
            focusRestorer.restoreFocus(to: processIdentifier)
        }

        guard didTearDown == false,
              model?.appearance.animationPreference != .disabled else {
            close(panel)
            return
        }

        model?.visualPhase = .dismissing
        finishDismissingPanel()
        dismissingPanel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel, self.dismissingPanel === panel else { return }
                self.close(panel)
                self.dismissingPanel = nil
            }
        }
    }

    func tearDown() {
        guard didTearDown == false else { return }
        didTearDown = true
        dismissImmediately()
        finishDismissingPanel()
        removeObservers()
        displayConfigurationChanged = nil
        activeSpaceChanged = nil
        frontmostApplicationChanged = nil
        applicationWillTerminate = nil
    }

    private func makePanel(frame: CGRect) -> CommandWheelPanel {
        let panel = CommandWheelPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // `.floating` is intentionally sufficient once the shared active-Space behavior and
        // `fullScreenAuxiliary` are combined; unlike menu levels it does not obscure system UI.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = Self.collectionBehavior
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = false
        panel.setFrame(frame, display: false)
        return panel
    }

    private func dismissImmediately() {
        guard let panel else { return }
        let processIdentifier = didTakeKeyFocus ? focusRestorationProcessIdentifier : nil
        didTakeKeyFocus = false
        focusRestorationProcessIdentifier = nil
        panel.onKeyboardCommand = nil
        self.panel = nil
        hostingController = nil
        presentedModel = nil
        removeObservers()
        close(panel)
        if let processIdentifier {
            focusRestorer.restoreFocus(to: processIdentifier)
        }
    }

    private func finishDismissingPanel() {
        guard let dismissingPanel else { return }
        close(dismissingPanel)
        self.dismissingPanel = nil
    }

    private func close(_ panel: CommandWheelPanel) {
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.close()
    }

    private func installObservers() {
        guard observerTokens.isEmpty else { return }
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displayConfigurationChanged?()
                }
            }
        )
        observerTokens.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.activeSpaceChanged?()
                }
            }
        )
        observerTokens.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let processIdentifier = (
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                )?.processIdentifier
                MainActor.assumeIsolated {
                    self?.frontmostApplicationChanged?(processIdentifier)
                }
            }
        )
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applicationWillTerminate?()
                }
            }
        )
    }

    private func removeObservers() {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
            workspaceNotificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    isolated deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
            workspaceNotificationCenter.removeObserver(token)
        }
        panel?.orderOut(nil)
        panel?.close()
        dismissingPanel?.orderOut(nil)
        dismissingPanel?.close()
    }
}

#if DEBUG
extension CommandWheelWindowController {
    /// Direct presentation hook for deterministic UI validation without registering a hot key.
    func presentForDebugging(
        model: CommandWheelPresentationModel,
        frame: CGRect,
        onActivateSlot: @escaping (Int) -> Void = { _ in },
        onActivateCenter: @escaping () -> Void = {}
    ) {
        let display = CommandWheelDisplaySnapshot(
            identifier: "debug",
            frame: frame,
            visibleFrame: frame,
            scale: 1
        )
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let position = CommandWheelPosition(
            display: display,
            requestedCenter: center,
            actualCenter: center,
            contentFrame: frame,
            wasClamped: false
        )
        present(
            model: model,
            position: position,
            activationBehavior: .toggle,
            frontmostProcessIdentifier: nil,
            onActivateSlot: onActivateSlot,
            onActivateCenter: onActivateCenter,
            onKeyboardCommand: { _ in false }
        )
    }
}
#endif
