import Foundation
import Infrastructure
import os
@testable import SystemCompanionKit

final class CompanionTestClock: CompanionDeadlineClock {
    private struct State {
        var now = ContinuousClock().now
        var waits: [UUID: (ContinuousClock.Instant, CheckedContinuation<Void, any Error>)] = [:]
        var canceled: Set<UUID> = []
        var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func now() -> ContinuousClock.Instant { state.withLock { $0.now } }
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if state.canceled.remove(id) != nil || Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    if state.now >= deadline { continuation.resume(); return }
                    state.waits[id] = (deadline, continuation)
                    let count = state.waits.count
                    let ready = state.observers.filter { count >= $0.0 }
                    state.observers.removeAll { count >= $0.0 }
                    for (_, observer) in ready { observer.resume() }
                }
            }
        } onCancel: {
            self.state.withLock { state in
                if let (_, waiter) = state.waits.removeValue(forKey: id) { waiter.resume(throwing: CancellationError()) }
                else { state.canceled.insert(id) }
            }
        }
    }
    func waitForSleepers(_ count: Int) async {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if state.waits.count >= count { continuation.resume() }
                else { state.observers.append((count, continuation)) }
            }
        }
    }
    func advance(seconds: Int) {
        state.withLock { state in
            state.now = state.now.advanced(by: .seconds(seconds))
            let ready = state.waits.filter { $0.value.0 <= state.now }
            for (id, (_, waiter)) in ready { state.waits[id] = nil; waiter.resume() }
        }
    }
}

actor PausingCompanionMetadata: CompanionMetadataProviding {
    private var paused = false
    private var waits: [UUID: CheckedContinuation<CompanionStatus, any Error>] = [:]
    private var canceled: Set<UUID> = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func setPaused() { paused = true }
    func status() async throws -> CompanionStatus {
        if paused == false { return FoundationCompanionMetadata(build: "1").status() }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if canceled.remove(id) != nil || Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waits[id] = continuation
                let ready = observers.filter { waits.count >= $0.0 }
                observers.removeAll { waits.count >= $0.0 }
                for (_, observer) in ready { observer.resume() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func waitForCalls(_ count: Int) async {
        await withCheckedContinuation { continuation in
            if waits.count >= count { continuation.resume() }
            else { observers.append((count, continuation)) }
        }
    }
    private func cancel(_ id: UUID) {
        if let continuation = waits.removeValue(forKey: id) { continuation.resume(throwing: CancellationError()) }
        else { canceled.insert(id) }
    }
}

actor EngineCompanionTransport: CompanionTransport {
    let engine: CompanionSessionEngine
    var invalidations = 0
    var exchanges = 0
    var connected = false
    var mismatch = false
    init(build: String = "1") { engine = CompanionSessionEngine(build: build, metadata: FoundationCompanionMetadata(build: build)) }
    func exchange(_ request: Data) async throws -> Data {
        exchanges += 1; connected = true
        let value = try CompanionWireCodec.decodeRequest(request)
        let reply = await engine.receive(value)
        return try CompanionWireCodec.encode(mismatch ? .init(requestID: UUID(), value: reply.value) : reply)
    }
    func isConnected() -> Bool { connected }
    func invalidate() async { invalidations += 1; connected = false; await engine.invalidate() }
    func setMismatch() { mismatch = true }
}

actor TestCompanionRegistration: CompanionServiceRegistering {
    var current: CompanionInstallationState = .disabled
    var reads = 0; var registrations = 0; var unregistrations = 0; var settings = 0
    var unregisterFails = false
    func state() -> CompanionInstallationState { reads += 1; return current }
    func register() { registrations += 1; current = .enabled }
    func unregister() throws {
        unregistrations += 1
        if unregisterFails { throw CompanionError.unregistrationFailed }
        current = .disabled
    }
    func openApprovalSettings() { settings += 1 }
    func setState(_ value: CompanionInstallationState) { current = value }
    func failUnregister() { unregisterFails = true }
}
actor TestCompanionValidator: CompanionInstallationValidating {
    var calls = 0
    var error: CompanionError?
    func validate() throws -> String { calls += 1; if let error { throw error }; return "1" }
    func fail(_ error: CompanionError) { self.error = error }
}

actor LateReplyCompanionTransport: CompanionTransport {
    private var waiter: CheckedContinuation<Data, any Error>?
    private var response: Data?
    private var observation: CheckedContinuation<Void, Never>?
    private var connected = true
    func exchange(_ bytes: Data) async throws -> Data {
        let request = try CompanionWireCodec.decodeRequest(bytes)
        response = try CompanionWireCodec.encode(.init(requestID: request.id, value: .status(FoundationCompanionMetadata(build: "1").status())))
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            observation?.resume(); observation = nil
        }
    }
    func waitForRequest() async {
        if waiter != nil { return }
        await withCheckedContinuation { observation = $0 }
    }
    func deliverLateReply() {
        if let waiter, let response { self.waiter = nil; waiter.resume(returning: response) }
    }
    func isConnected() -> Bool { connected }
    func invalidate() { connected = false }
}
