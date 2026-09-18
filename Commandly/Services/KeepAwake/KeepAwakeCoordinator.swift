import AppKit
import Foundation
import IOKit.ps
import Infrastructure
import Observability
import Observation
import SecurityKit

/// What started the running Keep Awake session.
enum KeepAwakeSessionTrigger: Equatable, Sendable {
    case manual
    case automation
}

/// Why a Keep Awake session ended.
enum KeepAwakeEndReason: Equatable, Sendable {
    case manual
    case durationElapsed
    case lowBattery
    case teardown
}

/// Owns the Keep Awake session: the power assertions, the countdown, the automation rules, the
/// battery floor, and the optional pointer nudge.
///
/// Every stored property is UI state, so the whole type is `@MainActor`. The system work it
/// drives (assertions, power reads, pointer events) is non-blocking C API.
@Observable
@MainActor
final class KeepAwakeCoordinator {
    /// Preferences. Assigning persists them and re-applies the running session.
    var settings: KeepAwakeSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            // A deliberate preference change earns automation another chance to act, even after
            // a manual stop suppressed it.
            if settings.hasAutomation != oldValue.hasAutomation
                || settings.runningApplicationBundleIdentifiers != oldValue.runningApplicationBundleIdentifiers {
                automationSuppressed = false
            }
            syncWithSettings()
        }
    }

    private(set) var isActive = false
    /// When the running session ends. `nil` while it runs until it is switched off.
    private(set) var endDate: Date?
    private(set) var trigger: KeepAwakeSessionTrigger?
    private(set) var activeConditions: Set<KeepAwakeAutomationCondition> = []
    /// True while the session is held open but its assertions are dropped for a locked screen.
    private(set) var isPausedForScreenLock = false
    /// Accessibility state, refreshed on demand; the pointer nudge needs it.
    private(set) var hasAccessibilityPermission = false

    private let store: any KeepAwakeSettingsStoring
    private let sleepPrevention: any SleepPreventing
    private let powerSource: any PowerSourceReading
    private let externalDisplays: any ExternalDisplayReading
    private let screenLock: any ScreenLockReading
    private let pointer: any PointerNudging
    private let permissions: any PermissionServicing
    private let runningBundleIdentifiers: @MainActor () -> [String]
    private let logger: AppLogger

    private var endTimer: Timer?
    private var batteryTimer: Timer?
    private var pointerTimer: Timer?
    private var screenParametersObserver: NSObjectProtocol?
    private var runningApplicationObservers: [NSObjectProtocol] = []
    private var screenLockObservers: [NSObjectProtocol] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var evaluationWorkItem: DispatchWorkItem?
    private var lastExternalDisplayConnected: Bool?
    private var isScreenLocked = false
    /// Set when the session is stopped by hand while an automation condition still matches, so
    /// automation does not immediately start it again.
    private var automationSuppressed = false

    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    /// How often the battery floor is re-checked while a session runs.
    private static let batteryCheckInterval: TimeInterval = 30

    init(
        store: any KeepAwakeSettingsStoring = UserDefaultsKeepAwakeSettingsStore(),
        sleepPrevention: any SleepPreventing = IOKitSleepPreventionService(),
        powerSource: any PowerSourceReading = IOKitPowerSourceService(),
        externalDisplays: any ExternalDisplayReading = CoreGraphicsExternalDisplayService(),
        screenLock: any ScreenLockReading = CoreGraphicsScreenLockService(),
        pointer: any PointerNudging = CoreGraphicsPointerNudgeService(),
        permissions: any PermissionServicing,
        logger: AppLogger = Loggers.application,
        runningBundleIdentifiers: @escaping @MainActor () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        }
    ) {
        self.store = store
        self.sleepPrevention = sleepPrevention
        self.powerSource = powerSource
        self.externalDisplays = externalDisplays
        self.screenLock = screenLock
        self.pointer = pointer
        self.permissions = permissions
        self.logger = logger
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.settings = store.load()
    }

    // MARK: - Lifecycle

    /// Starts monitoring and, when the preference is on, opens a session for this launch.
    func start() {
        syncWithSettings()
        refreshAccessibilityPermission()
        if settings.startsWithCommandly, isActive == false {
            activate(minutes: settings.duration, trigger: .manual)
        }
    }

    /// Releases every assertion and observer. Safe to call more than once.
    func tearDown() {
        stopAutomationMonitoring()
        deactivate(reason: .teardown)
        sleepPrevention.release()
    }

    // MARK: - Session control

    func toggle() {
        if isActive {
            stopByHand()
        } else {
            activate(minutes: settings.duration, trigger: .manual)
        }
    }

    /// Starts a session by hand. `minutes <= 0` runs until it is switched off.
    func activate(minutes: Int) {
        automationSuppressed = false
        activate(minutes: minutes, trigger: .manual)
    }

    /// Stops the session the way the switch does: automation stays out of the way until its
    /// conditions clear, so switching off does not bounce straight back on.
    func stopByHand() {
        if trigger == .automation || currentMatchingConditions().isEmpty == false {
            automationSuppressed = true
        }
        deactivate(reason: .manual)
    }

    /// Pushes the end of a timed session further out.
    func extend(minutes: Int) {
        guard isActive, let current = endDate else { return }
        let extended = max(current, Date()).addingTimeInterval(TimeInterval(minutes) * 60)
        endDate = extended
        scheduleEnd(at: extended)
    }

    private func activate(minutes: Int, trigger: KeepAwakeSessionTrigger) {
        let minutes = KeepAwakeAutomationRules.sanitizedDuration(minutes)
        endTimer?.invalidate()
        endTimer = nil

        syncScreenLockMonitoring()
        isPausedForScreenLock = isScreenLocked && settings.pausesWhenScreenLocked
        self.trigger = trigger
        if trigger == .manual {
            activeConditions = []
        }
        isActive = true

        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes) * 60)
            endDate = end
            scheduleEnd(at: end)
        } else {
            endDate = nil
        }

        applyRunningState()
    }

    private func deactivate(reason: KeepAwakeEndReason) {
        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        trigger = nil
        activeConditions = []
        isActive = false
        isPausedForScreenLock = false
        stopBatteryWatch()
        stopPointerNudge()
        sleepPrevention.apply(.none)

        if reason == .lowBattery {
            logger.info("Keep Awake stopped: battery reached the configured floor")
        }
    }

    /// Brings assertions, the battery watch, and the pointer nudge in line with the session.
    private func applyRunningState() {
        guard isActive, isPausedForScreenLock == false else {
            sleepPrevention.apply(.none)
            stopBatteryWatch()
            stopPointerNudge()
            return
        }

        sleepPrevention.apply(
            SleepPreventionRequest(
                preventsSystemSleep: true,
                preventsDisplaySleep: settings.allowsDisplaySleep == false
            )
        )
        startBatteryWatch()
        syncPointerNudge()
    }

    private func scheduleEnd(at date: Date) {
        endTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.sessionTimerDidFire()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func sessionTimerDidFire() {
        // A timed manual session hands over to automation when a rule still matches, instead of
        // dropping the assertions the rule would take again a moment later.
        guard continueAutomaticallyIfNeeded() == false else { return }
        deactivate(reason: .durationElapsed)
    }

    private func continueAutomaticallyIfNeeded() -> Bool {
        guard trigger == .manual, automationSuppressed == false, batteryAllowsSession() else {
            return false
        }
        let matches = currentMatchingConditions()
        guard matches.isEmpty == false else { return false }
        activeConditions = matches
        activate(minutes: 0, trigger: .automation)
        return true
    }

    // MARK: - Preferences

    private func syncWithSettings() {
        syncAutomationMonitoring()
        applyRunningState()
    }

    /// Replaces the watched bundle identifiers for the running-apps rule.
    func setRunningApplicationBundleIdentifiers(_ identifiers: [String]) {
        settings.runningApplicationBundleIdentifiers =
            KeepAwakeAutomationRules.sanitizedBundleIdentifiers(identifiers)
    }

    // MARK: - Automation monitoring

    private func syncAutomationMonitoring() {
        syncScreenLockMonitoring()
        setScreenParameterMonitoring(settings.startsWithExternalDisplay)
        setPowerSourceMonitoring(settings.startsWhenConnectedToPower)
        setRunningApplicationMonitoring(
            settings.startsWithRunningApplications
                && settings.runningApplicationBundleIdentifiers.isEmpty == false
        )
        evaluateAutomation()
    }

    private func stopAutomationMonitoring() {
        evaluationWorkItem?.cancel()
        evaluationWorkItem = nil
        setScreenParameterMonitoring(false)
        setPowerSourceMonitoring(false)
        setRunningApplicationMonitoring(false)

        let center = DistributedNotificationCenter.default()
        for observer in screenLockObservers { center.removeObserver(observer) }
        screenLockObservers.removeAll()
        isScreenLocked = false
        isPausedForScreenLock = false
        activeConditions = []
    }

    private func setScreenParameterMonitoring(_ enabled: Bool) {
        if enabled {
            guard screenParametersObserver == nil else { return }
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    // Displays settle a moment after the notification; read the list once it has.
                    self.scheduleEvaluation(after: 0.35)
                }
            }
        } else if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
            lastExternalDisplayConnected = nil
        }
    }

    private func setPowerSourceMonitoring(_ enabled: Bool) {
        if enabled {
            guard powerSourceRunLoopSource == nil else { return }
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let coordinator = Unmanaged<KeepAwakeCoordinator>.fromOpaque(context)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        coordinator.scheduleEvaluation(after: 0.1)
                    }
                }
            }, context)?.takeRetainedValue()
            guard let source else {
                logger.error("Keep Awake could not observe power-source changes")
                return
            }
            powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            self.powerSourceRunLoopSource = nil
        }
    }

    private func setRunningApplicationMonitoring(_ enabled: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if enabled {
            guard runningApplicationObservers.isEmpty else { return }
            let handler: (Notification) -> Void = { _ in
                MainActor.assumeIsolated {
                    self.scheduleEvaluation(after: 0.1)
                }
            }
            runningApplicationObservers = [
                center.addObserver(
                    forName: NSWorkspace.didLaunchApplicationNotification,
                    object: nil,
                    queue: .main,
                    using: handler
                ),
                center.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main,
                    using: handler
                ),
            ]
        } else {
            guard runningApplicationObservers.isEmpty == false else { return }
            for observer in runningApplicationObservers { center.removeObserver(observer) }
            runningApplicationObservers.removeAll()
        }
    }

    private func syncScreenLockMonitoring() {
        let center = DistributedNotificationCenter.default()
        if settings.pausesWhenScreenLocked {
            guard screenLockObservers.isEmpty else { return }
            screenLockObservers = [
                center.addObserver(
                    forName: Self.screenLockedNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated { self.screenLockDidChange(locked: true) }
                },
                center.addObserver(
                    forName: Self.screenUnlockedNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated { self.screenLockDidChange(locked: false) }
                },
            ]
            isScreenLocked = screenLock.isScreenLocked()
            syncSessionWithScreenLock()
        } else {
            guard screenLockObservers.isEmpty == false else { return }
            for observer in screenLockObservers { center.removeObserver(observer) }
            screenLockObservers.removeAll()
            isScreenLocked = false
            syncSessionWithScreenLock()
        }
    }

    private func screenLockDidChange(locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        syncSessionWithScreenLock()
        evaluateAutomation()
    }

    private func syncSessionWithScreenLock() {
        guard isActive else {
            isPausedForScreenLock = false
            return
        }
        let shouldPause = isScreenLocked && settings.pausesWhenScreenLocked
        guard shouldPause != isPausedForScreenLock else { return }
        isPausedForScreenLock = shouldPause

        if shouldPause {
            applyRunningState()
            return
        }

        // Resuming: a countdown that ran out while the screen was locked ends the session now.
        if let endDate, endDate <= Date() {
            sessionTimerDidFire()
            return
        }
        if trigger == .automation, currentMatchingConditions().isEmpty {
            deactivate(reason: .manual)
            return
        }
        applyRunningState()
    }

    private func scheduleEvaluation(after delay: TimeInterval) {
        evaluationWorkItem?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                self.evaluationWorkItem = nil
                self.evaluateAutomation()
            }
        }
        evaluationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluateAutomation() {
        let matches = currentMatchingConditions()

        if automationSuppressed {
            if matches.isEmpty { automationSuppressed = false }
            if trigger == .automation { deactivate(reason: .manual) }
            return
        }

        // A locked screen freezes automation: the session state resumes from the unlock.
        if isScreenLocked, settings.pausesWhenScreenLocked {
            if trigger == .automation { activeConditions = matches }
            return
        }

        if trigger == .automation { activeConditions = matches }

        switch KeepAwakeAutomationRules.action(
            matchingConditions: matches,
            sessionActive: isActive,
            automaticSessionActive: isActive && trigger == .automation
        ) {
        case .none:
            break
        case .activate:
            guard batteryAllowsSession() else { return }
            activeConditions = matches
            activate(minutes: 0, trigger: .automation)
        case .deactivate:
            deactivate(reason: .manual)
        }
    }

    private func currentMatchingConditions() -> Set<KeepAwakeAutomationCondition> {
        let externalDisplayConnected: Bool
        if settings.startsWithExternalDisplay {
            if let current = externalDisplays.hasExternalDisplay() {
                lastExternalDisplayConnected = current
            }
            externalDisplayConnected = lastExternalDisplayConnected ?? false
        } else {
            externalDisplayConnected = false
        }

        let connectedToPower = settings.startsWhenConnectedToPower
            && (powerSource.snapshot().map { $0.isOnBattery == false } ?? false)

        let applicationsRunning: Bool
        if settings.startsWithRunningApplications,
           settings.runningApplicationBundleIdentifiers.isEmpty == false {
            applicationsRunning = KeepAwakeAutomationRules.selectedApplicationsAreRunning(
                selectedBundleIdentifiers: settings.runningApplicationBundleIdentifiers,
                runningBundleIdentifiers: runningBundleIdentifiers()
            )
        } else {
            applicationsRunning = false
        }

        return KeepAwakeAutomationRules.matchingConditions(
            externalDisplayEnabled: settings.startsWithExternalDisplay,
            externalDisplayConnected: externalDisplayConnected,
            powerEnabled: settings.startsWhenConnectedToPower,
            connectedToPower: connectedToPower,
            runningApplicationsEnabled: settings.startsWithRunningApplications,
            selectedApplicationsRunning: applicationsRunning
        )
    }

    // MARK: - Battery floor

    private func batteryAllowsSession() -> Bool {
        KeepAwakeAutomationRules.batteryAllowsSession(
            floorPercent: settings.batteryFloorPercent,
            power: currentPowerReading()
        )
    }

    private func currentPowerReading() -> KeepAwakeAutomationRules.PowerReadingInput? {
        powerSource.snapshot().map {
            KeepAwakeAutomationRules.PowerReadingInput(
                isOnBattery: $0.isOnBattery,
                percentRemaining: $0.percentRemaining
            )
        }
    }

    private func startBatteryWatch() {
        guard settings.batteryFloorPercent > 0 else {
            stopBatteryWatch()
            return
        }
        guard batteryTimer == nil else {
            checkBatteryFloor()
            return
        }
        let timer = Timer(timeInterval: Self.batteryCheckInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.checkBatteryFloor() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        checkBatteryFloor()
    }

    private func stopBatteryWatch() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func checkBatteryFloor() {
        guard isActive else { return }
        guard KeepAwakeAutomationRules.batteryRequiresStop(
            floorPercent: settings.batteryFloorPercent,
            power: currentPowerReading()
        ) else {
            return
        }
        automationSuppressed = true
        deactivate(reason: .lowBattery)
    }

    /// The battery percentage right now, for the panel's low-battery caption.
    var batteryPercentRemaining: Int? {
        powerSource.snapshot()?.percentRemaining
    }

    // MARK: - Pointer nudge

    private func syncPointerNudge() {
        guard isActive, isPausedForScreenLock == false, settings.nudgesPointer else {
            stopPointerNudge()
            return
        }
        let minutes = KeepAwakeAutomationRules.sanitizedPointerNudgeInterval(
            settings.pointerNudgeInterval
        )
        let interval = TimeInterval(minutes) * 60
        if pointerTimer?.timeInterval == interval { return }

        stopPointerNudge()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.nudgePointer() }
        }
        timer.tolerance = min(10, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerNudge() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func nudgePointer() {
        guard isActive, settings.nudgesPointer else {
            stopPointerNudge()
            return
        }
        if pointer.nudge() == false {
            refreshAccessibilityPermission()
        }
    }

    // MARK: - Accessibility

    /// Re-reads Accessibility state without prompting.
    func refreshAccessibilityPermission() {
        Task { [permissions] in
            let state = await permissions.state(for: .accessibility)
            hasAccessibilityPermission = state == .authorized
        }
    }

    /// Asks for Accessibility after the user chose the pointer nudge.
    func requestAccessibilityPermission() {
        Task { [permissions] in
            let state = await permissions.request(.accessibility)
            hasAccessibilityPermission = state == .authorized
        }
    }

    /// True when the pointer nudge is on but cannot post events yet.
    var pointerNudgeNeedsAccessibility: Bool {
        settings.nudgesPointer && hasAccessibilityPermission == false
    }
}
