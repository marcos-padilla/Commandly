import Foundation
import Infrastructure
import os
import Testing
@testable import SystemCompanionKit

struct CompanionBoundAdmissionTests {
    private let user = CompanionUserSession(effectiveUser: 501, auditSession: 34)
    @Test func ticketHasOneConnectionOneBindAndExactInstanceIdentity() throws {
        let clock = CompanionTestClock(); let ticket = CompanionBoundTicket(hello: .init(build: "1"))
        let gate = CompanionBoundAdmission(ticket: ticket, userSession: user, deadline: clock.now().advanced(by: .seconds(5)), clock: clock)
        #expect(gate.isReady == false)
        #expect(gate.claim(.init(effectiveUser: 502, auditSession: 34)) == false)
        #expect(gate.claim(.init(effectiveUser: 501, auditSession: 35)) == false)
        #expect(gate.claim(user))
        #expect(gate.claim(user) == false)
        #expect(throws: CompanionError.unknownSession) { try gate.bind(.init(ticket: .init(hello: ticket.hello)), peer: user) }
        #expect(gate.isReady == false)
        let proof = CompanionBoundProof(ticket: ticket)
        try gate.bind(proof, peer: user)
        #expect(gate.isReady)
        #expect(throws: CompanionError.replayedRequest) { try gate.bind(proof, peer: user) }
        gate.invalidate()
        #expect(gate.isReady == false)
        #expect(gate.claim(user) == false)
    }
    @Test func deadlineIsCheckedInsideAdmissionWithoutDependingOnATimerCallback() throws {
        let clock = CompanionTestClock(); let ticket = CompanionBoundTicket(hello: .init(build: "1"))
        let gate = CompanionBoundAdmission(ticket: ticket, userSession: user, deadline: clock.now().advanced(by: .seconds(5)), clock: clock)
        #expect(gate.claim(user))
        clock.advance(seconds: 5)
        #expect(throws: CompanionError.expiredSession) { try gate.bind(.init(ticket: ticket), peer: user) }
        #expect(gate.isReady == false)
        let closed = CompanionBoundAdmission(ticket: ticket, userSession: user, deadline: clock.now(), clock: clock)
        #expect(closed.claim(user) == false)
    }
    @Test func invalidationBeforeAcceptancePreventsSetupAndClosesRejectedResource() {
        let resource = FixturePeerResource()
        let owner = CompanionBoundConnectionOwner<FixturePeerResource>(activate: { $0.activate() }, close: { $0.close() })
        owner.invalidate()
        #expect(owner.accept(resource) == false)
        #expect(resource.counts == [0, 1])
    }
    @Test func retainedPeerIsExplicitlyClosedOnceAndAnotherCannotReplaceIt() {
        let first = FixturePeerResource(); let second = FixturePeerResource()
        let owner = CompanionBoundConnectionOwner<FixturePeerResource>(activate: { $0.activate() }, close: { $0.close() })
        #expect(owner.accept(first))
        #expect(owner.accept(second) == false)
        #expect(first.counts == [1, 0]); #expect(second.counts == [0, 1])
        owner.invalidate(); owner.invalidate()
        #expect(first.counts == [1, 1])
    }
    @Test func ownershipRetainsThePeerUntilExplicitInvalidation() {
        let owner = CompanionBoundConnectionOwner<FixturePeerResource>(activate: { $0.activate() }, close: { $0.close() })
        var resource: FixturePeerResource? = FixturePeerResource()
        weak let retained = resource
        if let resource { #expect(owner.accept(resource)) }
        resource = nil
        #expect(retained != nil)
        owner.invalidate()
        #expect(retained == nil)
    }
    @Test func concurrentAcceptanceAndInvalidationNeverActivateAfterClose() async {
        let resource = FixturePeerResource()
        let owner = CompanionBoundConnectionOwner<FixturePeerResource>(activate: { $0.activate() }, close: { $0.close() })
        async let accepted = Task { owner.accept(resource) }.value
        async let closed: Void = Task { owner.invalidate() }.value
        _ = await (accepted, closed)
        #expect(resource.counts[1] == 1)
        #expect(resource.activatedAfterClose == false)
    }
    @Test func concurrentBindAndInvalidationCannotLeaveTheGateReady() async {
        let clock = CompanionTestClock(); let ticket = CompanionBoundTicket(hello: .init(build: "1"))
        let gate = CompanionBoundAdmission(ticket: ticket, userSession: user, deadline: clock.now().advanced(by: .seconds(5)), clock: clock)
        #expect(gate.claim(user))
        async let binding: Void = Task { do { try gate.bind(.init(ticket: ticket), peer: user) } catch { #expect(gate.isReady == false) } }.value
        async let closing: Void = Task { gate.invalidate() }.value
        _ = await (binding, closing)
        #expect(gate.isReady == false)
    }
    @Test func wireRejectsUnknownKeysOversizeWrongVersionAndEchoIdentity() throws {
        let hello = CompanionBoundHello(build: "1")
        let bytes = try CompanionBoundWire.encode(hello)
        #expect(try CompanionBoundWire.hello(bytes) == hello)
        var unknown = bytes; unknown.removeLast(); unknown.append(Data(",\"unexpected\":true}".utf8))
        #expect(throws: CompanionError.malformedMessage) { try CompanionBoundWire.hello(unknown) }
        #expect(throws: CompanionError.oversizedMessage) { try CompanionBoundWire.hello(Data(repeating: 32, count: 4_097)) }
        #expect(throws: CompanionError.unsupportedVersion) { try CompanionBoundWire.hello(CompanionBoundWire.encode(CompanionBoundHello(version: 900, build: "1"))) }
        #expect(throws: CompanionError.versionMismatch) { try CompanionBoundWire.ticket(CompanionBoundWire.failure(CompanionError.versionMismatch)) }
    }
}

private final class FixturePeerResource: Sendable {
    private struct State { var activations = 0; var closures = 0; var activatedAfterClose = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func activate() { state.withLock { value in value.activations += 1; value.activatedAfterClose = value.closures > 0 } }
    func close() { state.withLock { $0.closures += 1 } }
    var counts: [Int] { state.withLock { [$0.activations, $0.closures] } }
    var activatedAfterClose: Bool { state.withLock { $0.activatedAfterClose } }
}
