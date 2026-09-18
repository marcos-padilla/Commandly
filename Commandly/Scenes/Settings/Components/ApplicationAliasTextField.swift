import AppKit
import DesignSystem
import SwiftUI

/// A native sheet field whose initial responder is assigned at actual window attachment.
/// This avoids presentation timing assumptions when the launcher opens a sheet from an overlay.
struct ApplicationAliasTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    @Environment(\.commandlyTextScale) private var textScale

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> AliasField {
        let field = AliasField(frame: .zero)
        field.placeholderString = "Short nickname"
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.cell?.sendsActionOnEndEditing = false
        field.setAccessibilityLabel("Application alias")
        field.setAccessibilityIdentifier("application-alias-input")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: AliasField, context: Context) {
        context.coordinator.parent = self
        field.font = .systemFont(ofSize: 14 * textScale)
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: AliasField, coordinator: Coordinator) {
        field.delegate = nil
        field.target = nil
        if field.window?.initialFirstResponder === field { field.window?.initialFirstResponder = nil }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ApplicationAliasTextField
        init(parent: ApplicationAliasTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        @objc func submit(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }

    final class AliasField: NSTextField {
        private var requestedInitialFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard requestedInitialFocus == false, let window else { return }
            requestedInitialFocus = true
            window.initialFirstResponder = self
            // Leave SwiftUI's attachment transaction before installing the AppKit field editor.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                if window.makeFirstResponder(self) { self.selectText(nil) }
            }
        }
    }
}
