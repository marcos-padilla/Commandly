import AppKit
import SwiftUI

@MainActor
protocol WindowSwitcherWindowPresenting: AnyObject {
    var isPresented: Bool { get }
    var panelFrame: CGRect? { get }

    func present(model: WindowSwitcherPresentationModel, frame: CGRect)
    func updateFrame(_ frame: CGRect)
    func dismiss()
    func tearDown()
}

/// Hosts the Window Switcher in a nonactivating panel so selection never steals focus from the
/// application that will receive the final window action.
@MainActor
final class WindowSwitcherWindowController: WindowSwitcherWindowPresenting {
    static let collectionBehavior = ActiveSpaceWindowPresenter.overlayCollectionBehavior
        .union(.fullScreenAuxiliary)

    private var panel: WindowSwitcherPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var model: WindowSwitcherPresentationModel?

    var isPresented: Bool { panel?.isVisible == true }
    var panelFrame: CGRect? { panel?.frame }
    var currentPanel: WindowSwitcherPanel? { panel }

    func present(model: WindowSwitcherPresentationModel, frame: CGRect) {
        dismiss()
        let panel = makePanel(frame: frame)
        let hostingController = NSHostingController(
            rootView: AnyView(WindowSwitcherView(model: model))
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        panel.alphaValue = 0

        self.model = model
        self.panel = panel
        self.hostingController = hostingController
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func updateFrame(_ frame: CGRect) {
        guard let panel else { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        hostingController = nil
        model = nil
        panel.contentViewController = nil
        panel.orderOut(nil)
        panel.close()
    }

    func tearDown() {
        dismiss()
    }

    private func makePanel(frame: CGRect) -> WindowSwitcherPanel {
        let panel = WindowSwitcherPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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
        panel.acceptsMouseMovedEvents = true
        panel.setFrame(frame, display: false)
        return panel
    }
}
