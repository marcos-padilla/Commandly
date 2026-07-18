import Carbon
import Foundation

/// Stable process-local identity for a globally registered Commandly shortcut.
struct GlobalShortcutID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Lifecycle event emitted for a registered global shortcut.
enum GlobalShortcutPhase: Equatable, Sendable {
    case pressed
    case released
    /// The registration disappeared while the shortcut was held.
    case cancelled
}

/// A shortcut event tied to the registration generation that produced it.
struct GlobalShortcutEvent: Equatable, Sendable {
    let id: GlobalShortcutID
    let phase: GlobalShortcutPhase
    let generation: UInt64
}

/// Immutable registration identity captured before a Carbon callback is queued onto the main run
/// loop. Numeric Carbon identifiers are intentionally reused between replacement plans, so the
/// generation and feature identifier must travel with the queued event.
struct GlobalShortcutCallbackIdentity: Equatable, Sendable {
    let numericID: UInt32
    let id: GlobalShortcutID
    let generation: UInt64
}

/// One shortcut requested by an app feature.
struct GlobalShortcutRegistration: Equatable, Sendable {
    let id: GlobalShortcutID
    let hotKey: LauncherHotKey
}

enum GlobalShortcutRegistrationIssue: Equatable, Sendable {
    case duplicate(owner: GlobalShortcutID)
    case duplicateID
    case unavailable
}

struct GlobalShortcutPlan: Sendable {
    let registrations: [GlobalShortcutRegistration]
    let issues: [GlobalShortcutID: GlobalShortcutRegistrationIssue]

    /// Resolves in-process conflicts deterministically in request order.
    static func resolve(_ requested: [GlobalShortcutRegistration]) -> GlobalShortcutPlan {
        var issues: [GlobalShortcutID: GlobalShortcutRegistrationIssue] = [:]
        var ownersByHotKey: [LauncherHotKey: GlobalShortcutID] = [:]
        var seenIDs: Set<GlobalShortcutID> = []
        var accepted: [GlobalShortcutRegistration] = []

        for registration in requested {
            guard seenIDs.insert(registration.id).inserted else {
                issues[registration.id] = .duplicateID
                continue
            }
            guard registration.hotKey.isValid else {
                issues[registration.id] = .unavailable
                continue
            }
            if let owner = ownersByHotKey[registration.hotKey] {
                issues[registration.id] = .duplicate(owner: owner)
                continue
            }
            ownersByHotKey[registration.hotKey] = registration.id
            accepted.append(registration)
        }

        return GlobalShortcutPlan(registrations: accepted, issues: issues)
    }
}

/// Owns every app-lifetime Carbon hot-key registration and emits press/release phases.
///
/// Carbon marks its event APIs as non-thread-safe, so registration, callback delivery, and
/// teardown are isolated to the main actor. A held shortcut is cancelled before a replacement
/// plan is installed, preventing a release from an old registration from completing a newer
/// Command Wheel session.
@MainActor
final class GlobalShortcutMonitor {
    private struct Registration {
        let definition: GlobalShortcutRegistration
        let reference: EventHotKeyRef
    }

    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var pressedNumericIDs: Set<UInt32> = []
    private var onEvent: ((GlobalShortcutEvent) -> Void)?
    private var activeCarbonSignature: OSType?
    private(set) var generation: UInt64 = 0

    /// Atomically replaces registrations and returns conflicts or Carbon failures by feature ID.
    func replace(
        _ requested: [GlobalShortcutRegistration],
        onEvent: @escaping (GlobalShortcutEvent) -> Void
    ) -> [GlobalShortcutID: GlobalShortcutRegistrationIssue] {
        stop(notifyCancellation: true)
        generation &+= 1
        self.onEvent = onEvent

        let plan = GlobalShortcutPlan.resolve(requested)
        var issues = plan.issues
        guard plan.registrations.isEmpty == false else { return issues }
        activeCarbonSignature = Self.carbonSignature(for: generation)
        guard installHandler() else {
            for registration in plan.registrations {
                issues[registration.id] = .unavailable
            }
            activeCarbonSignature = nil
            self.onEvent = nil
            return issues
        }

        for (offset, definition) in plan.registrations.enumerated() {
            let numericID = UInt32(offset + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(definition.hotKey.keyCode),
                Self.carbonModifiers(definition.hotKey.modifiers),
                EventHotKeyID(
                    signature: activeCarbonSignature ?? Self.signatureSeed,
                    id: numericID
                ),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                issues[definition.id] = .unavailable
                continue
            }
            registrations[numericID] = Registration(
                definition: definition,
                reference: reference
            )
        }

        return issues
    }

    /// Removes all registrations and cancels any shortcut that is currently held.
    func stop() {
        stop(notifyCancellation: true)
    }

