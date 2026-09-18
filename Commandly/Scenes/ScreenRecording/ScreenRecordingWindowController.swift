import AppKit
import Infrastructure
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenRecordingWindowController: NSObject, ScreenRecordingWindowPresenting, NSWindowDelegate {
    private let appearance: AuxiliaryWindowAppearance
    private var window: ScreenRecordingWindow?
    private var model: ScreenRecordingModel?
    private var onClosed: (() -> Void)?
    private var closeAlert: NSAlert?
    private var previousCompact: Bool?

    init(appearance: AuxiliaryWindowAppearance = AuxiliaryWindowAppearance()) { self.appearance = appearance }

    func present(model: ScreenRecordingModel, onClosed: @escaping () -> Void) {
        guard window == nil else { focus(); return }
        let window = ScreenRecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 570),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.window = window
        self.model = model
        self.onClosed = onClosed
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("commandly.screen-recording")
        window.title = "Screen Recording"
        window.tabbingMode = .disallowed
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.onRequestClose = { [weak model] in model?.requestClose() }
        window.onSave = { [weak model] in model?.requestExport() }
        model.onChooseExport = { [weak self] in self?.chooseExport() }
        window.contentViewController = NSHostingController(rootView: ScreenRecordingWindowContent(model: model, appearance: appearance))
        window.center()
        observeLayout()
        focus()
    }

    func focus() {
        guard let window else { return }
        ActiveSpaceWindowPresenter.present(window)
    }
    func close() { window?.close() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.requestClose(); return false }
    func windowWillClose(_ notification: Notification) {
        closeAlert = nil
        model?.onChooseExport = nil
        window?.contentViewController = nil
        window?.onRequestClose = nil
        window?.onSave = nil
        window = nil
        model = nil
        let callback = onClosed
        onClosed = nil
        callback?()
    }

    private func chooseExport() {
        guard let window, window.attachedSheet == nil, let model, let artifact = model.artifact else {
            model?.exportSelectionCancelled(); return
        }
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.prompt = "Save Video"
        panel.nameFieldStringValue = "Commandly Recording.\(artifact.draft.container.rawValue)"
        panel.allowedContentTypes = [artifact.draft.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { [weak model] response in
            guard let model else { return }
            if response == .OK, let url = panel.url { model.export(to: url) }
            else { model.exportSelectionCancelled() }
        }
    }

    private func observeLayout() {
        guard let model, let window else { return }
        withObservationTracking {
            _ = model.showsCloseConfirmation
            let compact = model.isCompact
            let larger = appearance.textSize == .larger
            window.isDocumentEdited = model.hasActiveOrUnsavedRecording
            window.title = model.phase == .recording ? "Recording — \(model.audioDescription)" : "Screen Recording"
            let minimum = compact ? NSSize(width: 520, height: larger ? 290 : 250) : NSSize(width: 580, height: larger ? 620 : 570)
            window.contentMinSize = minimum
            if previousCompact != compact || window.contentLayoutRect.height < minimum.height {
                let top = window.frame.maxY
                window.setContentSize(minimum)
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
                previousCompact = compact
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLayout() }
        }
        synchronizeCloseAlert()
    }

    private func synchronizeCloseAlert() {
        guard let window, let model else { return }
        if !model.showsCloseConfirmation {
            if let closeAlert, closeAlert.window.sheetParent != nil {
                window.endSheet(closeAlert.window, returnCode: .cancel)
            }
            return
        }
        guard closeAlert == nil, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        closeAlert = alert
        alert.messageText = "Keep this recording?"
        alert.informativeText = "Save the video to keep it after this window closes. Discard removes its private temporary file."
        let canSave = model.phase == .review && model.artifact != nil
        if canSave { alert.addButton(withTitle: "Save Video…") }
        let discard = alert.addButton(withTitle: "Discard Recording")
        discard.hasDestructiveAction = true
        let keep = alert.addButton(withTitle: "Keep Open")
        keep.keyEquivalent = "\u{1b}"
        if !canSave { discard.keyEquivalent = ""; keep.keyEquivalent = "\r" }
        alert.beginSheetModal(for: window) { [weak self, weak model] response in
            self?.closeAlert = nil
            guard let model else { return }
            model.showsCloseConfirmation = false
            // AppKit's sheet completion runs after the close alert ends. The native Save panel
            // can therefore be opened here without racing SwiftUI alert dismissal.
            if canSave && response == .alertFirstButtonReturn { model.requestExport(closeAfterSaving: true) }
            else if response == (canSave ? .alertSecondButtonReturn : .alertFirstButtonReturn) { model.discard(close: true) }
            else { model.keepOpen() }
        }
    }
}

private struct ScreenRecordingWindowContent: View {
    let model: ScreenRecordingModel
    let appearance: AuxiliaryWindowAppearance
    var body: some View { ScreenRecordingView(model: model).commandlyContentSize(appearance.textSize) }
}

@MainActor
private final class ScreenRecordingWindow: NSWindow {
    var onRequestClose: (() -> Void)?
    var onSave: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "s" { onSave?(); return true }
            if key == "w" { onRequestClose?(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { super.cancelOperation(sender); return }
        onRequestClose?()
    }
}
