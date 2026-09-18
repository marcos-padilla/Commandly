import AppKit
import ApplicationServices
import Carbon
import Foundation
import Infrastructure
import IOKit
import IOKit.hid
import IOKit.hidsystem
import os

/// Public permission checks are inert. The visible companion setup action owns permission requests.
public enum CompanionKeyboardPermissions {
    public static func hasAccess() -> Bool { CGPreflightListenEventAccess() && AXIsProcessTrusted() }
    public static func requestFromVisibleSetup() {
        _ = CGRequestListenEventAccess()
        // Public ApplicationServices constant value, spelled literally to avoid importing its mutable C global into Swift concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// A run-loop thread owns all native tap/HID/AX state. This bridge owns only the cross-thread stop handles.
/// Core Foundation explicitly supports stopping/waking a run loop from another thread. Native event
/// objects and input text never cross this lock or the worker thread boundary.
private final class KeyboardTapLifetime: Sendable {
    private struct State { var stopping = false; var finished = false; var loop: CFRunLoop?; var waiters: [CheckedContinuation<Void, Never>] = [] }
    // The only unchecked state is a CFRunLoop reference used exclusively through documented cross-thread
    // stop/wake operations under this lock. It is never exposed to clients; worker native state stays local.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    func install(_ loop: CFRunLoop) -> Bool { state.withLockUnchecked { guard !$0.stopping else { return false }; $0.loop = loop; return true } }
    var isStopping: Bool { state.withLockUnchecked { $0.stopping } }
    func stop() { state.withLockUnchecked { $0.stopping = true; if let loop = $0.loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) } } }
    func waitForFinish() async {
        await withCheckedContinuation { continuation in
            let done = state.withLockUnchecked { value in
                if value.finished { return true }; value.waiters.append(continuation); return false
            }
            if done { continuation.resume() }
        }
    }
    func finished() {
        let waiters = state.withLockUnchecked { value in
            value.loop = nil; value.stopping = true; value.finished = true
            let waiters = value.waiters; value.waiters = []; return waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// One factory-owned authority prevents separately authenticated peers from installing overlapping taps.
/// It is injected by composition, not global state, and never contains key data or native objects.
final class CompanionKeyboardHardwareAuthority: Sendable {
    private let owner = OSAllocatedUnfairLock<UUID?>(initialState: nil)
    func claim(_ id: UUID) -> Bool { owner.withLock { guard $0 == nil else { return false }; $0 = id; return true } }
    func release(_ id: UUID) { owner.withLock { if $0 == id { $0 = nil } } }
}

/// Dedicated thread avoids blocking the helper's main actor in AX/HID or relying on a GUI event loop
/// in its headless LaunchAgent. Constructors never create taps, observe devices, or prompt.
public actor NativeCompanionKeyboardDriver: CompanionKeyboardDriving {
    private var lifetime: KeyboardTapLifetime?
    private let authority: CompanionKeyboardHardwareAuthority
    public init() { authority = CompanionKeyboardHardwareAuthority() }
    init(authority: CompanionKeyboardHardwareAuthority) { self.authority = authority }
    public func start(configuration: CompanionKeyboardConfiguration, authorized: @escaping @Sendable () -> Bool,
                      activation: @escaping @Sendable (UUID) -> Void, stopped: @escaping @Sendable () -> Void) async throws {
        await stop()
        let hardwareID = UUID()
        guard authority.claim(hardwareID) else { throw CompanionKeyboardError.unavailable }
        let authority = authority
        let lifetime = KeyboardTapLifetime(); self.lifetime = lifetime
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                Thread.detachNewThread {
                    autoreleasepool {
                        let worker = KeyboardTapWorker(configuration: configuration, lifetime: lifetime,
                                                       authorized: authorized, activation: activation)
                        do {
                            try worker.start()
                            continuation.resume()
                            if !lifetime.isStopping { CFRunLoopRun() }
                        } catch { continuation.resume(throwing: error) }
                        worker.stop(); authority.release(hardwareID); lifetime.finished()
                        if authorized() { stopped() }
                    }
                }
            }
        } onCancel: { lifetime.stop() }
    }
    public func stop() async { let old = lifetime; lifetime = nil; old?.stop(); await old?.waitForFinish() }
}

/// Confined to the driver-created run-loop thread; callback pointers never escape that thread.
private final class KeyboardTapWorker {
    private let configuration: CompanionKeyboardConfiguration
    private let lifetime: KeyboardTapLifetime
    private let authorized: @Sendable () -> Bool
    private let activation: @Sendable (UUID) -> Void
    private var machine: CompanionKeyboardStateMachine
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hid: IOHIDManager?
    private var hidSystem: io_connect_t = 0
    private var capsLock = false
    private var capsDevices: Set<UInt> = []
    private var timer: CFRunLoopTimer?
    private var focus: KeyboardExpansionFocus?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastCapsDown: TimeInterval?
    private var hyperWasApplied = false
    private static let ownEventTag: Int64 = 0x434D444C59545247
    init(configuration: CompanionKeyboardConfiguration, lifetime: KeyboardTapLifetime,
         authorized: @escaping @Sendable () -> Bool, activation: @escaping @Sendable (UUID) -> Void) {
        self.configuration = configuration; self.lifetime = lifetime; self.authorized = authorized
        self.activation = activation; machine = .init(configuration: configuration)
    }
    func start() throws {
        guard configuration.isValid, authorized(), !lifetime.isStopping else { throw CompanionKeyboardError.disabled }
        guard CompanionKeyboardPermissions.hasAccess() else { throw CompanionKeyboardError.permissionDenied }
        guard !IsSecureEventInputEnabled() else { throw CompanionKeyboardError.secureInput }
        guard lifetime.install(CFRunLoopGetCurrent()) else { throw CompanionKeyboardError.canceled }
        focus = KeyboardExpansionFocus.capture()
        if focus?.caret == 0 { _ = machine.process(.init(.startOfText, timestamp: ProcessInfo.processInfo.systemUptime), field: .editable) }
        if configuration.hyperEnabled { try startPhysicalCaps() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: nil) { [lifetime] _ in lifetime.stop() }))
        }
        let distributed = DistributedNotificationCenter.default()
        // Public Carbon TIS notification; input source changes invalidate the active suffix and key sequence.
        let inputSource = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observers.append((distributed, distributed.addObserver(forName: inputSource, object: nil, queue: nil) { [lifetime] _ in lifetime.stop() }))
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return autoreleasepool { Unmanaged<KeyboardTapWorker>.fromOpaque(context).takeUnretainedValue().receive(type, event) }
            }, userInfo: context), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw CompanionKeyboardError.permissionDenied
        }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // A safety watchdog releases synthetic flags during Secure Input, sleep, revocation or a missed release.
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.25, 0.25, 0, 0) { [weak self] _ in
            self?.checkHealth()
        }
        self.timer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    }
    func stop() {
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        if let timer { CFRunLoopTimerInvalidate(timer) }
        if let hid {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerRegisterInputValueCallback(hid, nil, nil)
            IOHIDManagerClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        _ = machine.reset(); releaseHyper(); focus = nil; capsDevices = []; lastCapsDown = nil
        if hidSystem != 0 { IOServiceClose(hidSystem); hidSystem = 0 }
        tap = nil; source = nil; timer = nil; hid = nil
    }
    private func checkHealth() {
        if !authorized() || lifetime.isStopping || !CompanionKeyboardPermissions.hasAccess() || IsSecureEventInputEnabled()
            || lastCapsDown.map({ ProcessInfo.processInfo.systemUptime - $0 > 5 }) == true {
            _ = machine.reset(); releaseHyper(); focus = nil; capsDevices = []; lastCapsDown = nil
            lifetime.stop()
        }
    }
    private func startPhysicalCaps() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { throw CompanionKeyboardError.unsupportedKeyboard }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &hidSystem) == KERN_SUCCESS,
              IOHIDGetModifierLockState(hidSystem, Int32(kIOHIDCapsLockState), &capsLock) == KERN_SUCCESS else {
            throw CompanionKeyboardError.unsupportedKeyboard
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                              kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        // Subscribe only to physical Caps Lock values. No unrelated HID input is retained or decoded.
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
                                                  kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, status, _, value in
            guard status == kIOReturnSuccess, let context else { return }
            Unmanaged<KeyboardTapWorker>.fromOpaque(context).takeUnretainedValue().physicalCaps(value)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let worker = Unmanaged<KeyboardTapWorker>.fromOpaque(context).takeUnretainedValue()
            worker.lifetime.stop()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        hid = manager
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager), CFSetGetCount(devices) > 0 else {
            throw CompanionKeyboardError.unsupportedKeyboard
        }
    }
    private func physicalCaps(_ value: IOHIDValue) {
        guard authorized(), !IsSecureEventInputEnabled(), !lifetime.isStopping else { checkHealth(); return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad,
              IOHIDElementGetUsage(element) == kHIDUsage_KeyboardCapsLock else { return }
        let device = UInt(bitPattern: Unmanaged.passUnretained(IOHIDElementGetDevice(element)).toOpaque())
        let down = IOHIDValueGetIntegerValue(value) != 0
        let before = !capsDevices.isEmpty
        if down { capsDevices.insert(device) } else { capsDevices.remove(device) }
        guard before != !capsDevices.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastCapsDown = down ? now : nil
        let result = machine.process(.init(down ? .physicalCapsDown : .physicalCapsUp, timestamp: now), field: .unknown)
        if result.toggleCapsLock { capsLock.toggle(); setCapsLock() }
        if result.resetModifiers { releaseHyper() }
    }
    private func setCapsLock() {
        guard hidSystem != 0 else { return }
        var current = false
        guard IOHIDGetModifierLockState(hidSystem, Int32(kIOHIDCapsLockState), &current) == KERN_SUCCESS else { lifetime.stop(); return }
        if current != capsLock, IOHIDSetModifierLockState(hidSystem, Int32(kIOHIDCapsLockState), capsLock) != KERN_SUCCESS { lifetime.stop() }
    }
    private func releaseHyper() {
        guard hyperWasApplied else { return }
        hyperWasApplied = false
        // No fake modifier keydown was posted. One flags notification restores the actual physical flags.
        guard let event = CGEvent(source: nil) else { return }
        event.type = .flagsChanged; event.flags = CGEventSource.flagsState(.hidSystemState)
        if configuration.hyperEnabled { event.flags.remove(.maskAlphaShift); if capsLock { event.flags.insert(.maskAlphaShift) } }
        event.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
        event.post(tap: .cgSessionEventTap)
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Explicit re-enable is required; never resume interception after a lost event sequence.
            lifetime.stop(); _ = machine.reset(); releaseHyper(); return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventTag { return Unmanaged.passUnretained(event) }
        guard authorized(), !lifetime.isStopping, !IsSecureEventInputEnabled() else {
            checkHealth(); return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            _ = machine.reset(); releaseHyper(); focus = nil; return Unmanaged.passUnretained(event)
        }
        let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        if configuration.hyperEnabled && type == .flagsChanged && key == 57 {
            // Caps lock's CG flag is a toggle, not its physical release. HID alone drives tap/hold.
            setCapsLock(); return nil
        }
        let currentFocus = KeyboardExpansionFocus.capture()
        if !KeyboardExpansionFocus.same(focus, currentFocus) {
            _ = machine.reset(); releaseHyper(); focus = currentFocus
            if currentFocus?.caret == 0 { _ = machine.process(.init(.startOfText, timestamp: now), field: .editable) }
        }
        let field = currentFocus?.field ?? .unknown
        guard field != .secure else {
            _ = machine.reset(); releaseHyper(); lifetime.stop(); return Unmanaged.passUnretained(event)
        }
        var text = ""
        if type == .keyDown && !configuration.expansions.isEmpty {
            var values = [UniChar](repeating: 0, count: 4); var length = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &values)
            if length > 0 { text = String(utf16CodeUnits: values, count: min(length, 4)) }
        }
        let kind: CompanionKeyboardEvent.Kind
        if type == .flagsChanged {
            kind = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key)) ? .modifierDown : .modifierUp
        } else { kind = type == .keyUp ? .up : .down }
        var shortcuts = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if type == .flagsChanged {
            if [55,54].contains(key) { shortcuts.remove(.maskCommand) }
            if [59,62].contains(key) { shortcuts.remove(.maskControl) }
            if [58,61].contains(key) { shortcuts.remove(.maskAlternate) }
        }
        let result = machine.process(.init(kind, keyCode: key, timestamp: now,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            hasShortcutModifier: !shortcuts.isEmpty, text: text), field: field)
        guard authorized(), !lifetime.isStopping, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            _ = machine.reset(); releaseHyper(); lifetime.stop(); return Unmanaged.passUnretained(event)
        }
        if let binding = result.activation { activation(binding) }
        if let expansion = result.expansion, let currentFocus {
            currentFocus.replaceSuffix(expansion, authorized: authorized)
        }
        if result.resetModifiers { releaseHyper() }
        if configuration.hyperEnabled {
            event.flags.remove(.maskAlphaShift); if capsLock { event.flags.insert(.maskAlphaShift) }
        }
        if result.addHyper { event.flags.formUnion([.maskCommand, .maskControl, .maskAlternate, .maskShift]); hyperWasApplied = true }
        return result.consume ? nil : Unmanaged.passUnretained(event)
    }
}
