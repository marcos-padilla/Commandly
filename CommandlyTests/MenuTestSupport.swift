@testable import Commandly
import SystemCompanionKit
import Foundation
import Infrastructure
import os

func candidate(_ title: String = "Generated Action", enabled: Bool = true) -> CompanionMenuCandidate {
    .init(path: [.init(index: 0, role: "AXMenuBarItem", title: "Generated Menu"),
                 .init(index: 0, role: "AXMenu", title: ""),
                 .init(index: 1, role: "AXMenuItem", title: title, identifier: "generated.action", shortcut: "g:0:5:0")], enabled: enabled)
}
let fixtureApplication = CompanionMenuApplicationIdentity(processIdentifier: 100, birth: .init(seconds: 1, microseconds: 0), executablePath: "/generated/fixture", bundleIdentifier: "generated.fixture")

@MainActor final class MenuEnvironment: CompanionMenuEnvironment {
    let lease: CompanionMenuLease
    var starts = 0; var stops = 0
    init(_ lease: CompanionMenuLease) { self.lease = lease }
    func start() { starts += 1; lease.activateExternal(fixtureApplication) }
    func stop() { stops += 1 }
    func validate(_ context: CompanionMenuContext) throws { try lease.validate(context) }
}
actor MenuWorker: CompanionMenuWorking {
    var values = [candidate()]
    var captures = 0; var invocations: [UUID] = []; var clears = 0
    var failure: CompanionAppMenuError?
    var outcome: CompanionMenuInvocationOutcome = .accepted
    var holds = false
    var pending: CheckedContinuation<Void, Never>?
    var observed: CheckedContinuation<Void, Never>?
    func set(values: [CompanionMenuCandidate]) { self.values = values }
    func set(failure: CompanionAppMenuError) { self.failure = failure }
    func set(outcome: CompanionMenuInvocationOutcome) { self.outcome = outcome }
    func hold() { holds = true }
    func waitForCapture() async { if captures > 0 { return }; await withCheckedContinuation { observed = $0 } }
    func resume() { pending?.resume(); pending = nil }
    func snapshot(context: CompanionMenuContext, deadline: ContinuousClock.Instant) async throws -> [CompanionMenuCandidate] {
        captures += 1; observed?.resume(); observed = nil
        if holds { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }
        return values
    }
    func invoke(id: UUID, context: CompanionMenuContext, deadline: ContinuousClock.Instant) throws -> CompanionMenuInvocationOutcome {
        invocations.append(id)
        if let failure { throw failure }
        return outcome
    }
    func clear() { clears += 1 }
}
final class MenuClock: Sendable {
    let value = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
    func now() -> ContinuousClock.Instant { value.withLock { $0 } }
    func advance(_ duration: Duration) { value.withLock { $0 = $0.advanced(by: duration) } }
}
actor MemoryFavorites: CompanionMenuFavoritesStoring {
    var favorites: Set<CompanionMenuIdentity> = []
    var saves = 0
    var fail = false
    func setFailure() { fail = true }
    func load() throws -> Set<CompanionMenuIdentity> { if fail { throw CompanionAppMenuError.persistence }; return favorites }
    func save(_ values: Set<CompanionMenuIdentity>) throws {
        if fail { throw CompanionAppMenuError.persistence }
        saves += 1; favorites = values
    }
}
actor MenuClient: CompanionAppMenuCalling {
    var calls: [CompanionAppMenuRequest] = []
    var snapshot: CompanionAppMenuSnapshot
    var reply: CompanionAppMenuReply?
    var holdSnapshot = false
    var pending: CheckedContinuation<Void, Never>?
    var observer: CheckedContinuation<Void, Never>?
    init(items: [CompanionAppMenuItem]) { snapshot = .init(bundleIdentifier: "generated.fixture", items: items) }
    func setReply(_ reply: CompanionAppMenuReply) { self.reply = reply }
    func hold() { holdSnapshot = true }
    func waitForSnapshot() async { if calls.contains(.snapshot) { return }; await withCheckedContinuation { observer = $0 } }
    func resume() { pending?.resume(); pending = nil }
    func requestAppMenu(_ request: CompanionAppMenuRequest) async throws -> CompanionAppMenuReply {
        calls.append(request)
        switch request {
        case .snapshot:
            observer?.resume(); observer = nil
            if holdSnapshot { await withCheckedContinuation { pending = $0 } }
            return reply ?? .snapshot(snapshot)
        case .setEnabled(let value): return reply ?? .enabled(value)
        case .release: return .released
        case .invoke: return reply ?? .invoked(.accepted)
        }
    }
}
func menuItem(_ title: String = "Generated Action", enabled: Bool = true) throws -> CompanionAppMenuItem {
    let value = candidate(title, enabled: enabled)
    return .init(handle: .init(session: UUID(), target: UUID()), title: title, ancestors: ["Generated Menu"], enabled: enabled,
                 identity: try value.identity(bundle: "generated.fixture"))
}
