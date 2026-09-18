import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Typed failures from the screen and keyboard-light actions.
nonisolated enum ScreenControlError: Error, Equatable, Sendable {
    /// Posting a key requires Accessibility, which has not been granted.
    case needsAccessibility
    case actionFailed
    case screenSaverUnavailable
}

/// Locks the screen, starts the screen saver, and drives the keyboard backlight.
nonisolated protocol ScreenControlling: Sendable {
    /// Locks the screen the way ⌃⌘Q does.
    func lockScreen() throws
    /// Starts the screen saver on every display.
    func startScreenSaver() throws
    /// Current keyboard backlight level, `0...1`, or `nil` on a Mac that reports none.
    func keyboardBacklightLevel() -> Double?
    /// Steps the backlight all the way off, or back up to a usable level.
    func setKeyboardBacklight(on: Bool) throws
}

/// Native adapter for the screen and keyboard-light rows.
///
/// The backlight level is a plain IO registry read. Changing it is done by posting the same
/// illumination keys the keyboard has, because the interface that sets the level directly is not
/// open to a sandboxed app. Locking posts ⌃⌘Q for the same reason. Both need Accessibility, and
/// both report that rather than failing quietly.
nonisolated struct NativeScreenControlService: ScreenControlling {
    /// `Q`, which with Command and Control is the system's lock-screen shortcut.
    private static let lockKeyCode: CGKeyCode = 12
    /// The `NSEvent` subtype that carries media keys.
    private static let mediaKeySubtype: Int16 = 8
    /// Illumination up and down, as reported in a system-defined event's `data1`.
    private static let illuminationUpKey: Int32 = 21
    private static let illuminationDownKey: Int32 = 22
    /// Enough presses to cross the backlight's whole range from either end.
    private static let illuminationSteps = 16
    private static let screenSaverPath =
        "/System/Library/CoreServices/ScreenSaverEngine.app"

    /// Registry properties different keyboard drivers publish the backlight level under.
    private static let backlightProperties = [
        "KeyboardBacklightBrightness",
        "KeyboardBacklightLevel",
        "BacklightLevel",
    ]

    func lockScreen() throws {
        guard AXIsProcessTrusted() else { throw ScreenControlError.needsAccessibility }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.lockKeyCode,
            keyDown: true
        ), let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.lockKeyCode,
            keyDown: false
        ) else {
            throw ScreenControlError.actionFailed
        }
        down.flags = [.maskCommand, .maskControl]
        up.flags = [.maskCommand, .maskControl]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func startScreenSaver() throws {
        let url = URL(fileURLWithPath: Self.screenSaverPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScreenControlError.screenSaverUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func keyboardBacklightLevel() -> Double? {
        for serviceName in ["AppleHIDKeyboardEventDriverV2", "AppleKeyboardBacklight"] {
            guard let level = Self.backlightLevel(serviceName: serviceName) else { continue }
            return level
        }
        return nil
    }

    func setKeyboardBacklight(on: Bool) throws {
        guard AXIsProcessTrusted() else { throw ScreenControlError.needsAccessibility }
        let keyCode = on ? Self.illuminationUpKey : Self.illuminationDownKey
        // The level is set by the driver, not by this app, so the range is crossed a step at a
        // time exactly as the keyboard's own keys do.
        for _ in 0..<Self.illuminationSteps {
            Self.postIlluminationKey(keyCode)
        }
    }

    /// Reads one driver's backlight property and scales it to `0...1`.
    ///
    /// Drivers report the level on different scales, so the maximum is taken from the registry
    /// where it is published and falls back to the common byte range otherwise.
    private static func backlightLevel(serviceName: String) -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(serviceName),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        // The advance lives in the condition so the `defer` only releases.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            for property in backlightProperties {
                guard let reference = IORegistryEntryCreateCFProperty(
                    entry, property as CFString, kCFAllocatorDefault, 0
                ), let value = reference.takeRetainedValue() as? NSNumber else { continue }

                let maximum = (IORegistryEntryCreateCFProperty(
                    entry, "KeyboardBacklightMaximum" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? NSNumber)?.doubleValue ?? 255
                guard maximum > 0 else { continue }
                return min(1, max(0, value.doubleValue / maximum))
            }
        }
        return nil
    }

    private static func postIlluminationKey(_ keyCode: Int32) {
        for state in [0x0a, 0x0b] {
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: mediaKeySubtype,
                data1: Int((keyCode << 16) | Int32(state << 8)),
                data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
