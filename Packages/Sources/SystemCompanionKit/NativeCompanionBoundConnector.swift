import Foundation
import Infrastructure

/// Foundation connections stay actor-owned. Endpoint objects are SDK-declared Sendable/NSSecureCoding.
/// Neither construction nor status reads contact launchd. Only an explicit bootstrap connects.
public actor NativeCompanionBoundConnector: CompanionBoundConnecting {
    private enum Channel: Sendable { case named, endpoint }
    private enum Response: Sendable { case bootstrap(Data, NSXPCListenerEndpoint?), data(Data) }
    private enum Call { case bootstrap(Data), bind(Data), exchange(Data) }
    private struct Pending {
        let continuation: CheckedContinuation<Response, any Error>
        let timeout: Task<Void, Never>
        let channel: Channel
        let deadline: ContinuousClock.Instant
    }
    private let clock: any CompanionDeadlineClock
    private let allowReviewedKeyboardTriggers: Bool
    private let allowReviewedAppMenus: Bool
    private let allowReviewedWindowLayouts: Bool
    private var named: NSXPCConnection?
    private var endpoint: NSXPCConnection?
    private var offeredEndpoint: NSXPCListenerEndpoint?
    private var offeredTicket: CompanionBoundTicket?
    private var policy: CompanionSigningPolicy?
    private var userSession: CompanionUserSession?
    private var generation = UUID()
    private var pending: [UUID: Pending] = [:]
    private var bindingDeadline: ContinuousClock.Instant?
    private var ready = false
    private var invalidated = false
    public init(clock: any CompanionDeadlineClock = NativeCompanionDeadlineClock(), allowReviewedWindowLayouts: Bool = false, allowReviewedAppMenus: Bool = false, allowReviewedKeyboardTriggers: Bool = false) {
        self.clock = clock; self.allowReviewedWindowLayouts = allowReviewedWindowLayouts; self.allowReviewedAppMenus = allowReviewedAppMenus; self.allowReviewedKeyboardTriggers = allowReviewedKeyboardTriggers
    }

    public func bootstrap(_ hello: CompanionBoundHello) async throws -> CompanionBoundTicket {
        guard named == nil, invalidated == false else { throw CompanionError.disconnected }
        try Task.checkCancellation(); try CompanionBoundWire.validate(hello)
        let policy = try CompanionSigningPolicy()
        try policy.validateCurrentProcess(as: .application)
        let userSession = try CompanionUserSession.current()
        self.policy = policy; self.userSession = userSession
        let connection = NSXPCConnection(machServiceName: CompanionIdentity.machService, options: [])
        configure(connection, requirement: policy.helperRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: CompanionBootstrapXPCProtocol.self)
        named = connection; connection.activate()
        let token = generation
        let deadline = clock.now().advanced(by: .milliseconds(CompanionLimits.timeoutMilliseconds))
        bindingDeadline = deadline
        do {
            let response = try await call(.bootstrap(CompanionBoundWire.encode(hello)), id: hello.requestID, channel: .named, deadline: deadline)
            try check(token)
            guard case .bootstrap(let data, let object) = response else { throw CompanionError.malformedMessage }
            let ticket = try CompanionBoundWire.ticket(data)
            guard let object else { throw CompanionError.malformedMessage }
            guard ticket.hello == hello else { throw CompanionError.malformedMessage }
            // receive() already checked the OS-authenticated reply's kernel user/session. Only now retain its endpoint.
            offeredEndpoint = object; offeredTicket = ticket
            return ticket
        } catch { failAll((error as? CompanionError) ?? .disconnected); throw error }
    }
    public func bind(_ proof: CompanionBoundProof) async throws -> CompanionBoundProof {
        guard invalidated == false, endpoint == nil, proof.ticket == offeredTicket,
              let object = offeredEndpoint, let policy, let deadline = bindingDeadline,
              clock.now() < deadline else { failAll(.expiredSession); throw CompanionError.expiredSession }
        try Task.checkCancellation()
        // No Mach-name lookup or fallback. This object refers to the particular authenticated listener instance.
        let connection = NSXPCConnection(listenerEndpoint: object)
        configure(connection, requirement: policy.helperRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: CompanionBoundXPCProtocol.self)
        endpoint = connection; offeredEndpoint = nil; connection.activate()
        let token = generation
        do {
            let response = try await call(.bind(CompanionBoundWire.encode(proof)), id: proof.challenge, channel: .endpoint, deadline: deadline)
            try check(token)
            guard case .data(let data) = response else { throw CompanionError.malformedMessage }
            let echoed = try CompanionBoundWire.proof(data)
            guard echoed == proof else { throw CompanionError.malformedMessage }
            ready = true; offeredTicket = nil; bindingDeadline = nil
            return echoed
        } catch { failAll((error as? CompanionError) ?? .disconnected); throw error }
    }
    public func exchangeMetadata(_ data: Data) async throws -> Data {
        let request = try CompanionWireCodec.decodeRequest(data)
        try CompanionBoundTransport.requireBoundAllowed(request, allowReviewedWindowLayouts: allowReviewedWindowLayouts, allowReviewedAppMenus: allowReviewedAppMenus, allowReviewedKeyboardTriggers: allowReviewedKeyboardTriggers)
        guard ready, invalidated == false else { throw CompanionError.disconnected }
        let token = generation
        do {
            let response = try await call(.exchange(data), id: request.id, channel: .endpoint,
                                          deadline: clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds)))
            try check(token)
            guard case .data(let data) = response else { throw CompanionError.malformedMessage }
            let reply = try CompanionWireCodec.decodeReply(data)
            guard reply.requestID == request.id else { throw CompanionError.malformedMessage }
            guard reply.version == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
            return data
        } catch { failAll((error as? CompanionError) ?? .disconnected); throw error }
    }
    public func isConnected() -> Bool { ready && named != nil && endpoint != nil && invalidated == false }
    public func invalidate() { failAll(.disconnected) }

    private func configure(_ connection: NSXPCConnection, requirement: String) {
        // Each direction receives one immutable Security-validated requirement before activation.
        connection.setCodeSigningRequirement(requirement)
        let token = generation
        connection.invalidationHandler = { [weak self] in Task { await self?.connectionEnded(token) } }
        connection.interruptionHandler = { [weak self] in Task { await self?.connectionEnded(token) } }
    }
    private func call(_ call: Call, id: UUID, channel: Channel, deadline: ContinuousClock.Instant) async throws -> Response {
        guard pending[id] == nil, pending.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
        guard let connection = channel == .named ? named : endpoint, invalidated == false else { throw CompanionError.disconnected }
        let token = generation
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard clock.now() < deadline else { throw CompanionError.timedOut }
            return try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self, clock] in
                    do { try await clock.sleep(until: deadline) } catch { return }
                    await self?.timedOut(id, token: token)
                }
                pending[id] = .init(continuation: continuation, timeout: timeout, channel: channel, deadline: deadline)
                let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                    Task { await self?.connectionEnded(token) }
                }
                switch call {
                case .bootstrap(let data):
                    guard let remote = proxy as? any CompanionBootstrapXPCProtocol else { failAll(.disconnected); return }
                    remote.bootstrap(data) { [weak self] reply, endpoint in
                        Task { await self?.receive(.bootstrap(reply, endpoint), id: id, token: token) }
                    }
                case .bind(let data):
                    guard let remote = proxy as? any CompanionBoundXPCProtocol else { failAll(.disconnected); return }
                    remote.bind(data) { [weak self] reply in Task { await self?.receive(.data(reply), id: id, token: token) } }
                case .exchange(let data):
                    guard let remote = proxy as? any CompanionBoundXPCProtocol else { failAll(.disconnected); return }
                    remote.exchange(data) { [weak self] reply in Task { await self?.receive(.data(reply), id: id, token: token) } }
                }
            }
        } onCancel: { [weak self] in Task { await self?.canceled(id, token: token) } }
    }
    private func receive(_ response: Response, id: UUID, token: UUID) {
        guard token == generation, let item = pending[id], let userSession,
              let connection = item.channel == .named ? named : endpoint else { return }
        guard clock.now() < item.deadline else { failAll(.timedOut); return }
        // A setter-authenticated reply alone does not prove the expected login session.
        let peer = CompanionUserSession(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)
        guard userSession.permits(peer) else { failAll(.wrongUserSession); return }
        let count: Int
        switch response { case .bootstrap(let data, _), .data(let data): count = data.count }
        let maximum = item.channel == .named || ready == false ? CompanionBoundWire.maximumBytes : CompanionLimits.replyBytes
        guard count <= maximum else { failAll(.oversizedMessage); return }
        pending[id] = nil; item.timeout.cancel(); item.continuation.resume(returning: response)
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == generation, invalidated == false else { throw CompanionError.disconnected }
    }
    private func connectionEnded(_ token: UUID) { if token == generation { failAll(.disconnected) } }
    private func timedOut(_ id: UUID, token: UUID) { if token == generation, pending[id] != nil { failAll(.timedOut) } }
    private func canceled(_ id: UUID, token: UUID) { if token == generation, pending[id] != nil { failAll(.canceled) } }
    private func failAll(_ error: CompanionError) {
        generation = UUID(); invalidated = true; ready = false
        offeredEndpoint = nil; offeredTicket = nil; bindingDeadline = nil; policy = nil; userSession = nil
        let oldNamed = named; let oldEndpoint = endpoint; named = nil; endpoint = nil
        oldNamed?.invalidationHandler = nil; oldNamed?.interruptionHandler = nil; oldNamed?.invalidate()
        oldEndpoint?.invalidationHandler = nil; oldEndpoint?.interruptionHandler = nil; oldEndpoint?.invalidate()
        let work = pending.values; pending.removeAll()
        for item in work { item.timeout.cancel(); item.continuation.resume(throwing: error) }
    }
}
