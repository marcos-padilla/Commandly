import ApplicationServices
import CoreGraphics
import Foundation
import Infrastructure

enum WindowSwitcherShortcutSource: Equatable, Sendable {
    case optionTab
    case commandTab
    case toggle
}

enum WindowSwitcherInputCommand: Equatable, Sendable {
    case begin(source: WindowSwitcherShortcutSource, reverse: Bool)
    case cycle(reverse: Bool)
    case move(offset: Int)
    case commit
    case cancel
    case deleteBackward
    case clearSearch
    case appendText(String)
    case perform(WindowAction)
}

/// A value-only keyboard input used by the event tap and deterministic session tests.
nonisolated enum WindowSwitcherKeyboardEvent: Sendable {
    case keyDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        isRepeat: Bool,
        printableText: String?
    )
    case keyUp(keyCode: UInt16, flags: CGEventFlags)
    case flagsChanged(CGEventFlags)
}

/// Tracks whether the first key-down in a physical key press reached the system.
///
/// A keyboard repeat can emit several additional key-down events but still produces only one
/// key-up. The initial key-down therefore owns the release policy. Keeping this bookkeeping free of
/// Core Graphics types makes the event-tap invariant deterministic to test without installing a
/// global monitor.
nonisolated struct WindowSwitcherKeyConsumptionTracker: Sendable {
    private var consumesKeyUpByKeyCode: [UInt16: Bool] = [:]

    mutating func recordKeyDown(
        keyCode: UInt16,
        isRepeat: Bool,
        wasConsumed: Bool
    ) {
        if isRepeat, consumesKeyUpByKeyCode[keyCode] != nil {
            return
        }
        consumesKeyUpByKeyCode[keyCode] = wasConsumed
    }

    mutating func consumeKeyUp(keyCode: UInt16) -> Bool {
        consumesKeyUpByKeyCode.removeValue(forKey: keyCode) ?? false
    }

    mutating func reset() {
        consumesKeyUpByKeyCode.removeAll(keepingCapacity: true)
    }
}

@MainActor
protocol WindowSwitcherInputMonitoring: AnyObject {
    var isRunning: Bool { get }

    @discardableResult
    func start(
        configuration: WindowSwitcherConfiguration,
        onCommand: @escaping (WindowSwitcherInputCommand) -> Void
    ) -> Bool
    func beginToggleSession()
    func endSession()
    func stop()
}

/// Owns the Accessibility-authorized event tap used only by the Window Switcher.
///
/// The monitor observes keyboard flags and key presses; it never records or logs text. Printable
/// characters are delivered only while the ephemeral switcher search is active and are discarded
/// with the session.
@MainActor
final class WindowSwitcherEventMonitor: WindowSwitcherInputMonitoring {
    /// The event tap source is installed on the main run loop. This wrapper documents that the
    /// non-Sendable Core Graphics event never crosses threads while satisfying Swift's callback
    /// isolation checks.
    private struct MainRunLoopEvent: @unchecked Sendable {
        nonisolated(unsafe) let value: CGEvent

        nonisolated init(value: CGEvent) {
            self.value = value
        }
    }

    private enum ActiveTrigger {
        case holdOption
        case holdCommand
        case toggleOption
        case toggleCommand
        case toggleDirect
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var configuration = WindowSwitcherConfiguration.default
    private var onCommand: ((WindowSwitcherInputCommand) -> Void)?
    private var activeTrigger: ActiveTrigger?
    private var keyConsumptionTracker = WindowSwitcherKeyConsumptionTracker()

    var isRunning: Bool { eventTap != nil }

