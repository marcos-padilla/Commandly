import Foundation

/// Stable identity for every key drawn on the onboarding MacBook Pro keyboard.
enum MacKeyboardKeyID: String, Hashable, Sendable, CaseIterable {
    case escape
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case touchID

    case grave, one, two, three, four, five, six, seven, eight, nine, zero
    case minus, equal, delete

    case tab
    case q, w, e, r, t, y, u, i, o, p
    case leftBracket, rightBracket, backslash

    case capsLock
    case a, s, d, f, g, h, j, k, l
    case semicolon, quote, returnKey

    case leftShift
    case z, x, c, v, b, n, m
    case comma, period, slash
    case rightShift

    case fn, leftControl, leftOption, leftCommand
    case space
    case rightCommand, rightOption
    case leftArrow, upArrow, downArrow, rightArrow
}

/// Visual / input description of a single keyboard key.
struct MacKeyboardKeySpec: Identifiable, Sendable, Equatable {
    let id: MacKeyboardKeyID
    /// Primary glyph shown on the keycap.
    let label: String
    /// Optional secondary caption under the glyph.
    let caption: String?
    /// Width in layout units (1 = alphanumeric key).
    let widthUnits: CGFloat
    /// Hardware key codes that illuminate this key.
    let keyCodes: [UInt16]
    /// Whether this key is part of the taught ⌥Space shortcut.
    let isHotkeyTarget: Bool
    /// Compact function-row styling.
    let isFunctionRow: Bool

    init(
        id: MacKeyboardKeyID,
        label: String,
        caption: String? = nil,
        widthUnits: CGFloat = 1,
        keyCodes: [UInt16] = [],
        isHotkeyTarget: Bool = false,
        isFunctionRow: Bool = false
    ) {
        self.id = id
        self.label = label
        self.caption = caption
        self.widthUnits = widthUnits
        self.keyCodes = keyCodes
        self.isHotkeyTarget = isHotkeyTarget
        self.isFunctionRow = isFunctionRow
    }
}

/// US MacBook Pro keyboard geometry and key-code map used by the hotkey step.
enum MacBookProKeyboardLayout {
    /// Ordered rows from top (Escape / function) to bottom (modifiers / arrows).
    static let rows: [[MacKeyboardKeySpec]] = [
        functionRow,
        numberRow,
        topLetterRow,
        homeLetterRow,
        bottomLetterRow,
        modifierRow
    ]

    /// Lookup table from hardware key code → drawn key(s).
    static let keyIDsByCode: [UInt16: [MacKeyboardKeyID]] = {
        var map: [UInt16: [MacKeyboardKeyID]] = [:]
        for row in rows {
            for key in row {
                for code in key.keyCodes {
                    map[code, default: []].append(key.id)
                }
            }
        }
        return map
    }()

    static func keyIDs(forKeyCode code: UInt16) -> [MacKeyboardKeyID] {
        keyIDsByCode[code] ?? []
    }

    // MARK: - Rows

    private static let functionRow: [MacKeyboardKeySpec] = [
        .init(id: .escape, label: "esc", widthUnits: 1.4, keyCodes: [53], isFunctionRow: true),
        .init(id: .f1, label: "F1", widthUnits: 0.95, keyCodes: [122], isFunctionRow: true),
        .init(id: .f2, label: "F2", widthUnits: 0.95, keyCodes: [120], isFunctionRow: true),
        .init(id: .f3, label: "F3", widthUnits: 0.95, keyCodes: [99], isFunctionRow: true),
        .init(id: .f4, label: "F4", widthUnits: 0.95, keyCodes: [118], isFunctionRow: true),
        .init(id: .f5, label: "F5", widthUnits: 0.95, keyCodes: [96], isFunctionRow: true),
        .init(id: .f6, label: "F6", widthUnits: 0.95, keyCodes: [97], isFunctionRow: true),
        .init(id: .f7, label: "F7", widthUnits: 0.95, keyCodes: [98], isFunctionRow: true),
        .init(id: .f8, label: "F8", widthUnits: 0.95, keyCodes: [100], isFunctionRow: true),
        .init(id: .f9, label: "F9", widthUnits: 0.95, keyCodes: [101], isFunctionRow: true),
        .init(id: .f10, label: "F10", widthUnits: 0.95, keyCodes: [109], isFunctionRow: true),
        .init(id: .f11, label: "F11", widthUnits: 0.95, keyCodes: [103], isFunctionRow: true),
        .init(id: .f12, label: "F12", widthUnits: 0.95, keyCodes: [111], isFunctionRow: true),
        .init(id: .touchID, label: "id", caption: "touch", widthUnits: 1.4, isFunctionRow: true)
    ]

