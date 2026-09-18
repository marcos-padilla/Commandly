import Foundation
import Infrastructure
@testable import SystemCompanionKit

actor BoundFixtureConnector: CompanionBoundConnecting {
    enum Mode: Sendable { case normal, wrongSigner, wrongUser, replacedTicket, replacedEndpoint, invalidEndpoint, malformedEcho }
    enum Stage: Sendable { case bootstrap, bind, metadata, connected }
    let mode: Mode
    let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"))
    var bootstrapCalls = 0; var bindCalls = 0; var metadataCalls = 0; var invalidations = 0
    var namedBytes: [Data] = []
    private var ready = false
    private var suspendedStage: Stage?
    private var paused: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(_ mode: Mode = .normal) { self.mode = mode }
    func pause(at stage: Stage) { suspendedStage = stage }
    func waitUntilPaused() async { if paused != nil { return }; await withCheckedContinuation { observer = $0 } }
    func resume() { let old = paused; paused = nil; old?.resume() }
    private func suspendIfNeeded(_ stage: Stage) async {
        if suspendedStage == stage {
            suspendedStage = nil
            await withCheckedContinuation { continuation in paused = continuation; observer?.resume(); observer = nil }
        }
    }
    func bootstrap(_ hello: CompanionBoundHello) async throws -> CompanionBoundTicket {
        bootstrapCalls += 1; namedBytes.append(try CompanionBoundWire.encode(hello))
        await suspendIfNeeded(.bootstrap)
        if mode == .wrongSigner { throw CompanionError.invalidSignature }
        if mode == .wrongUser { throw CompanionError.wrongUserSession }
        if mode == .replacedTicket { return .init(hello: .init(build: hello.build)) }
        return .init(hello: hello)
    }
    func bind(_ proof: CompanionBoundProof) async throws -> CompanionBoundProof {
        bindCalls += 1; await suspendIfNeeded(.bind)
        if mode == .invalidEndpoint { throw CompanionError.disconnected }
        if mode == .replacedEndpoint { return .init(ticket: .init(hello: proof.ticket.hello), challenge: proof.challenge) }
        ready = true; return proof
    }
    func exchangeMetadata(_ data: Data) async throws -> Data {
        metadataCalls += 1; await suspendIfNeeded(.metadata)
        let request = try CompanionWireCodec.decodeRequest(data)
        let reply = await engine.receive(request)
        if mode == .malformedEcho { return try CompanionWireCodec.encode(.init(requestID: UUID(), value: reply.value)) }
        return try CompanionWireCodec.encode(reply)
    }
    func isConnected() async -> Bool { let value = ready; await suspendIfNeeded(.connected); return value }
    func invalidate() { invalidations += 1; ready = false }
}

actor SnapshotCompanionTransport: CompanionTransport {
    let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"))
    private var connected = true
    private var pauseSnapshot = false
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func exchange(_ data: Data) async throws -> Data {
        try await CompanionWireCodec.encode(engine.receive(CompanionWireCodec.decodeRequest(data)))
    }
    func pauseNextSnapshot() { pauseSnapshot = true }
    func isConnected() async -> Bool {
        let snapshot = connected
        if pauseSnapshot {
            pauseSnapshot = false
            await withCheckedContinuation { pending = $0; observer?.resume(); observer = nil }
        }
        return snapshot
    }
    func waitForSnapshot() async { if pending != nil { return }; await withCheckedContinuation { observer = $0 } }
    func deliverSnapshot() { let old = pending; pending = nil; old?.resume() }
    func invalidate() { connected = false }
}
