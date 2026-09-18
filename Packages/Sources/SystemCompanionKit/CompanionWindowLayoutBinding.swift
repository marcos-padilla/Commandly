import Foundation
import Infrastructure
import os

/// Built only from the authenticated incoming bind callback's kernel PID. No wire value is accepted.
public struct CompanionWindowLayoutFactory: Sendable {
    private let create: @MainActor @Sendable (Int32) -> any CompanionWindowLayoutHandling
    public init(create: @escaping @MainActor @Sendable (Int32) -> any CompanionWindowLayoutHandling) { self.create = create }
    @MainActor public func make(authenticatedMainProcessIdentifier: Int32) -> any CompanionWindowLayoutHandling {
        create(authenticatedMainProcessIdentifier)
    }
    /// Inert until `make` is called, and still performs no observation or AX until explicit enable/Apply.
    public static var native: Self {
        Self { pid in
            let lease = CompanionWindowLayoutLease()
            let environment = NativeCompanionWindowLayoutEnvironment(lease: lease, authenticatedMainProcessIdentifier: pid)
            let worker = NativeCompanionWindowLayoutWorker(lease: lease, environment: environment)
            return CompanionWindowLayoutController(lease: lease, worker: worker, observer: environment)
        }
    }
}

/// Revoke synchronously in Foundation callbacks, before actor teardown can be delayed by native work.
/// A late factory result is rejected and immediately revoked; a second handler cannot replace the first.
final class CompanionWindowLayoutBindingOwner: Sendable {
    private struct State: Sendable {
        var handler: (any CompanionWindowLayoutHandling)?
        var revoked = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func install(_ handler: any CompanionWindowLayoutHandling) -> Bool {
        let accepted = state.withLock {
            guard $0.revoked == false, $0.handler == nil else { return false }
            $0.handler = handler
            return true
        }
        if accepted == false { handler.revoke() }
        return accepted
    }
    func revoke() {
        let handler = state.withLock { value in
            value.revoked = true
            let old = value.handler; value.handler = nil
            return old
        }
        handler?.revoke()
        if let handler { Task { await handler.cleanupAfterRevocation() } }
    }
}