    init(
        configuration: WindowSwitcherConfiguration = .default,
        onCommand: ((WindowSwitcherInputCommand) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onCommand = onCommand
    }

    @discardableResult
    func start(
        configuration: WindowSwitcherConfiguration,
        onCommand: @escaping (WindowSwitcherInputCommand) -> Void
    ) -> Bool {
        stop()
        self.configuration = configuration
        self.onCommand = onCommand

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<WindowSwitcherEventMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            let mainRunLoopEvent = MainRunLoopEvent(value: event)
            let shouldConsume = MainActor.assumeIsolated {
                monitor.handle(type: type, event: mainRunLoopEvent.value)
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            self.onCommand = nil
            return false
        }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func beginToggleSession() {
        activeTrigger = .toggleDirect
    }

    func endSession() {
        activeTrigger = nil
        // Retain key-down state until matching releases arrive. Escape, Return, or modifier release
        // can dismiss the session before a consumed key is physically released.
    }

    func stop() {
        activeTrigger = nil
        keyConsumptionTracker.reset()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        onCommand = nil
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The disabled interval can contain events that this tap never observes, so existing
            // down/up correspondence is no longer trustworthy. Cancel before resuming observation
            // so a hold or toggle session cannot survive with missing modifier/key-release state.
            recoverFromDisabledTap()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .flagsChanged:
            return handleKeyboardEvent(.flagsChanged(event.flags))
        case .keyDown:
            return handleKeyboardEvent(.keyDown(
                keyCode: keyCode,
                flags: event.flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                printableText: configuration.allowsSearch ? Self.printableText(from: event) : nil
            ))
        case .keyUp:
            return handleKeyboardEvent(.keyUp(keyCode: keyCode, flags: event.flags))
        default:
            return false
        }
    }

    /// Interprets one value-only keyboard event without installing a global event tap.
    ///
    /// This is internal so app tests can verify shortcut lifecycles without observing or mutating
    /// real keyboard input.
    func handleKeyboardEvent(_ event: WindowSwitcherKeyboardEvent) -> Bool {
        switch event {
        case let .flagsChanged(flags):
            handleFlagsChanged(flags)
            return false
        case let .keyUp(keyCode, _):
            return keyConsumptionTracker.consumeKeyUp(keyCode: keyCode)
        case let .keyDown(keyCode, flags, isRepeat, printableText):
            let shouldConsume = handleKeyDown(
                keyCode: keyCode,
                flags: flags,
                isRepeat: isRepeat,
                printableText: printableText
            )
            keyConsumptionTracker.recordKeyDown(
                keyCode: keyCode,
                isRepeat: isRepeat,
                wasConsumed: shouldConsume
            )
            return shouldConsume
        }
    }

    private func handleKeyDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        isRepeat: Bool,
        printableText: String?
    ) -> Bool {
        if keyCode == 48 {
            if let activeTrigger {
                return handleTab(
                    activeTrigger: activeTrigger,
                    flags: flags,
                    isRepeat: isRepeat
                )
            }

            if flags.contains(.maskAlternate) {
                activeTrigger = configuration.shortcutMode == .holdToCycle
                    ? .holdOption
                    : .toggleOption
                onCommand?(.begin(source: .optionTab, reverse: flags.contains(.maskShift)))
                return true
            }
            if configuration.replacesCommandTab,
               flags.contains(.maskCommand) {
                activeTrigger = configuration.shortcutMode == .holdToCycle
                    ? .holdCommand
                    : .toggleCommand
                onCommand?(.begin(source: .commandTab, reverse: flags.contains(.maskShift)))
                return true
            }
            return false
        }

        guard activeTrigger != nil else {
            return false
        }

        if flags.contains(.maskCommand) {
            switch keyCode {
            case 13:
                onCommand?(.perform(.close))
            case 46:
                onCommand?(.perform(.toggleMinimized))
            case 3:
                onCommand?(.perform(.toggleFullScreen))
            case 12:
                onCommand?(.perform(.quit))
            case 5:
                onCommand?(.perform(.zoom))
            case 8:
                onCommand?(.perform(.center))
            case 18:
                onCommand?(.perform(.leftHalf))
            case 19:
                onCommand?(.perform(.rightHalf))
            case 20:
                onCommand?(.perform(.topHalf))
            case 21:
                onCommand?(.perform(.bottomHalf))
            default:
                break
            }
            if [3, 5, 8, 12, 13, 18, 19, 20, 21, 46].contains(keyCode) {
                return true
            }
        }

        switch keyCode {
        case 53:
            onCommand?(.cancel)
            return true
        case 36, 76:
            onCommand?(.commit)
            return true
        case 123, 126:
            onCommand?(.move(offset: -1))
            return true
        case 124, 125:
            onCommand?(.move(offset: 1))
            return true
        case 51:
            onCommand?(.deleteBackward)
            return true
        default:
            break
        }

        if let command = Self.textOrVimCommand(
            keyCode: keyCode,
            flags: flags,
            printableText: configuration.allowsSearch ? printableText : nil,
            configuration: configuration
        ) {
            onCommand?(command)
            return true
        }

        // The non-key panel owns keyboard interaction for the lifetime of an active session. Do not
        // leak unsupported shortcuts or text to the application behind it.
        return true
    }

