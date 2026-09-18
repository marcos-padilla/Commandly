@testable import Commandly
import SystemCompanionKit
import Foundation
import Infrastructure
import Testing

@MainActor struct MenuControllerTests {
    /// Controls the clock `CompanionMenuController` reads, so request deadlines never depend on
    /// real elapsed time.
    ///
    /// These tests previously built deadlines from `ContinuousClock.now` while the controller
    /// compared them against its own real-time reads. A parallel full-suite run can starve the
    /// main actor for seconds, so a request could exceed its budget between the deadline being
    /// computed and the controller checking it, and `handle` would return
    /// `.failure(.timedOut)` instead of the expected reply.
    ///
    /// The clock is never advanced here, so every `now()` the controller performs returns the same
    /// instant and `now() < deadline` is decided by arithmetic rather than by machine load. A test
    /// that needs an expired deadline derives it from this clock too, so it is deterministic in the
    /// other direction. Advancing time on purpose is covered by
    /// ``handleExpiryIsCheckedSynchronouslyWithInjectedClock()``, which drives its own clock.
    private let clock = MenuClock()
    private func setup() -> (CompanionMenuController, CompanionMenuLease, MenuWorker, MenuEnvironment, UUID) {
        let lease = CompanionMenuLease(); let worker = MenuWorker(); let environment = MenuEnvironment(lease)
        let controller = CompanionMenuController(lease: lease, worker: worker, environment: environment,
                                                 now: { [clock] in clock.now() })
        let session = UUID(); controller.connect(session: session)
        return (controller, lease, worker, environment, session)
    }
    private var deadline: ContinuousClock.Instant { clock.now().advanced(by: .seconds(5)) }
    @Test func constructionAndDisabledReadsNeverObserveOrCapture() async {
        let (controller, _, worker, environment, session) = setup()
        #expect(environment.starts == 0)
        #expect(await controller.handle(.snapshot, session: session, deadline: deadline) == .failure(.disabled))
        #expect(await worker.captures == 0)
    }
    @Test func explicitEnableSnapshotAndSingleUseInvoke() async throws {
        let (controller, _, worker, environment, session) = setup()
        #expect(await controller.handle(.setEnabled(true), session: session, deadline: deadline) == .enabled(true))
        #expect(environment.starts == 1)
        guard case .snapshot(let result) = await controller.handle(.snapshot, session: session, deadline: deadline) else { Issue.record("snapshot missing"); return }
        let item = try #require(result.items.first)
        #expect(item.handle.session == session && item.title == "Generated Action")
        #expect(await controller.handle(.invoke(item.handle), session: session, deadline: deadline) == .invoked(.accepted))
        #expect(await controller.handle(.invoke(item.handle), session: session, deadline: deadline) == .failure(.expired))
        #expect(await worker.invocations.count == 1)
        await controller.disconnect()
    }
    @Test func wrongSessionAndForeignHandleNeverInvoke() async throws {
        let (controller, _, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        _ = await controller.handle(.snapshot, session: session, deadline: deadline)
        #expect(await controller.handle(.invoke(.init(session: UUID(), target: UUID())), session: session, deadline: deadline) == .failure(.stale))
        #expect(await controller.handle(.snapshot, session: UUID(), deadline: deadline) == .failure(.disconnected))
        #expect(await worker.invocations.isEmpty)
        await controller.disconnect()
    }
    @Test func appSwitchInvalidatesAndRefreshDoesNotRetargetOpenSession() async {
        let (controller, lease, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        _ = await controller.handle(.snapshot, session: session, deadline: deadline)
        lease.activateExternal(.init(processIdentifier: 101, birth: .init(seconds: 2, microseconds: 0), executablePath: "/generated/other", bundleIdentifier: "generated.other"))
        #expect(await controller.handle(.snapshot, session: session, deadline: deadline) == .failure(.stale))
        #expect(await worker.captures == 1)
        _ = await controller.handle(.release, session: session, deadline: deadline)
        let reopened = await controller.handle(.snapshot, session: session, deadline: deadline)
        guard case .snapshot(let fresh) = reopened else { Issue.record("fresh open missing: \(reopened)"); return }
        #expect(fresh.bundleIdentifier == "generated.other")
        await controller.disconnect()
    }
    @Test func lateCaptureCannotOutliveSynchronousRevocation() async {
        let (controller, _, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        await worker.hold()
        let task = Task { await controller.handle(.snapshot, session: session, deadline: deadline) }
        await worker.waitForCapture(); controller.revoke(); await worker.resume()
        #expect(await task.value == .failure(.disconnected))
        #expect(await worker.invocations.isEmpty)
    }
    @Test func lateCaptureCannotOutliveCancellation() async {
        let (controller, _, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        await worker.hold()
        let task = Task { await controller.handle(.snapshot, session: session, deadline: deadline) }
        await worker.waitForCapture(); task.cancel(); await worker.resume()
        #expect(await task.value == .failure(.canceled))
        await controller.disconnect()
    }
    @Test func permissionRevocationStopsObserverAndRequiresReconnect() async {
        let (controller, lease, worker, environment, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        await worker.set(failure: .permissionDenied)
        #expect(await controller.handle(.snapshot, session: session, deadline: deadline) == .failure(.permissionDenied))
        #expect(throws: CompanionAppMenuError.disconnected) { _ = try lease.snapshot(session: session) }
        #expect(environment.stops >= 2)
    }
    @Test func lockAndSameProcessReactivationRevokeContexts() throws {
        let lease = CompanionMenuLease(); let session = UUID(); lease.connect(session: session)
        try lease.setEnabled(true, session: session); lease.activateExternal(fixtureApplication)
        let context = try lease.snapshot(session: session)
        lease.activateExternal(fixtureApplication)
        #expect(throws: CompanionAppMenuError.stale) { try lease.validate(context) }
        lease.setLocked()
        #expect(throws: CompanionAppMenuError.locked) { _ = try lease.snapshot(session: session) }
        try lease.setEnabled(false, session: session)
    }
    @Test func snapshotBoundsAndExpiredRequestFailBeforeInvocation() async {
        let (controller, _, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        await worker.set(values: (0...500).map { candidate("Action \($0)") })
        #expect(await controller.handle(.snapshot, session: session, deadline: deadline) == .failure(.tooLarge))
        #expect(await controller.handle(.snapshot, session: session, deadline: clock.now().advanced(by: .seconds(-1))) == .failure(.timedOut))
        #expect(await worker.captures == 1)
        await controller.disconnect()
    }
    @Test func handleExpiryIsCheckedSynchronouslyWithInjectedClock() async throws {
        let lease = CompanionMenuLease(); let worker = MenuWorker(); let environment = MenuEnvironment(lease); let clock = MenuClock()
        let controller = CompanionMenuController(lease: lease, worker: worker, environment: environment, now: { clock.now() })
        let session = UUID(); controller.connect(session: session)
        let deadline = clock.now().advanced(by: .seconds(60))
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        guard case .snapshot(let result) = await controller.handle(.snapshot, session: session, deadline: deadline) else { Issue.record("snapshot missing"); return }
        let handle = try #require(result.items.first?.handle); clock.advance(.seconds(31))
        #expect(await controller.handle(.invoke(handle), session: session, deadline: deadline) == .failure(.expired))
        #expect(await worker.invocations.isEmpty)
        await controller.disconnect()
    }
    @Test func uncertainNativeOutcomeConsumesTheHandleWithoutRetry() async throws {
        let (controller, _, worker, _, session) = setup()
        _ = await controller.handle(.setEnabled(true), session: session, deadline: deadline)
        guard case .snapshot(let result) = await controller.handle(.snapshot, session: session, deadline: deadline) else { Issue.record("snapshot missing"); return }
        let handle = try #require(result.items.first?.handle); await worker.set(outcome: .outcomeUnknown)
        #expect(await controller.handle(.invoke(handle), session: session, deadline: deadline) == .invoked(.outcomeUnknown))
        #expect(await controller.handle(.invoke(handle), session: session, deadline: deadline) == .failure(.expired))
        #expect(await worker.invocations.count == 1)
        await controller.disconnect()
    }
}
