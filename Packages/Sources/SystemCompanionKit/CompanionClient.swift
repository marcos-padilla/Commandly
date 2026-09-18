import Foundation
import Infrastructure

/// Negotiates matching build/version before creating one short-lived metadata session.
public actor CompanionClient: CompanionWindowLayoutCalling, CompanionAppMenuCalling, CompanionKeyboardTriggerOperating {
    private let transport: any CompanionTransport
    private let build: String
    private var sequence: UInt64 = 0
    private var session: UUID?
    private var negotiated = false
    private var isChecking = false
    private var generation = UUID()
    public init(transport: any CompanionTransport, build: String) { self.transport = transport; self.build = build }

    public func check() async throws -> CompanionStatus {
        guard isChecking == false else { throw CompanionError.tooManyRequests }
        isChecking = true
        let token = generation
        defer { isChecking = false }
        do {
            if negotiated == false {
                let value = try await send(.handshake)
                guard case .status(let status) = value else { throw CompanionError.malformedMessage }
                try verifyGeneration(token); try verify(status); negotiated = true
            }
            if session == nil {
                guard case .session(let sessionToken) = try await send(.openSession) else { throw CompanionError.malformedMessage }
                try verifyGeneration(token)
                session = sessionToken
            }
            guard case .status(let status) = try await send(.status) else { throw CompanionError.malformedMessage }
            try verifyGeneration(token); try verify(status)
            return status
        } catch {
            if generation == token { await disconnect() }
            throw error
        }
    }
    public func keyboardTriggers(_ request: CompanionKeyboardTriggerRequest) async throws -> CompanionKeyboardTriggerReply {
        guard negotiated, session != nil, isChecking == false else { throw CompanionError.disconnected }
        let token = generation
        do {
            guard await transport.isConnected() else { throw CompanionError.disconnected }
            try verifyGeneration(token)
            let result = try await send(.keyboardTriggerAction, action: .keyboardTrigger(request))
            try verifyGeneration(token)
            guard case .keyboardTrigger(let value) = result else { throw CompanionError.malformedMessage }
            return value
        } catch {
            if generation == token { await disconnect() }
            throw error
        }
    }
    public func requestAppMenu(_ request: CompanionAppMenuRequest) async throws -> CompanionAppMenuReply {
        guard negotiated, session != nil, isChecking == false else { throw CompanionError.disconnected }
        let token = generation
        do {
            guard await transport.isConnected() else { throw CompanionError.disconnected }
            try verifyGeneration(token)
            let result = try await send(.appMenuAction, action: .appMenu(request))
            try verifyGeneration(token)
            guard case .appMenu(let value) = result else { throw CompanionError.malformedMessage }
            return value
        } catch {
            if generation == token { await disconnect() }
            throw error
        }
    }
    public func requestWindowLayout(_ request: CompanionWindowLayoutRequest) async throws -> CompanionWindowLayoutReply {
        guard negotiated, session != nil, isChecking == false else { throw CompanionError.disconnected }
        let token = generation
        do {
            guard await transport.isConnected() else { throw CompanionError.disconnected }
            try verifyGeneration(token)
            let result = try await send(.windowLayoutAction, action: .windowLayout(request))
            try verifyGeneration(token)
            guard case .windowLayout(let value) = result else { throw CompanionError.malformedMessage }
            return value
        } catch {
            if generation == token { await disconnect() }
            throw error
        }
    }
    public func isConnected() async -> Bool {
        let token = generation
        guard negotiated else { return false }
        let connected = await transport.isConnected()
        return connected && token == generation && negotiated
    }
    public func disconnect() async {
        generation = UUID(); session = nil; negotiated = false
        await transport.invalidate()
    }
    private func send(_ operation: CompanionOperation, action: CompanionAction? = nil) async throws -> CompanionReplyValue {
        try Task.checkCancellation()
        guard sequence < UInt64.max else { throw CompanionError.expiredSession }
        sequence += 1
        let request = CompanionRequest(sequence: sequence, build: build, session: session, operation: operation, action: action)
        let data = try await transport.exchange(CompanionWireCodec.encode(request))
        try Task.checkCancellation()
        let reply = try CompanionWireCodec.decodeReply(data)
        guard reply.requestID == request.id else { throw CompanionError.malformedMessage }
        guard reply.version == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
        if case .failure(let error) = reply.value { throw error }
        return reply.value
    }
    private func verifyGeneration(_ value: UUID) throws {
        try Task.checkCancellation()
        guard value == generation else { throw CompanionError.disconnected }
    }
    private func verify(_ status: CompanionStatus) throws {
        guard status.protocolVersion == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
        guard status.build == build else { throw CompanionError.versionMismatch }
    }
}
