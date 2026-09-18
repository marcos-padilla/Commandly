import Foundation
import Infrastructure
import os

/// Small synchronous gate is shared with Foundation's delegate queue. It never stores native objects or private data.
/// A ticket is single-use, single-connection, and expires against the helper's monotonic clock.
final class CompanionBoundAdmission: Sendable {
    private struct State { var claimed = false; var ready = false; var invalid = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let ticket: CompanionBoundTicket
    private let userSession: CompanionUserSession
    private let deadline: ContinuousClock.Instant
    private let clock: any CompanionDeadlineClock
    init(ticket: CompanionBoundTicket, userSession: CompanionUserSession,
         deadline: ContinuousClock.Instant, clock: any CompanionDeadlineClock) {
        self.ticket = ticket; self.userSession = userSession; self.deadline = deadline; self.clock = clock
    }
    func claim(_ peer: CompanionUserSession) -> Bool {
        state.withLock { value in
            guard userSession.permits(peer), value.invalid == false, value.claimed == false, clock.now() < deadline else { return false }
            value.claimed = true; return true
        }
    }
    func bind(_ proof: CompanionBoundProof, peer: CompanionUserSession) throws {
        try state.withLock { value in
            guard userSession.permits(peer) else { throw CompanionError.wrongUserSession }
            guard value.invalid == false, value.claimed, value.ready == false else { throw CompanionError.replayedRequest }
            guard clock.now() < deadline else { throw CompanionError.expiredSession }
            guard proof.ticket == ticket else { throw CompanionError.unknownSession }
            value.ready = true
        }
    }
    func validateBindCompletion() throws {
        try state.withLock {
            guard $0.ready, $0.invalid == false else { throw CompanionError.disconnected }
            guard clock.now() < deadline else { throw CompanionError.expiredSession }
        }
    }
    var isReady: Bool { state.withLock { $0.ready && $0.invalid == false } }
    func invalidate() { state.withLock { $0.invalid = true; $0.ready = false } }
}

/// Owns one anonymous listener and its delegate. The named connection retains this owner for the whole
/// endpoint lifetime; losing either channel invalidates the listener and every session it created.
actor CompanionBoundListener {
    private let policy: CompanionSigningPolicy
    private let userSession: CompanionUserSession
    private let build: String
    private let clock: any CompanionDeadlineClock
    private let keyboardTriggerFactory: CompanionKeyboardTriggerFactory?
    private let appMenuFactory: CompanionAppMenuFactory?
    private let windowLayoutFactory: CompanionWindowLayoutFactory?
    nonisolated private let keyboardTriggerOwner = CompanionKeyboardTriggerBindingOwner()
    nonisolated private let appMenuOwner = CompanionAppMenuBindingOwner()
    nonisolated private let windowLayoutOwner = CompanionWindowLayoutBindingOwner()
    private let peerOwner = CompanionBoundConnectionOwner<NSXPCConnection>(activate: { $0.activate() }, close: { $0.invalidate() })
    private var issued = false
    private var invalid = false
    private var listener: NSXPCListener?
    private var delegate: CompanionBoundListenerDelegate?
    private var engine: CompanionSessionEngine?
    private var admission: CompanionBoundAdmission?
    private var expiry: Task<Void, Never>?
    init(policy: CompanionSigningPolicy, userSession: CompanionUserSession, build: String,
         clock: any CompanionDeadlineClock = NativeCompanionDeadlineClock(), windowLayoutFactory: CompanionWindowLayoutFactory? = nil, appMenuFactory: CompanionAppMenuFactory? = nil, keyboardTriggerFactory: CompanionKeyboardTriggerFactory? = nil) {
        self.windowLayoutFactory = windowLayoutFactory; self.appMenuFactory = appMenuFactory; self.keyboardTriggerFactory = keyboardTriggerFactory
        self.policy = policy; self.userSession = userSession; self.build = build; self.clock = clock
    }
    func issue(_ hello: CompanionBoundHello) throws -> (Data, NSXPCListenerEndpoint) {
        guard invalid == false, issued == false else { throw CompanionError.replayedRequest }
        try CompanionBoundWire.validate(hello)
        guard hello.build == build else { throw CompanionError.versionMismatch }
        issued = true
        let ticket = CompanionBoundTicket(hello: hello)
        let data = try CompanionBoundWire.encode(ticket)
        let deadline = clock.now().advanced(by: .milliseconds(CompanionLimits.timeoutMilliseconds))
        let gate = CompanionBoundAdmission(ticket: ticket, userSession: userSession, deadline: deadline, clock: clock)
        let engine = CompanionSessionEngine(build: build, metadata: FoundationCompanionMetadata(build: build))
        let delegate = CompanionBoundListenerDelegate(policy: policy, userSession: userSession, gate: gate, engine: engine, peerOwner: peerOwner, windowLayoutFactory: windowLayoutFactory, windowLayoutOwner: windowLayoutOwner, appMenuFactory: appMenuFactory, appMenuOwner: appMenuOwner, keyboardTriggerFactory: keyboardTriggerFactory, keyboardTriggerOwner: keyboardTriggerOwner) { [weak self] in
            Task { await self?.invalidate() }
        }
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        self.listener = listener; self.delegate = delegate; self.engine = engine; admission = gate
        listener.activate()
        expiry = Task { [weak self, clock] in
            do { try await clock.sleep(until: deadline) } catch { return }
            await self?.expireIfUnbound()
        }
        return (data, listener.endpoint)
    }
    nonisolated func revokeActions() { windowLayoutOwner.revoke(); appMenuOwner.revoke(); keyboardTriggerOwner.revoke() }
    func invalidate() async {
        revokeActions()
        invalid = true; admission?.invalidate(); peerOwner.invalidate(); expiry?.cancel(); expiry = nil
        listener?.invalidate(); listener = nil; delegate = nil
        let old = engine; engine = nil
        await old?.invalidate()
    }
    private func expireIfUnbound() async {
        if admission?.isReady != true { await invalidate() }
    }
}

private final class CompanionBoundListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    let policy: CompanionSigningPolicy
    let userSession: CompanionUserSession
    let gate: CompanionBoundAdmission
    let engine: CompanionSessionEngine
    let onEnd: @Sendable () -> Void
    let peerOwner: CompanionBoundConnectionOwner<NSXPCConnection>
    let keyboardTriggerFactory: CompanionKeyboardTriggerFactory?
    let keyboardTriggerOwner: CompanionKeyboardTriggerBindingOwner
    let appMenuFactory: CompanionAppMenuFactory?
    let appMenuOwner: CompanionAppMenuBindingOwner
    let windowLayoutFactory: CompanionWindowLayoutFactory?
    let windowLayoutOwner: CompanionWindowLayoutBindingOwner
    init(policy: CompanionSigningPolicy, userSession: CompanionUserSession, gate: CompanionBoundAdmission,
         engine: CompanionSessionEngine, peerOwner: CompanionBoundConnectionOwner<NSXPCConnection>, windowLayoutFactory: CompanionWindowLayoutFactory?, windowLayoutOwner: CompanionWindowLayoutBindingOwner, appMenuFactory: CompanionAppMenuFactory?, appMenuOwner: CompanionAppMenuBindingOwner, keyboardTriggerFactory: CompanionKeyboardTriggerFactory?, keyboardTriggerOwner: CompanionKeyboardTriggerBindingOwner, onEnd: @escaping @Sendable () -> Void) {
        self.windowLayoutFactory = windowLayoutFactory; self.appMenuFactory = appMenuFactory; self.keyboardTriggerFactory = keyboardTriggerFactory; self.windowLayoutOwner = windowLayoutOwner; self.appMenuOwner = appMenuOwner; self.keyboardTriggerOwner = keyboardTriggerOwner
        self.peerOwner = peerOwner
        self.policy = policy; self.userSession = userSession; self.gate = gate; self.engine = engine; self.onEnd = onEnd
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let peer = CompanionUserSession(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)
        guard gate.claim(peer) else { return false }
        // Claim alone is not signer authorization. Foundation filters each incoming invocation using this requirement.
        connection.setCodeSigningRequirement(policy.applicationRequirement)
        connection.exportedInterface = NSXPCInterface(with: CompanionBoundXPCProtocol.self)
        connection.exportedObject = CompanionBoundServerEndpoint(gate: gate, userSession: userSession, engine: engine, windowLayoutFactory: windowLayoutFactory, windowLayoutOwner: windowLayoutOwner, appMenuFactory: appMenuFactory, appMenuOwner: appMenuOwner, keyboardTriggerFactory: keyboardTriggerFactory, keyboardTriggerOwner: keyboardTriggerOwner, onEnd: onEnd)
        let end: @Sendable () -> Void = { [gate, windowLayoutOwner, appMenuOwner, keyboardTriggerOwner, onEnd] in windowLayoutOwner.revoke(); appMenuOwner.revoke(); keyboardTriggerOwner.revoke(); gate.invalidate(); onEnd() }
        connection.invalidationHandler = end; connection.interruptionHandler = end
        return peerOwner.accept(connection)
    }
}

