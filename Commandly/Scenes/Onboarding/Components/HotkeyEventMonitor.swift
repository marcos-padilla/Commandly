import AppKit
import SwiftUI

/// Local key monitor that mirrors every pressed key onto the onboarding keyboard.
struct HotkeyEventMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onPressedKeysChange: (Set<MacKeyboardKeyID>) -> Void
    var onOptionSpace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPressedKeysChange: onPressedKeysChange, onOptionSpace: onOptionSpace)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.attachIfNeeded(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPressedKeysChange = onPressedKeysChange
        context.coordinator.onOptionSpace = onOptionSpace
        context.coordinator.attachIfNeeded(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onPressedKeysChange: (Set<MacKeyboardKeyID>) -> Void
        var onOptionSpace: () -> Void
        private var monitor: Any?
        private var pressedKeyCodes: Set<UInt16> = []
        private var pressedModifiers: Set<MacKeyboardKeyID> = []

        init(
            onPressedKeysChange: @escaping (Set<MacKeyboardKeyID>) -> Void,
            onOptionSpace: @escaping () -> Void
        ) {
            self.onPressedKeysChange = onPressedKeysChange
            self.onOptionSpace = onOptionSpace
        }

        func attachIfNeeded(isEnabled: Bool) {
            if isEnabled {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .keyUp, .flagsChanged]
                ) { [weak self] event in
                    self?.handle(event) ?? event
                }
            } else {
                detach()
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            pressedKeyCodes.removeAll()
            pressedModifiers.removeAll()
            publish()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .flagsChanged:
                updateModifiers(from: event)
                publish()
                return event

            case .keyDown:
                if event.isARepeat == false {
                    pressedKeyCodes.insert(event.keyCode)
                    publish()
                }
                if shouldTriggerOptionSpace(for: event) {
                    onOptionSpace()
                    return nil
                }
                return event

            case .keyUp:
                pressedKeyCodes.remove(event.keyCode)
                publish()
                return event

            default:
                return event
            }
        }

        private func updateModifiers(from event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let code = event.keyCode

            switch code {
            case 56: // left shift
                setModifier(.leftShift, enabled: flags.contains(.shift))
            case 60: // right shift
                setModifier(.rightShift, enabled: flags.contains(.shift))
            case 59: // left control
                setModifier(.leftControl, enabled: flags.contains(.control))
            case 62: // right control
                // MacBooks typically only have left control; still map if present.
                setModifier(.leftControl, enabled: flags.contains(.control))
            case 58: // left option
                setModifier(.leftOption, enabled: flags.contains(.option))
            case 61: // right option
                setModifier(.rightOption, enabled: flags.contains(.option))
            case 55: // left command
                setModifier(.leftCommand, enabled: flags.contains(.command))
            case 54: // right command
                setModifier(.rightCommand, enabled: flags.contains(.command))
            case 63: // fn
                setModifier(.fn, enabled: flags.contains(.function))
            case 57: // caps lock
                // Caps toggles; illuminate while the lock is on.
                if flags.contains(.capsLock) {
                    pressedModifiers.insert(.capsLock)
                } else {
                    pressedModifiers.remove(.capsLock)
                }
            default:
                // Fallback: sync from flags when keyCode is ambiguous.
                syncModifiersFromFlags(flags)
            }
        }

        private func setModifier(_ id: MacKeyboardKeyID, enabled: Bool) {
            if enabled {
                pressedModifiers.insert(id)
            } else {
                pressedModifiers.remove(id)
            }
        }

        private func syncModifiersFromFlags(_ flags: NSEvent.ModifierFlags) {
            // Only used as a safety net; prefer keyCode-specific updates.
            if flags.contains(.shift) == false {
                pressedModifiers.remove(.leftShift)
                pressedModifiers.remove(.rightShift)
            }
            if flags.contains(.control) == false {
                pressedModifiers.remove(.leftControl)
            }
            if flags.contains(.option) == false {
                pressedModifiers.remove(.leftOption)
                pressedModifiers.remove(.rightOption)
            }
            if flags.contains(.command) == false {
                pressedModifiers.remove(.leftCommand)
                pressedModifiers.remove(.rightCommand)
            }
            if flags.contains(.function) == false {
                pressedModifiers.remove(.fn)
            }
            if flags.contains(.capsLock) == false {
                pressedModifiers.remove(.capsLock)
            }
        }

        private func shouldTriggerOptionSpace(for event: NSEvent) -> Bool {
            guard event.keyCode == 49 else { return false }
            let optionDown = pressedModifiers.contains(.leftOption)
                || pressedModifiers.contains(.rightOption)
                || event.modifierFlags.contains(.option)
            return optionDown
        }

        private func publish() {
            var keys = pressedModifiers
            for code in pressedKeyCodes {
                for id in MacBookProKeyboardLayout.keyIDs(forKeyCode: code) {
                    // Modifiers are tracked via flagsChanged for accurate left/right state.
                    if isModifierKey(id) { continue }
                    keys.insert(id)
                }
            }
            onPressedKeysChange(keys)
        }

        private func isModifierKey(_ id: MacKeyboardKeyID) -> Bool {
            switch id {
            case .leftShift, .rightShift, .leftControl, .leftOption, .rightOption,
                 .leftCommand, .rightCommand, .fn, .capsLock:
                return true
            default:
                return false
            }
        }
    }
}
