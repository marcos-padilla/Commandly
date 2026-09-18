import Foundation
import Infrastructure

/// The switches and one-tap actions the Quick Toggles tab offers, in display order.
///
/// Raw values are persisted as the user's hidden set, so renaming a case would bring a hidden row
/// back; keep them stable.
nonisolated enum QuickToggleID: String, CaseIterable, Identifiable, Sendable {
    case appearance
    case keyboardLight
    case microphone
    case emptyTrash
    case ejectDisks
    case hiddenFiles
    case desktopIcons
    case lockScreen
    case displaySleep
    case screenSaver

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .appearance: return "sun.max.fill"
        case .keyboardLight: return "keyboard"
        case .microphone: return "mic.fill"
        case .emptyTrash: return "trash"
        case .ejectDisks: return "eject.fill"
        case .hiddenFiles: return "eye.slash.fill"
        case .desktopIcons: return "desktopcomputer"
        case .lockScreen: return "lock.fill"
        case .displaySleep: return "display"
        case .screenSaver: return "display.and.arrow.down"
        }
    }

    /// Fixed title for rows whose name never changes. A row whose name depends on live state —
    /// "Switch to light mode" — supplies it from the presentation instead.
    var staticTitle: String? {
        switch self {
        case .appearance: return nil
        case .keyboardLight: return "Keyboard light"
        case .microphone: return nil
        case .emptyTrash: return "Empty the Trash"
        case .ejectDisks: return "Eject all disks"
        case .hiddenFiles: return nil
        case .desktopIcons: return nil
        case .lockScreen: return "Lock the screen"
        case .displaySleep: return "Turn off the display"
        case .screenSaver: return "Start the screen saver"
        }
    }

    /// Where System Settings can help when Commandly itself cannot make the change.
    var settingsPane: SystemSettingsPane? {
        switch self {
        case .appearance: return .appearance
        case .keyboardLight: return .keyboard
        case .microphone: return .sound
        case .displaySleep: return .displays
        case .lockScreen: return .privacySecurity
        case .screenSaver: return .displays
        case .emptyTrash, .ejectDisks, .hiddenFiles, .desktopIcons: return nil
        }
    }

    /// Rows that change something outside Commandly in a way the user cannot simply undo with the
    /// same row, so the panel asks before doing it.
    var needsConfirmation: Bool {
        self == .emptyTrash
    }
}

/// What a row's control does.
nonisolated enum QuickToggleControl: Equatable, Sendable {
    /// A switch the user flips. `isOn` is the live system state, not a remembered intent.
    case toggle(isOn: Bool)
    /// A one-tap action with no on/off state of its own.
    case action
    /// Commandly cannot make this change on this build. The row stays visible and explains why.
    case unavailable
}

/// One row as the panel draws it.
nonisolated struct QuickTogglePresentation: Identifiable, Equatable, Sendable {
    var id: QuickToggleID { toggle }

    let toggle: QuickToggleID
    let title: String
    let caption: String
    let control: QuickToggleControl
    /// Set while the row's own work is in flight, so it cannot be tapped twice.
    let isBusy: Bool

    var isEnabled: Bool { control != .unavailable && isBusy == false }
}

/// How live system state becomes the row titles and captions.
///
/// Pure, so every row's wording can be exercised without a microphone, a disk, or a Finder.
nonisolated enum QuickToggleRules {
    /// The appearance row names the mode it would switch *to*, not the one in effect.
    static func appearanceTitle(isDark: Bool) -> String {
        isDark ? "Switch to light mode" : "Switch to dark mode"
    }

    static func appearanceCaption(isDark: Bool?) -> String {
        guard isDark != nil else {
            return "Commandly could not read the current system appearance."
        }
        return "Changes the appearance of the whole system."
    }

    static func microphoneTitle(isMuted: Bool?) -> String {
        isMuted == true ? "Unmute microphone" : "Mute microphone"
    }

    static func microphoneCaption(deviceName: String?, canChange: Bool) -> String {
        guard canChange else {
            guard let deviceName else {
                return "No input device is reporting a mute control."
            }
            return "\(deviceName) exposes no system-wide mute control."
        }
        return "Cuts the Mac's microphone with a click, across every app."
    }

    static func ejectCaption(ejectableCount: Int) -> String {
        switch ejectableCount {
        case 0: return "No external disk ready to eject."
        case 1: return "One external disk is ready to eject."
        default: return "\(ejectableCount) external disks are ready to eject."
        }
    }

    static func trashCaption(isEmptying: Bool) -> String {
        isEmptying ? "Emptying the Trash…" : "Removes everything from the Trash."
    }

    /// Rows whose change needs Accessibility say so instead of failing silently when it is off.
    static func accessibilityCaption(
        granted: Bool,
        whenGranted: String
    ) -> String {
        granted ? whenGranted : "Needs Accessibility permission."
    }

    /// Why a row cannot act in a sandboxed build. These read as an explanation, never as a
    /// failure the user caused.
    static func unavailableCaption(_ toggle: QuickToggleID) -> String {
        switch toggle {
        case .hiddenFiles:
            return "Showing hidden files means writing the Finder's own settings, which App Sandbox does not allow."
        case .desktopIcons:
            return "Hiding desktop icons means writing the Finder's own settings, which App Sandbox does not allow."
        case .displaySleep:
            return "Putting the display to sleep needs a device interface App Sandbox does not open."
        case .keyboardLight:
            return "This Mac does not report a keyboard backlight to Commandly."
        case .appearance:
            return "Switching the system appearance needs permission to control System Events."
        case .microphone:
            return "No input device is reporting a mute control."
        case .emptyTrash, .ejectDisks, .lockScreen, .screenSaver:
            return "This action is unavailable right now."
        }
    }

    /// Ordered rows after the user's hidden set, which never hides every row.
    static func visibleToggles(hidden: Set<String>) -> [QuickToggleID] {
        let visible = QuickToggleID.allCases.filter { hidden.contains($0.rawValue) == false }
        return visible.isEmpty ? QuickToggleID.allCases : visible
    }
}
