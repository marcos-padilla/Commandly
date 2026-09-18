import AppCore
import Foundation
import Infrastructure
import Synchronization
@testable import Commandly

nonisolated final class ResolutionTestClock: AppCore.Clock {
    private let value = Mutex(ContinuousClock().now)
    func monotonicTime() -> ContinuousClock.Instant { value.withLock { $0 } }
    func advance(seconds: Int) { value.withLock { $0 = $0.advanced(by: .seconds(seconds)) } }
}

nonisolated enum ResolutionTestData {
    static let identity = DisplayHardwareIdentity(displayID: 11, uuid: "fixture-display-one", vendor: 1, model: 2, serial: 3)
    static let original = DisplayModeFingerprint(ioID: 1, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800, refreshRate: 60, flags: 0, isUsable: true)
    static let highDensity = DisplayModeFingerprint(ioID: 2, width: 1280, height: 800, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60, flags: 0, isUsable: true)
    static let lowDensity = DisplayModeFingerprint(ioID: 3, width: 1280, height: 800, pixelWidth: 1280, pixelHeight: 800, refreshRate: 60, flags: 1, isUsable: true)
    static let fastRefresh = DisplayModeFingerprint(ioID: 4, width: 1280, height: 800, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 75, flags: 0, isUsable: true)
    static let modes = [original, highDensity, lowDensity, fastRefresh]
    static func hardware(current: DisplayModeFingerprint = original, identity: DisplayHardwareIdentity = identity,
                         isMirrored: Bool = false) -> DisplayHardwareSnapshot {
        .init(displays: [.init(identity: identity, name: "Fixture Display", isActive: true, isMirrored: isMirrored,
            originX: 0, originY: 0, current: current, modes: modes, modesAreTruncated: false)])
    }
    static func selection(_ catalog: DisplayResolutionCatalog, pixelWidth: Int = 2560, refreshRate: Double = 60) -> DisplayResolutionSelection? {
        guard let display = catalog.displays.first,
              let mode = display.modes.first(where: { $0.logicalWidth == 1280 && $0.pixelWidth == pixelWidth && $0.refreshRate == refreshRate }) else { return nil }
        return .init(catalogID: catalog.id, displayID: display.id, modeID: mode.id)
    }
}

actor ResolutionTestDriver {
    private(set) var hardware: DisplayHardwareSnapshot
    private(set) var snapshotCount = 0
    private(set) var changes: [DisplayConfigurationChange] = []
    private var nextFailure: DisplayResolutionError?
    private var nextSubstitution: DisplayModeFingerprint?
    private var failAfterMutation = false
    private var shouldPause = false
    private var paused = false
    private var gate: CheckedContinuation<Void, Never>?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    init(hardware: DisplayHardwareSnapshot = ResolutionTestData.hardware()) { self.hardware = hardware }
    func snapshot() -> DisplayHardwareSnapshot { snapshotCount += 1; return hardware }
    func configure(_ change: DisplayConfigurationChange) async throws -> DisplayHardwareSnapshot {
        guard hardware.hasSameConfiguration(as: change.expected), hardware.display(change.display) != nil else {
            throw DisplayResolutionError.configurationChanged
        }
        changes.append(change)
        if let failure = nextFailure, failAfterMutation == false { nextFailure = nil; throw failure }
        hardware = replacingMode(nextSubstitution ?? change.mode, for: change.display)
        nextSubstitution = nil
        if shouldPause {
            shouldPause = false; paused = true
            let waiters = pauseWaiters; pauseWaiters = []; waiters.forEach { $0.resume() }
            await withCheckedContinuation { gate = $0 }
            paused = false
        }
        if let failure = nextFailure { nextFailure = nil; failAfterMutation = false; throw failure }
        return hardware
    }
    func setHardware(_ value: DisplayHardwareSnapshot) { hardware = value }
    func failNext(_ error: DisplayResolutionError, afterMutation: Bool = false) { nextFailure = error; failAfterMutation = afterMutation }
    func substituteNext(_ mode: DisplayModeFingerprint) { nextSubstitution = mode }
    func suspendNextChange() { shouldPause = true }
    func waitForPausedChange() async {
        if paused { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }
    func resumeChange() { gate?.resume(); gate = nil }
    private func replacingMode(_ mode: DisplayModeFingerprint, for identity: DisplayHardwareIdentity) -> DisplayHardwareSnapshot {
        .init(displays: hardware.displays.map { record in
            .init(identity: record.identity, name: record.name, isActive: record.isActive, isMirrored: record.isMirrored,
                originX: record.originX, originY: record.originY, current: record.identity == identity ? mode : record.current,
                modes: record.modes, modesAreTruncated: record.modesAreTruncated)
        })
    }
}
extension ResolutionTestDriver: DisplayConfigurationDriving {}

@MainActor
final class ResolutionTestTicker: DisplayResolutionTickScheduling {
    private(set) var callback: (@MainActor () -> Void)?
    func start(_ action: @escaping @MainActor () -> Void) { callback = action }
    func cancel() { callback = nil }
    func fire() { callback?() }
}
@MainActor
final class ResolutionTestEnvironment: DisplayResolutionEnvironmentObserving {
    private(set) var callback: (@MainActor () -> Void)?
    func start(_ action: @escaping @MainActor () -> Void) { callback = action }
    func stop() { callback = nil }
}
@MainActor
final class ResolutionTestWindow: DisplayResolutionWindowPresenting {
    private(set) var presentations = 0
    private(set) var repositionings = 0
    private(set) var closes = 0
    func present(_ model: DisplayResolutionCoordinator) { presentations += 1 }
    func ensureVisible() { repositionings += 1 }
    func close() { closes += 1 }
}
