import Foundation
import IOKit.pwr_mgt
import Infrastructure

/// IOKit power-assertion adapter for keep-awake sessions.
///
/// `@unchecked Sendable`: the two assertion identifiers are the whole mutable state and every
/// access runs inside `lock`. IOKit's assertion calls are themselves thread-safe.
final class IOKitSleepPreventionService: SleepPreventing, @unchecked Sendable {
    private let lock = NSLock()
    private var systemAssertion: IOPMAssertionID?
    private var displayAssertion: IOPMAssertionID?

    private let systemReason: String
    private let displayReason: String

    init(
        systemReason: String = "Commandly Keep Awake is holding off system sleep",
        displayReason: String = "Commandly Keep Awake is holding off display sleep"
    ) {
        self.systemReason = systemReason
        self.displayReason = displayReason
    }

    deinit {
        releaseLocked()
    }

    func apply(_ request: SleepPreventionRequest) {
        lock.lock()
        defer { lock.unlock() }

        systemAssertion = reconcile(
            systemAssertion,
            wanted: request.preventsSystemSleep,
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            reason: systemReason
        )
        displayAssertion = reconcile(
            displayAssertion,
            wanted: request.preventsDisplaySleep,
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            reason: displayReason
        )
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        releaseLocked()
    }

    /// Takes or drops one assertion so the held state matches `wanted`, returning the new id.
    private func reconcile(
        _ current: IOPMAssertionID?,
        wanted: Bool,
        type: String,
        reason: String
    ) -> IOPMAssertionID? {
        switch (current, wanted) {
        case (let held?, false):
            IOPMAssertionRelease(held)
            return nil
        case (nil, true):
            var identifier = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &identifier
            )
            return status == kIOReturnSuccess ? identifier : nil
        case (_, _):
            return current
        }
    }

    private func releaseLocked() {
        if let systemAssertion {
            IOPMAssertionRelease(systemAssertion)
            self.systemAssertion = nil
        }
        if let displayAssertion {
            IOPMAssertionRelease(displayAssertion)
            self.displayAssertion = nil
        }
    }
}