    private func handleFlagsChanged(_ flags: CGEventFlags) {
        switch activeTrigger {
        case .holdOption where flags.contains(.maskAlternate) == false:
            activeTrigger = nil
            onCommand?(.commit)
        case .holdCommand where flags.contains(.maskCommand) == false:
            activeTrigger = nil
            onCommand?(.commit)
        default:
            break
        }
    }

    private func handleTab(
        activeTrigger: ActiveTrigger,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> Bool {
        switch activeTrigger {
        case .holdOption:
            guard flags.contains(.maskAlternate) else { return false }
        case .holdCommand:
            guard flags.contains(.maskCommand) else { return false }
        case .toggleOption where flags.contains(.maskAlternate):
            guard isRepeat == false else { return true }
            self.activeTrigger = nil
            onCommand?(.cancel)
            return true
        case .toggleCommand where flags.contains(.maskCommand):
            guard isRepeat == false else { return true }
            self.activeTrigger = nil
            onCommand?(.cancel)
            return true
        case .toggleOption, .toggleCommand, .toggleDirect:
            let disallowedModifiers = flags
                .intersection([.maskAlternate, .maskCommand, .maskControl])
            guard disallowedModifiers.isEmpty else { return false }
        }

        onCommand?(.cycle(reverse: flags.contains(.maskShift)))
        return true
    }

    /// Clears state after Core Graphics disables the tap and cancels any active presentation.
    ///
    /// This value-seam is internal so tests can exercise disabled-tap recovery without installing a
    /// global event tap or depending on Core Graphics timeout behavior.
    func recoverFromDisabledTap() {
        let wasActive = activeTrigger != nil
        activeTrigger = nil
        keyConsumptionTracker.reset()
        if wasActive {
            onCommand?(.cancel)
        }
    }

    /// Resolves printable search input before optional Vim navigation.
    ///
    /// Keeping this decision independent of the event tap makes the precedence explicit: when
    /// search accepts a printable H/J/K/L key, it is always text and never a navigation command.
    nonisolated static func textOrVimCommand(
        keyCode: UInt16,
        flags: CGEventFlags,
        printableText: String?,
        configuration: WindowSwitcherConfiguration
    ) -> WindowSwitcherInputCommand? {
        let hasCommandModifier = flags
            .intersection([.maskCommand, .maskControl, .maskAlternate])
            .isEmpty == false
        if configuration.allowsSearch,
           hasCommandModifier == false,
           let printableText,
           printableText.isEmpty == false {
            return .appendText(printableText)
        }

        guard configuration.allowsVimNavigation,
              hasCommandModifier == false else {
            return nil
        }
        switch keyCode {
        case 4, 40:
            return .move(offset: -1)
        case 37, 38:
            return .move(offset: 1)
        default:
            return nil
        }
    }

    private nonisolated static func printableText(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        guard text.unicodeScalars.allSatisfy({ scalar in
            CharacterSet.controlCharacters.contains(scalar) == false
        }) else {
            return nil
        }
        return text
    }
}

@MainActor
final class InMemoryWindowSwitcherInputMonitor: WindowSwitcherInputMonitoring {
    private(set) var isRunning = false
    private(set) var configuration: WindowSwitcherConfiguration?
    private var onCommand: ((WindowSwitcherInputCommand) -> Void)?

    func start(
        configuration: WindowSwitcherConfiguration,
        onCommand: @escaping (WindowSwitcherInputCommand) -> Void
    ) -> Bool {
        self.configuration = configuration
        self.onCommand = onCommand
        isRunning = true
        return true
    }

    func beginToggleSession() {}
    func endSession() {}

    func stop() {
        isRunning = false
        configuration = nil
        onCommand = nil
    }

    func send(_ command: WindowSwitcherInputCommand) {
        onCommand?(command)
    }
}
