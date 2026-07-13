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
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard readStatus == noErr,
                      hotKeyID.signature == OptionSpaceHotkeyMonitor.signature,
                      hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
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

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
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

    private static let signature: OSType = 0x434D_4C59 // "CMLY"
}
