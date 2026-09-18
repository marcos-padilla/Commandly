import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

@Suite struct CompanionKeyboardRoutingTests {
    @Test @MainActor func boundGateAndSessionOptInAreRequired() async throws {
        let session = UUID()
        let config = CompanionKeyboardConfiguration(keys: [.init(id: UUID(), key: .f6)])
        let request = CompanionRequest(sequence: 1, build: "1", session: session,
            operation: .keyboardTriggerAction, action: .keyboardTrigger(.configure(config)))
        #expect(throws: CompanionError.unsupportedOperation) { try CompanionBoundTransport.requireMetadata(request) }
        #expect(throws: CompanionError.unsupportedOperation) { try CompanionBoundTransport.requireBoundAllowed(request, allowReviewedWindowLayouts: false) }
        try CompanionBoundTransport.requireBoundAllowed(request, allowReviewedWindowLayouts: false, allowReviewedKeyboardTriggers: true)
        #expect(try CompanionWireCodec.decodeRequest(CompanionWireCodec.encode(request)) == request)
        let driver = RoutingKeyboardDriver()
        let engine = CompanionSessionEngine(build: "1", metadata: FoundationCompanionMetadata(build: "1"))
        let controller = CompanionKeyboardController(driver: driver)
        try await engine.installBoundKeyboardTriggers(controller)
        _ = await engine.receive(.init(sequence: 1, build: "1", operation: .handshake))
        let opened = await engine.receive(.init(sequence: 2, build: "1", operation: .openSession))
        guard case .session(let token) = opened.value else { Issue.record("Expected session"); return }
        #expect(await driver.starts == 0)
        let configured = await engine.receive(.init(sequence: 3, build: "1", session: token,
            operation: .keyboardTriggerAction, action: .keyboardTrigger(.configure(config))))
        #expect(configured.value == .keyboardTrigger(.configured(config.revision)))
        #expect(await driver.starts == 1)
        await engine.invalidate()
        #expect(!controller.lease.permits(session: token, revision: config.revision))
    }
}
private actor RoutingKeyboardDriver: CompanionKeyboardDriving {
    private(set) var starts = 0
    func start(configuration: CompanionKeyboardConfiguration, authorized: @escaping @Sendable () -> Bool,
               activation: @escaping @Sendable (UUID) -> Void, stopped: @escaping @Sendable () -> Void) { starts += 1 }
    func stop() {}
}
