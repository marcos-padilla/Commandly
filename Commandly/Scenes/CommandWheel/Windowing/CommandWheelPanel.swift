import AppKit

/// Dedicated transient panel. Gesture mode keeps `allowsKeyFocus` false; toggle mode enables it
/// only when keyboard selection is configured.
@MainActor
final class CommandWheelPanel: NSPanel {
    var allowsKeyFocus = false
    var onKeyboardCommand: ((CommandWheelKeyboardCommand) -> Bool)?

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if allowsKeyFocus,
           event.type == .keyDown,
           let command = CommandWheelKeyboardInputTranslator.command(for: event),
           onKeyboardCommand?(command) == true {
            return
        }
        super.sendEvent(event)
    }
}