    private static let numberRow: [MacKeyboardKeySpec] = [
        .init(id: .grave, label: "`", keyCodes: [50]),
        .init(id: .one, label: "1", keyCodes: [18]),
        .init(id: .two, label: "2", keyCodes: [19]),
        .init(id: .three, label: "3", keyCodes: [20]),
        .init(id: .four, label: "4", keyCodes: [21]),
        .init(id: .five, label: "5", keyCodes: [23]),
        .init(id: .six, label: "6", keyCodes: [22]),
        .init(id: .seven, label: "7", keyCodes: [26]),
        .init(id: .eight, label: "8", keyCodes: [28]),
        .init(id: .nine, label: "9", keyCodes: [25]),
        .init(id: .zero, label: "0", keyCodes: [29]),
        .init(id: .minus, label: "-", keyCodes: [27]),
        .init(id: .equal, label: "=", keyCodes: [24]),
        .init(id: .delete, label: "⌫", caption: "delete", widthUnits: 1.6, keyCodes: [51])
    ]

    private static let topLetterRow: [MacKeyboardKeySpec] = [
        .init(id: .tab, label: "tab", widthUnits: 1.5, keyCodes: [48]),
        .init(id: .q, label: "Q", keyCodes: [12]),
        .init(id: .w, label: "W", keyCodes: [13]),
        .init(id: .e, label: "E", keyCodes: [14]),
        .init(id: .r, label: "R", keyCodes: [15]),
        .init(id: .t, label: "T", keyCodes: [17]),
        .init(id: .y, label: "Y", keyCodes: [16]),
        .init(id: .u, label: "U", keyCodes: [32]),
        .init(id: .i, label: "I", keyCodes: [34]),
        .init(id: .o, label: "O", keyCodes: [31]),
        .init(id: .p, label: "P", keyCodes: [35]),
        .init(id: .leftBracket, label: "[", keyCodes: [33]),
        .init(id: .rightBracket, label: "]", keyCodes: [30]),
        .init(id: .backslash, label: "\\", widthUnits: 1.25, keyCodes: [42])
    ]

    private static let homeLetterRow: [MacKeyboardKeySpec] = [
        .init(id: .capsLock, label: "caps", widthUnits: 1.75, keyCodes: [57]),
        .init(id: .a, label: "A", keyCodes: [0]),
        .init(id: .s, label: "S", keyCodes: [1]),
        .init(id: .d, label: "D", keyCodes: [2]),
        .init(id: .f, label: "F", keyCodes: [3]),
        .init(id: .g, label: "G", keyCodes: [5]),
        .init(id: .h, label: "H", keyCodes: [4]),
        .init(id: .j, label: "J", keyCodes: [38]),
        .init(id: .k, label: "K", keyCodes: [40]),
        .init(id: .l, label: "L", keyCodes: [37]),
        .init(id: .semicolon, label: ";", keyCodes: [41]),
        .init(id: .quote, label: "'", keyCodes: [39]),
        .init(id: .returnKey, label: "⏎", caption: "return", widthUnits: 1.85, keyCodes: [36])
    ]

    private static let bottomLetterRow: [MacKeyboardKeySpec] = [
        .init(id: .leftShift, label: "⇧", caption: "shift", widthUnits: 2.25, keyCodes: [56]),
        .init(id: .z, label: "Z", keyCodes: [6]),
        .init(id: .x, label: "X", keyCodes: [7]),
        .init(id: .c, label: "C", keyCodes: [8]),
        .init(id: .v, label: "V", keyCodes: [9]),
        .init(id: .b, label: "B", keyCodes: [11]),
        .init(id: .n, label: "N", keyCodes: [45]),
        .init(id: .m, label: "M", keyCodes: [46]),
        .init(id: .comma, label: ",", keyCodes: [43]),
        .init(id: .period, label: ".", keyCodes: [47]),
        .init(id: .slash, label: "/", keyCodes: [44]),
        .init(id: .rightShift, label: "⇧", caption: "shift", widthUnits: 2.35, keyCodes: [60])
    ]

    private static let modifierRow: [MacKeyboardKeySpec] = [
        .init(id: .fn, label: "fn", widthUnits: 1.1, keyCodes: [63]),
        .init(id: .leftControl, label: "⌃", caption: "control", widthUnits: 1.15, keyCodes: [59]),
        .init(
            id: .leftOption,
            label: "⌥",
            caption: "option",
            widthUnits: 1.2,
            keyCodes: [58],
            isHotkeyTarget: true
        ),
        .init(id: .leftCommand, label: "⌘", caption: "command", widthUnits: 1.35, keyCodes: [55]),
        .init(
            id: .space,
            label: "",
            caption: "space",
            widthUnits: 5.2,
            keyCodes: [49],
            isHotkeyTarget: true
        ),
        .init(id: .rightCommand, label: "⌘", caption: "command", widthUnits: 1.35, keyCodes: [54]),
        .init(
            id: .rightOption,
            label: "⌥",
            caption: "option",
            widthUnits: 1.2,
            keyCodes: [61],
            isHotkeyTarget: true
        ),
        .init(id: .leftArrow, label: "←", widthUnits: 1.0, keyCodes: [123]),
        .init(id: .upArrow, label: "↑", widthUnits: 1.0, keyCodes: [126]),
        .init(id: .downArrow, label: "↓", widthUnits: 1.0, keyCodes: [125]),
        .init(id: .rightArrow, label: "→", widthUnits: 1.0, keyCodes: [124])
    ]
}
