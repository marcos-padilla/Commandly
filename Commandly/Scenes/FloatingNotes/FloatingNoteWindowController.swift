import AppKit
import Observation
import SwiftUI

/// A document-like native window whose level can stay above the app the user is working in.
/// It activates only for explicit New/Open/focus requests, never for saves or metadata updates.
@MainActor
final class FloatingNoteWindowController: NSObject, FloatingNoteWindowPresenting, NSWindowDelegate {
    private var window: FloatingNoteWindow?
    private var model: FloatingNoteModel?
    private var onClosed: (() -> Void)?
    private let appearance: AuxiliaryWindowAppearance

    init(appearance: AuxiliaryWindowAppearance = AuxiliaryWindowAppearance()) {
        self.appearance = appearance
        super.init()
    }

    func present(model: FloatingNoteModel, placementIndex: Int, onClosed: @escaping () -> Void) {
        guard window == nil else { focus(); return }
        let window = FloatingNoteWindow(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 452),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        self.window = window
        self.model = model
        self.onClosed = onClosed
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 340, height: 290)
        window.tabbingMode = .disallowed
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.backgroundColor = .windowBackgroundColor
        window.onSave = { [weak model] in model?.save() }
        window.onSaveAndClose = { [weak model] in model?.saveAndClose() }
        window.onSaveCopy = { [weak model] in
            if model?.hasConflict == true { model?.saveAsCopy() }
        }
        window.onRequestClose = { [weak model] in model?.requestClose() }
        window.contentViewController = NSHostingController(
            rootView: FloatingNoteWindowContent(model: model, appearance: appearance)
        )
        if let target = WindowPresentationTargetResolver.activeTarget() {
            let visible = target.visibleFrame
            let offset = CGFloat(placementIndex % 8) * 24
            let x = min(visible.maxX - window.frame.width, max(visible.minX, visible.midX - window.frame.width / 2 + offset))
            let y = min(visible.maxY - window.frame.height, max(visible.minY, visible.midY - window.frame.height / 2 - offset))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else { window.center() }
        observeMetadata()
        focus()
    }

    func focus() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        ActiveSpaceWindowPresenter.present(window)
    }

    func close() { window?.close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.requestClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window?.onSave = nil
        window?.onSaveAndClose = nil
        window?.onSaveCopy = nil
        window?.onRequestClose = nil
        window = nil
        model = nil
        let callback = onClosed
        onClosed = nil
        callback?()
    }

    private func observeMetadata() {
        guard let window, let model else { return }
        withObservationTracking {
            window.title = model.windowTitle
            window.isDocumentEdited = model.hasUnsavedChanges || model.isSaving
            let level: NSWindow.Level = model.isPinned ? .floating : .normal
            if window.level != level { window.level = level }
        } onChange: { [weak self] in
            // Observation fires before the new value is installed. Re-read on the next actor turn;
            // this only updates metadata and window level, and never reorders or claims focus.
            Task { @MainActor [weak self] in self?.observeMetadata() }
        }
    }
}

private struct FloatingNoteWindowContent: View {
    let model: FloatingNoteModel
    let appearance: AuxiliaryWindowAppearance

    var body: some View {
        FloatingNoteView(model: model)
            .commandlyContentSize(appearance.textSize)
    }
}

@MainActor
private final class FloatingNoteWindow: NSWindow {
    var onSave: (() -> Void)?
    var onSaveAndClose: (() -> Void)?
    var onSaveCopy: (() -> Void)?
    var onRequestClose: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSaveCopy?()
            return true
        }
        if modifiers == .command {
            if event.charactersIgnoringModifiers?.lowercased() == "s" { onSave?(); return true }
            if event.keyCode == 36 || event.keyCode == 76 { onSaveAndClose?(); return true }
            if event.charactersIgnoringModifiers?.lowercased() == "w" { onRequestClose?(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { super.cancelOperation(sender); return }
        onRequestClose?()
    }
}
