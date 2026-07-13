import Carbon
import CommandKit
import Foundation

enum ApplicationHotkeyRegistrationIssue: Equatable, Sendable {
    case duplicate(CommandID)
    case unavailable

    var message: String {
        switch self {
        case .duplicate:
            return "This shortcut is already assigned to another Commandly application."
        case .unavailable:
            return "This shortcut is reserved by Commandly, macOS, or another application."
        }
    }
}

struct ApplicationHotkeyPlan {
    let registrations: [(CommandID, LauncherHotKey)]
    let issues: [CommandID: ApplicationHotkeyRegistrationIssue]

    static func resolve(
        _ hotKeys: [(CommandID, LauncherHotKey)]
    ) -> ApplicationHotkeyPlan {
        var issues: [CommandID: ApplicationHotkeyRegistrationIssue] = [:]
        var owners: [LauncherHotKey: CommandID] = [:]
        let unique = hotKeys.filter { commandID, hotKey in
            guard hotKey.isValid else {
                issues[commandID] = .unavailable
                return false
            }
            guard let owner = owners[hotKey] else {
                owners[hotKey] = commandID
                return true
            }
            issues[commandID] = .duplicate(owner)
            return false
        }
        return ApplicationHotkeyPlan(registrations: unique, issues: issues)
    }
}

/// Owns system-wide shortcuts for registered launcher applications.
///
/// `@unchecked Sendable` is required because Carbon invokes a C callback with an opaque pointer.
/// All mutable state is installed, removed, and read on the main thread; the callback immediately
/// hops to the main queue before accessing the stored trigger closure.
final class ApplicationHotkeyMonitor: @unchecked Sendable {
    private struct Registration {
        let commandID: CommandID
        let reference: EventHotKeyRef
    }

    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var onTrigger: ((CommandID) -> Void)?

    @MainActor
    func replace(
        _ hotKeys: [(CommandID, LauncherHotKey)],
        onTrigger: @escaping (CommandID) -> Void
    ) -> [CommandID: ApplicationHotkeyRegistrationIssue] {
        stop()
        self.onTrigger = onTrigger

        let plan = ApplicationHotkeyPlan.resolve(hotKeys)
        let unique = plan.registrations
        var issues = plan.issues
        guard unique.isEmpty == false, installHandler() else {
            for (commandID, _) in unique where issues[commandID] == nil {
                issues[commandID] = .unavailable
            }
            return issues
        }

        for (offset, pair) in unique.enumerated() {
            let numericID = UInt32(offset + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(pair.1.keyCode),
                carbonModifiers(pair.1.modifiers),
                EventHotKeyID(signature: Self.signature, id: numericID),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                issues[pair.0] = .unavailable
                continue
            }
            registrations[numericID] = Registration(commandID: pair.0, reference: reference)
        }
        return issues
    }

    @MainActor
    func stop() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations = [:]
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onTrigger = nil
    }

    @MainActor
    private func installHandler() -> Bool {
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
                      hotKeyID.signature == ApplicationHotkeyMonitor.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<ApplicationHotkeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.trigger(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        return status == noErr
    }

    @MainActor
    private func trigger(id: UInt32) {
        guard let commandID = registrations[id]?.commandID else { return }
        onTrigger?(commandID)
    }

    private func carbonModifiers(_ modifiers: LauncherHotKeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static let signature: OSType = 0x434D_4150 // "CMAP"
}
