import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

private actor LayoutMutationFixture: CompanionWindowLayoutMutationPort {
    let resize: CompanionWindowMutationState
    let position: CompanionWindowMutationState
    private(set) var positionCalls = 0
    init(resize: CompanionWindowMutationState, position: CompanionWindowMutationState) { self.resize = resize; self.position = position }
    func validateMutation(_ id: UUID) {}
    func resizeMutation(_ id: UUID) -> CompanionWindowMutationState { resize }
    func positionMutation(_ id: UUID) -> CompanionWindowMutationState { positionCalls += 1; return position }
    func readbackMutation(_ id: UUID) throws -> Bool { throw CompanionWindowLayoutError.unavailable }
}
@Test func uncertainResizeNeverMovesOrClaimsNoChange() async throws {
    let port = LayoutMutationFixture(resize: .unknown, position: .accepted)
    let receipt = try await CompanionWindowLayoutMutation.run(id: UUID(), port: port)
    #expect(receipt.outcome == .uncertain)
    #expect(receipt.positionState == .notAttempted)
    #expect(await port.positionCalls == 0)
    #expect(NativeCompanionWindowLayoutWorker.writeState(.cannotComplete) == .unknown)
}
@Test func uncertainMovePreservesConfirmedResize() async throws {
    let port = LayoutMutationFixture(resize: .accepted, position: .unknown)
    let receipt = try await CompanionWindowLayoutMutation.run(id: UUID(), port: port)
    #expect(receipt.outcome == .uncertain)
    #expect(receipt.resizeAccepted)
    #expect(receipt.readbackAvailable == false)
    #expect(await port.positionCalls == 1)
}
@Test func layoutCodecRejectsImpossibleReadbackFlags() throws {
    let receipt = CompanionWindowLayoutReceipt(resizeState: .accepted, positionState: .accepted, readbackMatches: true, readbackAvailable: true)
    let data = try CompanionWireCodec.encode(CompanionReply(requestID: UUID(), value: .windowLayout(.applied(receipt))))
    let invalid = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"readbackAvailable\":true", with: "\"readbackAvailable\":false")
    #expect(throws: CompanionError.malformedMessage) { try CompanionWireCodec.decodeReply(Data(invalid.utf8)) }
}
