import Foundation
import Infrastructure

/// Injectable endpoint boundary. Production validates each received peer with Foundation signing requirements
/// and kernel user/session identity. Test implementations establish ordering only, never OS authentication.
public protocol CompanionBoundConnecting: Sendable {
    func bootstrap(_ hello: CompanionBoundHello) async throws -> CompanionBoundTicket
    func bind(_ proof: CompanionBoundProof) async throws -> CompanionBoundProof
    func exchangeMetadata(_ data: Data) async throws -> Data
    func isConnected() async -> Bool
    func invalidate() async
}

/// Metadata-only proof of a peer-instance channel. No future action is sent, even after binding succeeds.
/// An invalidated instance is terminal; create a new transport for an explicit new connection check.
public actor CompanionBoundTransport: CompanionTransport {
    private let connector: any CompanionBoundConnecting
    private let build: String
    private let allowReviewedKeyboardTriggers: Bool
    private let allowReviewedAppMenus: Bool
    private let allowReviewedWindowLayouts: Bool
    private var generation = UUID()
    private var opening = false
    private var ticket: CompanionBoundTicket?
    private var invalidated = false
    public init(build: String, connector: any CompanionBoundConnecting = NativeCompanionBoundConnector(), allowReviewedWindowLayouts: Bool = false, allowReviewedAppMenus: Bool = false, allowReviewedKeyboardTriggers: Bool = false) {
        self.build = build; self.connector = connector; self.allowReviewedWindowLayouts = allowReviewedWindowLayouts; self.allowReviewedAppMenus = allowReviewedAppMenus; self.allowReviewedKeyboardTriggers = allowReviewedKeyboardTriggers
    }
    public func exchange(_ data: Data) async throws -> Data {
        let request = try CompanionWireCodec.decodeRequest(data)
        try Self.requireBoundAllowed(request, allowReviewedWindowLayouts: allowReviewedWindowLayouts, allowReviewedAppMenus: allowReviewedAppMenus, allowReviewedKeyboardTriggers: allowReviewedKeyboardTriggers)
        guard request.build == build else { throw CompanionError.versionMismatch }
        guard invalidated == false else { throw CompanionError.disconnected }
        guard opening == false || ticket != nil else { throw CompanionError.tooManyRequests }
        let token = generation
        do {
            try await establishIfNeeded()
            try check(token)
            let reply = try await connector.exchangeMetadata(data)
            try check(token)
            let decoded = try CompanionWireCodec.decodeReply(reply)
            guard decoded.requestID == request.id else { throw CompanionError.malformedMessage }
            guard decoded.version == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
            return reply
        } catch {
            if generation == token { await invalidate() }
            throw error
        }
    }
    public func isConnected() async -> Bool {
        let token = generation
        guard ticket != nil, invalidated == false else { return false }
        let connected = await connector.isConnected()
        return connected && token == generation && ticket != nil && invalidated == false
    }
    public func invalidate() async {
        generation = UUID(); invalidated = true; ticket = nil
        await connector.invalidate()
    }
    static func requireBoundAllowed(_ request: CompanionRequest, allowReviewedWindowLayouts: Bool, allowReviewedAppMenus: Bool = false, allowReviewedKeyboardTriggers: Bool = false) throws {
        if allowReviewedKeyboardTriggers, request.operation == .keyboardTriggerAction { return }
        if allowReviewedAppMenus, request.operation == .appMenuAction { return }
        if allowReviewedWindowLayouts, request.operation == .windowLayoutAction { return }
        try requireMetadata(request)
    }
    static func requireMetadata(_ request: CompanionRequest) throws {
        switch request.operation {
        case .handshake, .status, .openSession, .closeSession, .cancel: break
        default: throw CompanionError.unsupportedOperation
        }
    }
    private func establishIfNeeded() async throws {
        if ticket != nil { return }
        guard opening == false else { throw CompanionError.tooManyRequests }
        opening = true; defer { opening = false }
        let token = generation
        let hello = CompanionBoundHello(build: build)
        try check(token)
        let offered = try await connector.bootstrap(hello)
        try check(token)
        guard offered.hello == hello else { throw CompanionError.malformedMessage }
        let proof = CompanionBoundProof(ticket: offered)
        let response = try await connector.bind(proof)
        try check(token)
        guard response == proof else { throw CompanionError.malformedMessage }
        ticket = offered
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == generation, invalidated == false else { throw CompanionError.disconnected }
    }
}
