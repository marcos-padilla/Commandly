import Foundation
import Infrastructure

/// Keeps one short-lived token; a second capture invalidates the previous result.
actor FinderPathReader: FinderPathReading {
    private let probe: any FinderPathProbing
    private let now: @Sendable () -> ContinuousClock.Instant
    private var generation = 0
    private var lease: (snapshot: FinderPathSnapshot, context: FinderPathContext, expires: ContinuousClock.Instant)?
    init(probe: any FinderPathProbing, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.probe = probe; self.now = now
    }
    func authorization(allowPrompt: Bool) async throws -> FinderPathAuthorization {
        try Task.checkCancellation()
        let state = try await probe.authorization(allowPrompt: allowPrompt)
        try Task.checkCancellation()
        return state
    }
    func capture() async throws -> FinderPathSnapshot {
        try Task.checkCancellation()
        generation &+= 1; let id = generation
        lease = nil
        let context = try await probe.read()
        try Task.checkCancellation()
        guard generation == id else { throw FinderPathError.changedContext }
        let snapshot = FinderPathSnapshot(id: UUID(), path: context.path, origin: context.origin)
        lease = (snapshot, context, now().advanced(by: .seconds(10)))
        return snapshot
    }
    func validate(_ snapshot: FinderPathSnapshot) async throws {
        guard let pending = lease, pending.snapshot == snapshot else { throw FinderPathError.changedContext }
        let id = generation
        lease = nil // Consumed even on expiry, denial, cancellation or native failure; no replay.
        try Task.checkCancellation()
        guard now() < pending.expires else { throw FinderPathError.changedContext }
        let current = try await probe.read()
        try Task.checkCancellation()
        guard generation == id, current == pending.context, now() < pending.expires else { throw FinderPathError.changedContext }
    }
}
