import AppKit
import SwiftUI

@MainActor
final class DisplayResolutionWindowController: NSObject, DisplayResolutionWindowPresenting, NSWindowDelegate {
    private var window: DisplayResolutionWindow?
    private weak var model: DisplayResolutionCoordinator?
    private let appearance: AuxiliaryWindowAppearance
    init(appearance: AuxiliaryWindowAppearance) { self.appearance = appearance; super.init() }

    func present(_ model: DisplayResolutionCoordinator) {
        self.model = model
        if window == nil {
            let panel = DisplayResolutionWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Display Resolution"
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentMinSize = NSSize(width: 480, height: 340)
            panel.tabbingMode = .disallowed
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
            panel.onEscape = { [weak model] in model?.requestClose() }
            panel.contentViewController = NSHostingController(rootView: DisplayResolutionWindowContent(model: model, appearance: appearance))
            window = panel
            panel.center()
        }
        guard let window else { return }
        ensureVisible()
        ActiveSpaceWindowPresenter.present(window)
    }

    func ensureVisible() {
        guard let window else { return }
        let screens = NSScreen.screens
        guard let target = screens.first(where: { $0 == window.screen }) ?? screens.max(by: {
            $0.visibleFrame.width * $0.visibleFrame.height < $1.visibleFrame.width * $1.visibleFrame.height
        }) else { return }
        let visible = target.visibleFrame.insetBy(dx: 10, dy: 10)
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
        // Reposition without activating or restarting the preview deadline on a topology change.
        if model?.hasPendingChange == true, window.isVisible == false { window.orderFront(nil) }
    }

    func close() { window?.close() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.requestClose(); return false }
    func windowWillClose(_ notification: Notification) {
        window?.onEscape = nil; window?.contentViewController = nil; window = nil; model = nil
    }
}

private struct DisplayResolutionWindowContent: View {
    let model: DisplayResolutionCoordinator
    let appearance: AuxiliaryWindowAppearance
    var body: some View { DisplayResolutionView(model: model).commandlyContentSize(appearance.textSize) }
}

@MainActor
private final class DisplayResolutionWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" { onEscape?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}
