import CoreGraphics
import Foundation

/// The groups the Controls tab is divided into, in display order.
nonisolated enum ControlGroup: String, CaseIterable, Identifiable, Sendable {
    case windows
    case mouseAndKeyboard
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .mouseAndKeyboard: return "Mouse and Keyboard"
        case .files: return "Files"
        }
    }
}

/// One switch in the Controls tab.
nonisolated enum ControlID: String, CaseIterable, Identifiable, Sendable {
    // Windows
    case appSwitcher
    case appSwitcherLargeIcons
    case quitOnClose
    case maximizeWindows
    case dockPreview
    case dockClickMinimize
    case dockClickHide
    case dockClickCycle
    // Mouse and keyboard
    case invertScrolling
    case focusFollowsMouse
    case disableMouseAcceleration
    case sideButtonNavigation
    case keyboardDebounce
    case threeFingerMiddleClick
    case textSnippets
    case radialMenu
    case mouseButtonShortcuts
    case superKey
    case highlightMode
    // Files
    case finderCutAndPaste
    case shelf

    var id: String { rawValue }

    var group: ControlGroup {
        switch self {
        case .appSwitcher, .appSwitcherLargeIcons, .quitOnClose, .maximizeWindows,
             .dockPreview, .dockClickMinimize, .dockClickHide, .dockClickCycle:
            return .windows
        case .invertScrolling, .focusFollowsMouse, .disableMouseAcceleration,
             .sideButtonNavigation, .keyboardDebounce, .threeFingerMiddleClick,
             .textSnippets, .radialMenu, .mouseButtonShortcuts, .superKey, .highlightMode:
            return .mouseAndKeyboard
        case .finderCutAndPaste, .shelf:
            return .files
        }
    }

    /// A control shown indented under the one it belongs to, and only while that one is on.
    var parent: ControlID? {
        self == .appSwitcherLargeIcons ? .appSwitcher : nil
    }

    var title: String {
        switch self {
        case .appSwitcher: return "App switcher"
        case .appSwitcherLargeIcons: return "Show ⌘Tab with large icons"
        case .quitOnClose: return "Quit on close"
        case .maximizeWindows: return "Maximize windows"
        case .dockPreview: return "Dock Preview"
        case .dockClickMinimize: return "Click the Dock icon to minimize"
        case .dockClickHide: return "Click the Dock icon to hide the app"
        case .dockClickCycle: return "Click the Dock icon to cycle windows"
        case .invertScrolling: return "Invert mouse scrolling"
        case .focusFollowsMouse: return "Focus follows mouse"
        case .disableMouseAcceleration: return "Disable mouse acceleration"
        case .sideButtonNavigation: return "Use side buttons for Back and Forward"
        case .keyboardDebounce: return "Debounce"
        case .threeFingerMiddleClick: return "Three-finger click acts as middle click"
        case .textSnippets: return "Text snippets"
        case .radialMenu: return "Radial menu"
        case .mouseButtonShortcuts: return "Mouse button shortcuts"
        case .superKey: return "Super key"
        case .highlightMode: return "Highlight Mode"
        case .finderCutAndPaste: return "Cut & paste"
        case .shelf: return "Shelf"
        }
    }

    var caption: String {
        switch self {
        case .appSwitcher:
            return "Switch between apps and windows, including minimized windows and multiple windows from the same app."
        case .appSwitcherLargeIcons:
            return "Shows one icon per app with that app's window previews above it."
        case .quitOnClose:
            return "Closing an app's last window also quits it."
        case .maximizeWindows:
            return "The green button maximizes without creating another Space."
        case .dockPreview:
            return "Hover over an open app in the Dock to see its windows, then click the one you want."
        case .dockClickMinimize:
            return "The active app's windows minimize when you click its Dock icon. Click again to bring them back."
        case .dockClickHide:
            return "The active app hides when you click its Dock icon. Click again to bring it back."
        case .dockClickCycle:
            return "Click an active app's Dock icon to rotate through its windows, like ⌘`."
        case .invertScrolling:
            return "Reverses the mouse wheel direction."
        case .focusFollowsMouse:
            return "Focuses and raises the window under the pointer after a short pause."
        case .disableMouseAcceleration:
            return "Removes pointer acceleration for connected mice. Your previous setting returns when this is turned off or Commandly quits."
        case .sideButtonNavigation:
            return "Turns the mouse Back and Forward buttons into navigation commands in Finder, browsers and compatible apps."
        case .keyboardDebounce:
            return "Filters very fast duplicate key presses."
        case .threeFingerMiddleClick:
            return "Pressing the trackpad with three fingers works like a mouse wheel click."
        case .textSnippets:
            return "Type a trigger anywhere and it becomes its text. Everything stays on this Mac."
        case .radialMenu:
            return "Your favorite actions on a wheel."
        case .mouseButtonShortcuts:
            return "Extra buttons and side-wheel directions press key combinations you choose."
        case .superKey:
            return "Caps Lock holds ⌃⌥⇧⌘."
        case .highlightMode:
            return "Shows clicks and keystrokes on screen while you present or record."
        case .finderCutAndPaste:
            return "Use ⌘X to cut and ⌘V to move files and folders in Finder."
        case .shelf:
            return "A floating spot to gather files, images and text, then drag them anywhere later."
        }
    }

    var symbolName: String {
        switch self {
        case .appSwitcher: return "macwindow.on.rectangle"
        case .appSwitcherLargeIcons: return "square.grid.2x2"
        case .quitOnClose: return "xmark.square"
        case .maximizeWindows: return "arrow.up.left.and.arrow.down.right"
        case .dockPreview: return "rectangle.on.rectangle"
        case .dockClickMinimize: return "arrow.down.to.line"
        case .dockClickHide: return "eye.slash"
        case .dockClickCycle: return "rectangle.stack"
        case .invertScrolling: return "computermouse"
        case .focusFollowsMouse: return "rectangle.dashed.and.paperclip"
        case .disableMouseAcceleration: return "cursorarrow.motionlines"
        case .sideButtonNavigation: return "arrow.left.arrow.right"
        case .keyboardDebounce: return "keyboard"
        case .threeFingerMiddleClick: return "cursorarrow.click.2"
        case .textSnippets: return "text.append"
        case .radialMenu: return "circle.grid.cross"
        case .mouseButtonShortcuts: return "circle.circle"
        case .superKey: return "capslock"
        case .highlightMode: return "cursorarrow.rays"
        case .finderCutAndPaste: return "scissors"
        case .shelf: return "tray.full"
        }
    }
}

