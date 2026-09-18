import os

/// Retains exactly one Foundation-accepted connection, including while its delegate returns.
///
/// Foundation delivers a non-Sendable NSXPCConnection on its own callback queue; transferring it to
/// an actor would violate Swift isolation. The OS lock's explicit unchecked-state API is used only
/// for this native ownership boundary. Resource never escapes through this API. All stored-resource
/// access is serialized; activation finishes before close can remove it. Close removes ownership
/// under the lock and calls invalidate outside it. Native activation callbacks must only enqueue
/// cleanup and must not synchronously call back into this owner. Test resources exercise the same lease.
/// This is not an unchecked Sendable conformance for NSXPCConnection or a mutable peer policy.
final class CompanionBoundConnectionOwner<Resource>: Sendable {
    private struct State { var invalid = false; var resource: Resource? }
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let activate: @Sendable (Resource) -> Void
    private let close: @Sendable (Resource) -> Void
    init(activate: @escaping @Sendable (Resource) -> Void, close: @escaping @Sendable (Resource) -> Void) {
        self.activate = activate; self.close = close
    }
    func accept(_ resource: Resource) -> Bool {
        let accepted = state.withLockUnchecked { value in
            guard value.invalid == false, value.resource == nil else { return false }
            value.resource = resource
            activate(resource)
            return true
        }
        if accepted == false { close(resource) }
        return accepted
    }
    func invalidate() {
        let old = state.withLockUnchecked { value in
            value.invalid = true
            let old = value.resource; value.resource = nil
            return old
        }
        if let old { close(old) }
    }
}
