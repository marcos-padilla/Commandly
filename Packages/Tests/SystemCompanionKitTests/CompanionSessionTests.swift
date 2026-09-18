import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionSessionTests {
    @Test func handshakeBuildVersionReplayAndFutureActionsFailClosed() async throws {
        let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"))
        let before = await engine.receive(.init(sequence: 1, build: "1", operation: .openSession))
        #expect(before.value == .failure(.unknownSession))
        #expect(await engine.receive(.init(version: 99, sequence: 2, build: "1", operation: .handshake)).value == .failure(.unsupportedVersion))
        #expect(await engine.receive(.init(sequence: 3, build: "2", operation: .handshake)).value == .failure(.versionMismatch))
        let handshake = CompanionRequest(sequence: 4, build: "1", operation: .handshake)
        let reply = await engine.receive(handshake)
        guard case .status(let status) = reply.value else { Issue.record("Expected real metadata response"); return }
        #expect(status.capabilities.filter { $0.state == .available }.map(\.capability) == [.metadata])
        #expect(await engine.receive(handshake).value == .failure(.replayedRequest))
        let token = try await openSession(engine, sequence: 5)
        let action = CompanionAction.window(.init(handle: .init(session: token, target: UUID()), action: .activate))
        #expect(await engine.receive(.init(sequence: 6, build: "1", session: token, operation: .windowAction, action: action)).value == .failure(.unsupportedOperation))
        #expect(await engine.receive(.init(sequence: 7, build: "1", session: UUID(), operation: .status)).value == .failure(.unknownSession))
        #expect(await engine.receive(.init(sequence: 8, build: "1", session: token, operation: .closeSession)).value == .acknowledged)
        #expect(await engine.hasSession == false)
    }
    @Test func sessionExpirationAndInvalidationClearAuthority() async throws {
        let clock = CompanionTestClock()
        let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"), clock: clock)
        _ = await engine.receive(.init(sequence: 1, build: "1", operation: .handshake))
        let token = try await openSession(engine, sequence: 2)
        clock.advance(seconds: 300)
        #expect(await engine.receive(.init(sequence: 3, build: "1", session: token, operation: .status)).value == .failure(.expiredSession))
        #expect(await engine.hasSession == false)
        await engine.invalidate()
        #expect(await engine.receive(.init(sequence: 4, build: "1", operation: .openSession)).value == .failure(.disconnected))
    }
    @Test func explicitCancelAndDisconnectCancelPendingMetadata() async throws {
        let metadata = PausingCompanionMetadata()
        let engine = CompanionSessionEngine(build: "1", metadata: metadata)
        _ = await engine.receive(.init(sequence: 1, build: "1", operation: .handshake))
        let token = try await openSession(engine, sequence: 2)
        await metadata.setPaused()
        let request = CompanionRequest(sequence: 3, build: "1", session: token, operation: .status)
        let pending = Task { await engine.receive(request) }
        await metadata.waitForCalls(1)
        #expect(await engine.receive(.init(sequence: 4, build: "1", session: token, operation: .cancel, cancelRequestID: request.id)).value == .acknowledged)
        #expect(await pending.value.value == .failure(.canceled))
        let second = Task { await engine.receive(.init(sequence: 5, build: "1", session: token, operation: .status)) }
        await metadata.waitForCalls(1)
        await engine.invalidate()
        let result = await second.value
        #expect(result.value == .failure(.canceled) || result.value == .failure(.disconnected))
        #expect(await engine.hasSession == false)
        #expect(await engine.activeRequestCount == 0)
    }
    @Test func eightInFlightRequestsAreBoundedAndDeadlineUsesInjectedClock() async throws {
        let metadata = PausingCompanionMetadata(); let clock = CompanionTestClock()
        let engine = CompanionSessionEngine(build: "1", metadata: metadata, clock: clock)
        _ = await engine.receive(.init(sequence: 1, build: "1", operation: .handshake))
        let token = try await openSession(engine, sequence: 2)
        await metadata.setPaused()
        let tasks = (3...10).map { sequence in Task { await engine.receive(.init(sequence: UInt64(sequence), build: "1", session: token, operation: .status)) } }
        await metadata.waitForCalls(8); await clock.waitForSleepers(8)
        #expect(await engine.receive(.init(sequence: 11, build: "1", session: token, operation: .status)).value == .failure(.tooManyRequests))
        clock.advance(seconds: 5)
        for task in tasks { #expect(await task.value.value == .failure(.timedOut)) }
        #expect(await engine.activeRequestCount == 0)
    }
    @Test func requestLedgerNeverEvictsAnOldRequestIntoReplayability() async throws {
        let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"))
        _ = await engine.receive(.init(sequence: 1, build: "1", operation: .handshake))
        let token = try await openSession(engine, sequence: 2)
        for sequence in 3...256 {
            let reply = await engine.receive(.init(sequence: UInt64(sequence), build: "1", session: token, operation: .cancel, cancelRequestID: UUID()))
            #expect(reply.value == .acknowledged)
        }
        #expect(await engine.receive(.init(sequence: 257, build: "1", session: token, operation: .status)).value == .failure(.expiredSession))
        #expect(await engine.hasSession == false)
    }
    private func openSession(_ engine: CompanionSessionEngine, sequence: UInt64) async throws -> UUID {
        let reply = await engine.receive(.init(sequence: sequence, build: "1", operation: .openSession))
        guard case .session(let token) = reply.value else { throw CompanionError.unknownSession }
        return token
    }
}