/// Why a control cannot be offered, when it cannot.
nonisolated enum ControlUnavailableReason: Equatable, Sendable {
    /// Commandly has no implementation for it yet.
    case notBuilt
    /// The feature exists but needs Accessibility, which has not been granted.
    case needsAccessibility
    /// Commandly holds the setting per application rather than as one switch.
    case configuredPerApplication
}

/// One row as the Controls tab draws it.
nonisolated struct ControlPresentation: Identifiable, Equatable, Sendable {
    var id: ControlID { control }

    let control: ControlID
    let isOn: Bool
    /// `nil` when the row is a working switch.
    let unavailable: ControlUnavailableReason?
    /// Indented under its parent.
    let isNested: Bool

    var isEnabled: Bool { unavailable == nil }
}

/// One group with its rows and how many of them are on.
nonisolated struct ControlGroupPresentation: Identifiable, Equatable, Sendable {
    var id: ControlGroup { group }

    let group: ControlGroup
    let rows: [ControlPresentation]

    /// Rows that are on, out of the rows that can be switched at all.
    var enabledCount: Int { rows.filter { $0.isEnabled && $0.isOn }.count }
    var switchableCount: Int { rows.filter(\.isEnabled).count }
    var countLabel: String { "\(enabledCount)/\(switchableCount)" }
}

/// Grouping and wording rules for the Controls tab.
nonisolated enum ControlRules {
    /// The rows of one group, with any nested row placed directly under its parent and hidden
    /// while that parent is off.
    static func rows(
        in group: ControlGroup,
        isOn: (ControlID) -> Bool,
        unavailable: (ControlID) -> ControlUnavailableReason?
    ) -> [ControlPresentation] {
        ControlID.allCases
            .filter { $0.group == group && $0.parent == nil }
            .flatMap { control -> [ControlPresentation] in
                let parentRow = ControlPresentation(
                    control: control,
                    isOn: isOn(control),
                    unavailable: unavailable(control),
                    isNested: false
                )
                let children = ControlID.allCases
                    .filter { $0.parent == control }
                    .filter { _ in parentRow.isOn && parentRow.isEnabled }
                    .map { child in
                        ControlPresentation(
                            control: child,
                            isOn: isOn(child),
                            unavailable: unavailable(child),
                            isNested: true
                        )
                    }
                return [parentRow] + children
            }
    }

    static func caption(
        for control: ControlID,
        unavailable: ControlUnavailableReason?
    ) -> String {
        switch unavailable {
        case .none:
            return control.caption
        case .needsAccessibility:
            return "Needs Accessibility permission."
        case .configuredPerApplication:
            return "Commandly keeps this per app. Choose the apps in Settings."
        case .notBuilt:
            return "Not built in Commandly yet."
        }
    }
}
