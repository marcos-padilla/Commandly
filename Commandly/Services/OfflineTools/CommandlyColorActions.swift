import CommandKit

extension CommandlyColorFormat {
    var copyActionID: CommandActionID {
        CommandActionID(rawValue: "color.copy.\(rawValue)")
    }

    var shortcutNumber: String {
        switch self {
        case .hex: "1"
        case .hexWithAlpha: "2"
        case .rgba: "3"
        case .rgbaPercentage: "4"
        case .rgbCSS4: "5"
        case .hsl: "6"
        }
    }

    var keyHint: CommandKeyHint { CommandKeyHint(symbols: ["⌘", shortcutNumber]) }

    static func matching(_ actionID: CommandActionID) -> Self? {
        allCases.first { $0.copyActionID == actionID }
    }

    func copyAction(isEnabled: Bool = true) -> CommandActionDescriptor {
        CommandActionDescriptor(id: copyActionID, title: "Copy \(title)", keyHint: keyHint, isEnabled: isEnabled)
    }
}