private final class CompanionBoundServerEndpoint: NSObject, CompanionBoundXPCProtocol, Sendable {
    let gate: CompanionBoundAdmission
    let userSession: CompanionUserSession
    let metadata: CompanionServerEndpoint
    let engine: CompanionSessionEngine
    let keyboardTriggerFactory: CompanionKeyboardTriggerFactory?
    let keyboardTriggerOwner: CompanionKeyboardTriggerBindingOwner
    let appMenuFactory: CompanionAppMenuFactory?
    let appMenuOwner: CompanionAppMenuBindingOwner
    let windowLayoutFactory: CompanionWindowLayoutFactory?
    let windowLayoutOwner: CompanionWindowLayoutBindingOwner
    let onEnd: @Sendable () -> Void
    init(gate: CompanionBoundAdmission, userSession: CompanionUserSession, engine: CompanionSessionEngine,
         windowLayoutFactory: CompanionWindowLayoutFactory?, windowLayoutOwner: CompanionWindowLayoutBindingOwner, appMenuFactory: CompanionAppMenuFactory?, appMenuOwner: CompanionAppMenuBindingOwner, keyboardTriggerFactory: CompanionKeyboardTriggerFactory?, keyboardTriggerOwner: CompanionKeyboardTriggerBindingOwner, onEnd: @escaping @Sendable () -> Void) {
        self.engine = engine; self.windowLayoutFactory = windowLayoutFactory; self.appMenuFactory = appMenuFactory; self.keyboardTriggerFactory = keyboardTriggerFactory; self.windowLayoutOwner = windowLayoutOwner; self.appMenuOwner = appMenuOwner; self.keyboardTriggerOwner = keyboardTriggerOwner
        self.gate = gate; self.userSession = userSession; metadata = .init(engine: engine, userSession: userSession); self.onEnd = onEnd
    }
    func bind(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        guard let connection = NSXPCConnection.current() else { reply(Data()); return }
        let peer = CompanionUserSession(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)
        do {
            let proof = try CompanionBoundWire.proof(data)
            try gate.bind(proof, peer: peer)
            let authenticatedPID = connection.processIdentifier
            guard authenticatedPID > 0 else { throw CompanionError.wrongUserSession }
            guard windowLayoutFactory != nil || appMenuFactory != nil || keyboardTriggerFactory != nil else { reply(try CompanionBoundWire.encode(proof)); return }
            Task { [gate, engine, windowLayoutOwner, appMenuOwner, keyboardTriggerOwner, windowLayoutFactory, appMenuFactory, keyboardTriggerFactory, onEnd] in
                do {
                    if let windowLayoutFactory {
                        let handler = await windowLayoutFactory.make(authenticatedMainProcessIdentifier: authenticatedPID)
                        guard windowLayoutOwner.install(handler) else { throw CompanionError.disconnected }
                        try await engine.installBoundWindowLayouts(handler)
                    }
                    if let appMenuFactory {
                        let handler = await appMenuFactory.make(authenticatedMainProcessIdentifier: authenticatedPID)
                        guard appMenuOwner.install(handler) else { throw CompanionError.disconnected }
                        try await engine.installBoundAppMenus(handler)
                    }
                    if let keyboardTriggerFactory {
                        let handler = await keyboardTriggerFactory.make()
                        guard keyboardTriggerOwner.install(handler) else { throw CompanionError.disconnected }
                        try await engine.installBoundKeyboardTriggers(handler)
                    }
                    try gate.validateBindCompletion()
                    reply(try CompanionBoundWire.encode(proof))
                } catch {
                    windowLayoutOwner.revoke(); appMenuOwner.revoke(); keyboardTriggerOwner.revoke(); gate.invalidate(); reply(CompanionBoundWire.failure(error)); onEnd()
                }
            }
        } catch { windowLayoutOwner.revoke(); appMenuOwner.revoke(); keyboardTriggerOwner.revoke(); gate.invalidate(); reply(CompanionBoundWire.failure(error)); onEnd() }
    }
    func exchange(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        guard gate.isReady, let connection = NSXPCConnection.current(),
              userSession.permits(.init(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)) else {
            windowLayoutOwner.revoke(); appMenuOwner.revoke(); keyboardTriggerOwner.revoke(); gate.invalidate(); reply(Data()); onEnd(); return
        }
        metadata.exchange(data, withReply: reply)
    }
}

