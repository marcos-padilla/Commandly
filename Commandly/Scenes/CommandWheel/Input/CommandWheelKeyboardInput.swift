import AppKit

nonisolated enum CommandWheelKeyboardCommand: Sendable, Equatable {
    case cancel
    case activate
    case next
    case previous
    case selectVisibleSlot(Int)
}

/// Pure translation from AppKit key data into the small set of wheel operations.
nonisolated enum CommandWheelKeyboardInputTranslator {
    static func command(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        isShiftPressed: Bool
    ) -> CommandWheelKeyboardCommand? {
        switch keyCode {
        case 53:
            return .cancel
        case 36, 76:
            return .activate
        case 124, 125:
            return .next
        case 123, 126:
            return .previous
        case 48:
            return isShiftPressed ? .previous : .next
        default:
            break
        }

        guard let character = charactersIgnoringModifiers?.first,
              let number = character.wholeNumberValue,
              (1 ... 9).contains(number) else {
            return nil
        }
        return .selectVisibleSlot(number - 1)
    }

    static func command(for event: NSEvent) -> CommandWheelKeyboardCommand? {
        command(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isShiftPressed: event.modifierFlags.contains(.shift)
        )
    }
}
