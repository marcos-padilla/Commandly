import Foundation
import Infrastructure
import os

/// A verified bound listener creates an inert driver. No native access occurs before configure.
public struct CompanionKeyboardTriggerFactory: Sendable {
    private let create: @MainActor @Sendable () -> any CompanionKeyboardTriggerHandling
    public init(create: @escaping @MainActor @Sendable () -> any CompanionKeyboardTriggerHandling) { self.create = create }
    @MainActor public func make() -> any CompanionKeyboardTriggerHandling { create() }
    public static var native: Self {
        let authority = CompanionKeyboardHardwareAuthority()
        return Self { CompanionKeyboardController(driver: NativeCompanionKeyboardDriver(authority: authority)) }
    }
}
/// Foundation invalidation revokes authorization synchronously, before scheduling native teardown.
final class CompanionKeyboardTriggerBindingOwner: Sendable {
    private struct State: Sendable { var handler: (any CompanionKeyboardTriggerHandling)?; var revoked = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func install(_ handler: any CompanionKeyboardTriggerHandling) -> Bool {
        let accepted = state.withLock { value in
            guard !value.revoked, value.handler == nil else { return false }; value.handler = handler; return true
        }
        if !accepted { handler.revoke() }
        return accepted
    }
    func revoke() {
        let handler = state.withLock { value in
            value.revoked = true; let old = value.handler; value.handler = nil; return old
        }
        handler?.revoke()
        if let handler { Task { await handler.cleanupAfterRevocation() } }
    }
}
