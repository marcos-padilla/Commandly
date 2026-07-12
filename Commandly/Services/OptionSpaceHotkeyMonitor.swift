import AppKit
import Carbon
import Foundation

/// Registers ⌥Space system-wide using Carbon hot keys (no Accessibility prompt).
///
/// `@unchecked Sendable` is required because Carbon installs a C callback that
/// retains `self` via an opaque pointer; all mutable state is touched only from
/// the main thread after hopping with `DispatchQueue.main`.
final class OptionSpaceHotkeyMonitor: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    func start(onTrigger: @escaping () -> Void) {
        stop()
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let monitor = Unmanaged<OptionSpaceHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.onTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard status == noErr else {
            stop()
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CMLY"), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            stop()
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onTrigger = nil
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for character in string.utf8.prefix(4) {
        result = (result << 8) + OSType(character)
    }
    return result
}
