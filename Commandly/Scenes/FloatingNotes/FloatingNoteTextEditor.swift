import AppKit
import SwiftUI

/// Native plain text editing supplies selection, undo, spelling and standard macOS editing keys.
struct FloatingNoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let textScale: CGFloat
    let onClose: () -> Void
    let onOversizedInput: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let editor = NoteTextView(frame: .zero)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 2, height: 6)
        editor.delegate = context.coordinator
        editor.onClose = onClose
        editor.setAccessibilityLabel("Note text")
        editor.setAccessibilityIdentifier("floating-note-body")
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NoteTextView else { return }
        editor.isEditable = isEditable
        editor.font = .systemFont(ofSize: 14 * textScale)
        editor.textColor = .labelColor
        editor.onClose = onClose
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? NoteTextView else { return }
        editor.delegate = nil
        editor.onClose = nil
        if editor.window?.initialFirstResponder === editor { editor.window?.initialFirstResponder = nil }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FloatingNoteTextEditor
        init(parent: FloatingNoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString else { return true }
            let previous = textView.string
            let updated = (previous as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
            guard updated.utf8.count <= FloatingNoteModel.maximumBodyBytes || updated.utf8.count < previous.utf8.count else {
                parent.onOversizedInput()
                return false
            }
            return true
        }
    }

    final class NoteTextView: NSTextView {
        var onClose: (() -> Void)?
        private var requestedInitialFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard requestedInitialFocus == false, let window else { return }
            requestedInitialFocus = true
            window.initialFirstResponder = self
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.isKeyWindow else { return }
                window.makeFirstResponder(self)
            }
        }

        override func cancelOperation(_ sender: Any?) {
            // Escape must retain its normal role while an input method is composing text.
            guard hasMarkedText() == false, window?.attachedSheet == nil else {
                super.cancelOperation(sender)
                return
            }
            onClose?()
        }
    }
}