/// The existing named metadata method remains compatible; only bootstrap can vend a new listener.
final class CompanionBootstrapServerEndpoint: NSObject, CompanionBootstrapXPCProtocol, Sendable {
    private let metadata: CompanionServerEndpoint
    private let bound: CompanionBoundListener
    private let userSession: CompanionUserSession
    private let admission = OSAllocatedUnfairLock(initialState: false)
    init(engine: CompanionSessionEngine, userSession: CompanionUserSession, bound: CompanionBoundListener) {
        metadata = .init(engine: engine, userSession: userSession); self.userSession = userSession; self.bound = bound
    }
    func exchange(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) { metadata.exchange(data, withReply: reply) }
    func bootstrap(_ data: Data, withReply reply: @escaping @Sendable (Data, NSXPCListenerEndpoint?) -> Void) {
        // Foundation has authenticated this incoming invocation before calling it. Capture kernel identity now.
        guard let connection = NSXPCConnection.current(),
              userSession.permits(.init(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)),
              let hello = try? CompanionBoundWire.hello(data),
              admission.withLock({ used in if used { return false }; used = true; return true }) else { reply(Data(), nil); return }
        Task { [bound] in
            do { let result = try await bound.issue(hello); reply(result.0, result.1) }
            catch { reply(CompanionBoundWire.failure(error), nil) }
        }
    }
}
