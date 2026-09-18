import Foundation
import Infrastructure

/// Owns Foundation's non-Sendable connection on one actor. Construction never connects or starts a helper.
public actor NativeCompanionTransport: CompanionTransport {
    private struct Pending {
        let continuation: CheckedContinuation<Data, any Error>
        let timeout: Task<Void, Never>
    }
    private let clock: any CompanionDeadlineClock
    private var connection: NSXPCConnection?
    private var userSession: CompanionUserSession?
    private var generation = UUID()
    private var pending: [UUID: Pending] = [:]
    public init(clock: any CompanionDeadlineClock = NativeCompanionDeadlineClock()) { self.clock = clock }

    public func exchange(_ data: Data) async throws -> Data {
        let request = try CompanionWireCodec.decodeRequest(data)
        // The public signing requirement validates incoming replies, not initial outbound disclosure.
        // Never send future private/action payloads on this metadata-only Mach-name channel.
        switch request.operation {
        case .handshake, .status, .openSession, .closeSession, .cancel: break
        default: throw CompanionError.unsupportedOperation
        }
        try Task.checkCancellation()
        guard pending[request.id] == nil, pending.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
        if connection == nil { try connect() }
        guard let connection else { throw CompanionError.disconnected }
        let token = generation; let requestID = request.id
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let deadline = clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds))
                let timeout = Task { [weak self, clock] in
                    do { try await clock.sleep(until: deadline) }
                    catch { return }
                    await self?.timedOut(requestID, generation: token)
                }
                pending[requestID] = .init(continuation: continuation, timeout: timeout)
                let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                    Task { await self?.connectionFailed(generation: token) }
                }
                guard let remote = proxy as? any CompanionXPCProtocol else { failAll(.disconnected); return }
                remote.exchange(data) { [weak self] reply in
                    Task { await self?.receive(reply, requestID: requestID, generation: token) }
                }
            }
        } onCancel: { [weak self] in
            Task { await self?.canceled(requestID, generation: token) }
        }
    }
    public func isConnected() -> Bool { connection != nil }
    public func invalidate() { failAll(.disconnected) }

    private func connect() throws {
        let policy = try CompanionSigningPolicy()
        try policy.validateCurrentProcess(as: .application)
        userSession = try CompanionUserSession.current()
        let connection = NSXPCConnection(machServiceName: CompanionIdentity.machService, options: [])
        // Exactly once, before activate. No privileged bootstrap option or Mach lookup exception.
        connection.setCodeSigningRequirement(policy.helperRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: CompanionXPCProtocol.self)
        generation = UUID(); let token = generation
        connection.invalidationHandler = { [weak self] in Task { await self?.connectionFailed(generation: token) } }
        connection.interruptionHandler = { [weak self] in Task { await self?.connectionFailed(generation: token) } }
        self.connection = connection
        connection.activate()
    }
    private func receive(_ data: Data, requestID: UUID, generation token: UUID) {
        guard token == generation, pending[requestID] != nil, let connection, let userSession else { return }
        let peer = CompanionUserSession(effectiveUser: connection.effectiveUserIdentifier, auditSession: connection.auditSessionIdentifier)
        guard userSession.permits(peer) else { failAll(.wrongUserSession); return }
        do {
            let reply = try CompanionWireCodec.decodeReply(data)
            guard reply.requestID == requestID, reply.version == CompanionLimits.protocolVersion else { failAll(.unsupportedVersion); return }
            guard let work = pending.removeValue(forKey: requestID) else { return }
            work.timeout.cancel(); work.continuation.resume(returning: data)
        } catch let error as CompanionError { failAll(error) }
        catch { failAll(.malformedMessage) }
    }
    private func timedOut(_ id: UUID, generation token: UUID) {
        guard token == generation, pending[id] != nil else { return }
        failAll(.timedOut)
    }
    private func canceled(_ id: UUID, generation token: UUID) {
        guard token == generation, pending[id] != nil else { return }
        // Closing the channel cancels every associated server session, including an in-flight request.
        failAll(.canceled)
    }
    private func connectionFailed(generation token: UUID) {
        guard token == generation else { return }
        failAll(.disconnected)
    }
    private func failAll(_ error: CompanionError) {
        generation = UUID()
        let old = connection; connection = nil; userSession = nil
        old?.invalidationHandler = nil; old?.interruptionHandler = nil; old?.invalidate()
        let work = pending.values; pending.removeAll()
        for item in work { item.timeout.cancel(); item.continuation.resume(throwing: error) }
    }
}
