import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

@MainActor struct FinderPathReaderTests {
    @Test func tokenRevalidatesOnceAndRejectsReplayOrForgedPath() async throws {
        let probe = FinderReaderTestProbe(); let reader = FinderPathReader(probe: probe)
        let snapshot = try await reader.capture()
        let forged = FinderPathSnapshot(id: snapshot.id, path: "/generated/other", origin: snapshot.origin)
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(forged) }
        try await reader.validate(snapshot)
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(snapshot) }
        #expect(await probe.reads == 2)
    }
    @Test(arguments: [0, 1, 2, 3, 4]) func changesToWindowSelectionPathOrProcessRejectCopy(_ dimension: Int) async throws {
        let probe = FinderReaderTestProbe(); let reader = FinderPathReader(probe: probe)
        let snapshot = try await reader.capture()
        await probe.change(dimension)
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(snapshot) }
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(snapshot) }
    }
    @Test func expiryUsesInjectedDeadlineAndDoesNotReadAgain() async throws {
        let clock = FinderReaderTestClock(); let probe = FinderReaderTestProbe()
        let reader = FinderPathReader(probe: probe, now: { clock.now })
        let snapshot = try await reader.capture(); clock.advance(.seconds(10))
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(snapshot) }
        #expect(await probe.reads == 1)
    }
    @Test func newerCaptureRejectsOldCompletionWithoutDestroyingNewLease() async throws {
        let probe = FinderReaderTestProbe(); let reader = FinderPathReader(probe: probe)
        await probe.holdNextRead()
        let old = Task { try await reader.capture() }; await probe.waitForHeldRead()
        let new = try await reader.capture()
        await probe.release()
        await #expect(throws: FinderPathError.changedContext) { try await old.value }
        try await reader.validate(new)
    }
    @Test func alreadyCancelledCaptureDoesNotDiscardCurrentLease() async throws {
        let probe = FinderReaderTestProbe(); let reader = FinderPathReader(probe: probe)
        let snapshot = try await reader.capture()
        let cancelled = Task { try await reader.capture() }; cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try await reader.validate(snapshot)
        #expect(await probe.reads == 2)
    }
    @Test func cancellationConsumesReturnedTokenWithoutFurtherRead() async throws {
        let probe = FinderReaderTestProbe(); let reader = FinderPathReader(probe: probe)
        let snapshot = try await reader.capture()
        let task = Task { try await reader.validate(snapshot) }; task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: FinderPathError.changedContext) { try await reader.validate(snapshot) }
        #expect(await probe.reads == 1)
    }
}

private actor FinderReaderTestProbe: FinderPathProbing {
    private var context = FinderPathContext(process: .init(pid: 123, startTime: .init(seconds: 1, microseconds: 0)),
                                            windowID: 42, selectionReference: Data([1]), path: "/generated/item")
    private(set) var reads = 0
    private var holdsNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func authorization(allowPrompt: Bool) -> FinderPathAuthorization { .authorized }
    func read() async -> FinderPathContext {
        reads += 1; let result = context
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
        }
        return result
    }
    func change(_ dimension: Int) {
        context = .init(process: .init(pid: dimension == 3 ? 124 : 123, startTime: .init(seconds: 1, microseconds: dimension == 4 ? 1 : 0)),
                        windowID: dimension == 0 ? 43 : 42, selectionReference: dimension == 1 ? nil : Data([1]),
                        path: dimension == 2 ? "/generated/renamed" : "/generated/item")
    }
    func holdNextRead() { holdsNext = true }
    func waitForHeldRead() async { if held == nil { await withCheckedContinuation { waiter = $0 } } }
    func release() { held?.resume(); held = nil }
}
nonisolated private final class FinderReaderTestClock: Sendable {
    private let value = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { value.withLock { $0 } }
    func advance(_ duration: Duration) { value.withLock { $0 = $0.advanced(by: duration) } }
}