    /// Deterministic callback entry point used by tests without registering a real shortcut.
    func dispatchForTesting(numericID: UInt32, phase: GlobalShortcutPhase) {
        guard let identity = callbackIdentity(numericID: numericID) else { return }
        dispatch(identity: identity, phase: phase)
    }

    /// Captures the immutable identity a callback would carry before asynchronous delivery.
    func captureCallbackForTesting(numericID: UInt32) -> GlobalShortcutCallbackIdentity? {
        callbackIdentity(numericID: numericID)
    }

    /// Delivers a previously captured callback identity, allowing replacement races to be tested
    /// without depending on Carbon or run-loop timing.
    func dispatchForTesting(
        identity: GlobalShortcutCallbackIdentity,
        phase: GlobalShortcutPhase
    ) {
        dispatch(identity: identity, phase: phase)
    }

    /// Installs deterministic registrations without calling Carbon, for lifecycle tests.
    func installForTesting(
        _ requested: [GlobalShortcutRegistration],
        onEvent: @escaping (GlobalShortcutEvent) -> Void
    ) -> [GlobalShortcutID: GlobalShortcutRegistrationIssue] {
        stop(notifyCancellation: true)
        generation &+= 1
        self.onEvent = onEvent
        let plan = GlobalShortcutPlan.resolve(requested)
        for (offset, definition) in plan.registrations.enumerated() {
            let numericID = UInt32(offset + 1)
            testingRegistrations[numericID] = definition
        }
        return plan.issues
    }

    private var testingRegistrations: [UInt32: GlobalShortcutRegistration] = [:]

    private func stop(notifyCancellation: Bool) {
        if notifyCancellation {
            for numericID in pressedNumericIDs.sorted() {
                emit(numericID: numericID, phase: .cancelled)
            }
        }
        pressedNumericIDs.removeAll()

        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        testingRegistrations.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        activeCarbonSignature = nil
        onEvent = nil
    }

    private func installHandler() -> Bool {
        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
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
                guard readStatus == noErr else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<GlobalShortcutMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let eventKind = GetEventKind(event)
                let phase: GlobalShortcutPhase
                switch eventKind {
                case UInt32(kEventHotKeyPressed):
                    phase = .pressed
                case UInt32(kEventHotKeyReleased):
                    phase = .released
                default:
                    return OSStatus(eventNotHandledErr)
                }
                let identity = MainActor.assumeIsolated {
                    monitor.callbackIdentity(
                        numericID: hotKeyID.id,
                        carbonSignature: hotKeyID.signature
                    )
                }
                guard let identity else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        monitor.dispatch(identity: identity, phase: phase)
                    }
                }
                return noErr
            }
        let status = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                callback,
                buffer.count,
                buffer.baseAddress,
                userData,
                &handlerRef
            )
        }
        return status == noErr
    }

    private func dispatch(
        identity: GlobalShortcutCallbackIdentity,
        phase: GlobalShortcutPhase
    ) {
        guard identity.generation == generation,
              definition(for: identity.numericID)?.id == identity.id else { return }
        switch phase {
        case .pressed:
            guard pressedNumericIDs.insert(identity.numericID).inserted else { return }
            emit(identity: identity, phase: .pressed)
        case .released:
            guard pressedNumericIDs.remove(identity.numericID) != nil else { return }
            emit(identity: identity, phase: .released)
        case .cancelled:
            guard pressedNumericIDs.remove(identity.numericID) != nil else { return }
            emit(identity: identity, phase: .cancelled)
        }
    }

    private func emit(numericID: UInt32, phase: GlobalShortcutPhase) {
        guard let identity = callbackIdentity(numericID: numericID) else { return }
        emit(identity: identity, phase: phase)
    }

    private func emit(identity: GlobalShortcutCallbackIdentity, phase: GlobalShortcutPhase) {
        onEvent?(
            GlobalShortcutEvent(
                id: identity.id,
                phase: phase,
                generation: identity.generation
            )
        )
    }

    private func callbackIdentity(
        numericID: UInt32,
        carbonSignature: OSType? = nil
    ) -> GlobalShortcutCallbackIdentity? {
        if let carbonSignature, carbonSignature != activeCarbonSignature {
            return nil
        }
        guard let definition = definition(for: numericID) else { return nil }
        return GlobalShortcutCallbackIdentity(
            numericID: numericID,
            id: definition.id,
            generation: generation
        )
    }

    private func definition(for numericID: UInt32) -> GlobalShortcutRegistration? {
        registrations[numericID]?.definition ?? testingRegistrations[numericID]
    }

    private static func carbonModifiers(_ modifiers: LauncherHotKeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static func carbonSignature(for generation: UInt64) -> OSType {
        let foldedGeneration = UInt32(truncatingIfNeeded: generation)
            ^ UInt32(truncatingIfNeeded: generation >> 32)
        return signatureSeed &+ foldedGeneration
    }

    private static let signatureSeed: OSType = 0x434D_4753 // "CMGS"
}
