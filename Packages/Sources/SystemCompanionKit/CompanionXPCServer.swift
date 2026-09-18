import Foundation
import Infrastructure
import os

/// Actor-owned native sessions are cleared on disconnect, process termination, and future feature shutdown.
public actor CompanionServerSessions {
    private struct Entry { let engine: CompanionSessionEngine; let bound: CompanionBoundListener }
    private var sessions: [UUID: Entry] = [:]
    private var stopped = false
    public init() {}
    fileprivate func add(_ id: UUID, engine: CompanionSessionEngine, bound: CompanionBoundListener, lease: CompanionConnectionLease) async {
        guard stopped == false, lease.isReleased == false else { await engine.invalidate(); await bound.invalidate(); return }
        sessions[id] = Entry(engine: engine, bound: bound)
    }
    fileprivate func remove(_ id: UUID, engine: CompanionSessionEngine, bound: CompanionBoundListener) async {
        sessions[id] = nil
        await engine.invalidate(); await bound.invalidate()
    }
    public func invalidateAll() async {
        stopped = true
        let values = sessions.values; sessions.removeAll()
        for entry in values { await entry.engine.invalidate(); await entry.bound.invalidate() }
    }
}

/// Native delegate has immutable configuration; its sole synchronous mutable state is a tiny connection counter.
public final class CompanionXPCServerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    private let policy: CompanionSigningPolicy
    private let userSession: CompanionUserSession
    private let build: String
    private let sessions: CompanionServerSessions
    private let keyboardTriggerFactory: CompanionKeyboardTriggerFactory?
    private let appMenuFactory: CompanionAppMenuFactory?
    private let windowLayoutFactory: CompanionWindowLayoutFactory?
    private let count = OSAllocatedUnfairLock(initialState: 0)
    public init(policy: CompanionSigningPolicy, userSession: CompanionUserSession, build: String,
                sessions: CompanionServerSessions, windowLayoutFactory: CompanionWindowLayoutFactory? = nil, appMenuFactory: CompanionAppMenuFactory? = nil, keyboardTriggerFactory: CompanionKeyboardTriggerFactory? = nil) {
        self.windowLayoutFactory = windowLayoutFactory; self.appMenuFactory = appMenuFactory; self.keyboardTriggerFactory = keyboardTriggerFactory
        self.policy = policy; self.userSession = userSession; self.build = build; self.sessions = sessions
    }
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let peer = CompanionUserSession(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)
        guard userSession.permits(peer), count.withLock({ value in
            guard value < 4 else { return false }
            value += 1; return true
        }) else { return false }
        let id = UUID()
        let engine = CompanionSessionEngine(build: build, metadata: FoundationCompanionMetadata(build: build))
        let bound = CompanionBoundListener(policy: policy, userSession: userSession, build: build, windowLayoutFactory: windowLayoutFactory, appMenuFactory: appMenuFactory, keyboardTriggerFactory: keyboardTriggerFactory)
        let lease = CompanionConnectionLease { [weak self] in self?.count.withLock { $0 -= 1 } }
        // Independent peer authentication in this direction, set once before the accepted channel activates.
        connection.setCodeSigningRequirement(policy.applicationRequirement)
        connection.exportedInterface = NSXPCInterface(with: CompanionBootstrapXPCProtocol.self)
        connection.exportedObject = CompanionBootstrapServerEndpoint(engine: engine, userSession: userSession, bound: bound)
        let onEnd: @Sendable () -> Void = { [sessions] in
            bound.revokeActions()
            lease.release()
            Task { await sessions.remove(id, engine: engine, bound: bound) }
        }
        connection.invalidationHandler = onEnd
        connection.interruptionHandler = onEnd
        Task { [sessions] in await sessions.add(id, engine: engine, bound: bound, lease: lease) }
        connection.activate()
        return true
    }
}

fileprivate final class CompanionConnectionLease: Sendable {
    private let released = OSAllocatedUnfairLock(initialState: false)
    private let onRelease: @Sendable () -> Void
    init(onRelease: @escaping @Sendable () -> Void) { self.onRelease = onRelease }
    var isReleased: Bool { released.withLock { $0 } }
    func release() {
        let first = released.withLock { value in if value { return false }; value = true; return true }
        if first { onRelease() }
    }
}

final class CompanionServerEndpoint: NSObject, CompanionXPCProtocol, Sendable {
    let engine: CompanionSessionEngine
    let userSession: CompanionUserSession
    private let admission = OSAllocatedUnfairLock(initialState: (normal: 0, control: 0))
    init(engine: CompanionSessionEngine, userSession: CompanionUserSession) { self.engine = engine; self.userSession = userSession }
    func exchange(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        // Read the public current connection only in its synchronous callback context, never after an await.
        guard let connection = NSXPCConnection.current(),
              userSession.permits(.init(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)),
              let request = try? CompanionWireCodec.decodeRequest(data) else { reply(Data()); return }
        let control = request.operation == .cancel || request.operation == .closeSession
        guard admission.withLock({ state in
            if control { guard state.control < 2 else { return false }; state.control += 1 }
            else { guard state.normal < CompanionLimits.inFlightRequests else { return false }; state.normal += 1 }
            return true
        }) else {
            do { reply(try CompanionWireCodec.encode(.init(requestID: request.id, value: .failure(.tooManyRequests)))) }
            catch { reply(Data()) }
            return
        }
        Task { [engine, admission] in
            defer { admission.withLock { state in if control { state.control -= 1 } else { state.normal -= 1 } } }
            let value = await engine.receive(request)
            do { reply(try CompanionWireCodec.encode(value)) }
            catch { reply(Data()) }
        }
    }
}
