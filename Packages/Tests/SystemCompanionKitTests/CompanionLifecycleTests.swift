import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionLifecycleTests {
    @Test func nativeMetadataTransportRejectsFuturePayloadBeforeAnyNativeConnectionOrSigningCheck() async throws {
        let transport = NativeCompanionTransport()
        let session = UUID()
        let action = CompanionAction.selection(.replace(handle: .init(session: session, target: UUID()), revision: UUID(), reviewedText: "Generated fixture text"))
        let request = CompanionRequest(sequence: 1, build: "1", session: session, operation: .selectionAction, action: action)
        let data = try CompanionWireCodec.encode(request)
        await #expect(throws: CompanionError.unsupportedOperation) { try await transport.exchange(data) }
        #expect(await transport.isConnected() == false)
    }
    @Test func constructionAndStatusAreInertAndEnableDoesNotSilentlyConnect() async throws {
        let registration = TestCompanionRegistration(); let validator = TestCompanionValidator()
        let transport = EngineCompanionTransport()
        let service = SystemCompanionService(registration: registration, validation: validator,
            clientFactory: { CompanionClient(transport: transport, build: $0) })
        #expect(await registration.reads == 0)
        #expect(await service.installation().state == .disabled)
        #expect(await registration.registrations == 0)
        #expect(await validator.calls == 0)
        #expect(try await service.enable().state == .enabled)
        #expect(await registration.registrations == 1)
        #expect(await transport.exchanges == 0)
        let status = try await service.checkConnection()
        #expect(status.capabilities.filter { $0.state == .available }.map(\.capability) == [.metadata])
        #expect(await service.installation().state == .ready)
        #expect(try await service.disable().state == .disabled)
        #expect(await registration.unregistrations == 1)
        #expect(await transport.invalidations == 1)
    }
    @Test func invalidSigningPreventsRegistrationAndApprovalNeverStartsAConnection() async throws {
        let registration = TestCompanionRegistration(); let validator = TestCompanionValidator()
        let transport = EngineCompanionTransport()
        let service = SystemCompanionService(registration: registration, validation: validator,
            clientFactory: { CompanionClient(transport: transport, build: $0) })
        await validator.fail(.invalidSignature)
        await #expect(throws: CompanionError.invalidSignature) { try await service.enable() }
        #expect(await registration.registrations == 0)
        await registration.setState(.needsApproval)
        #expect(await service.installation().state == .needsApproval)
        await #expect(throws: CompanionError.unavailable) { try await service.checkConnection() }
        #expect(await transport.exchanges == 0)
    }
    @Test func mismatchedBuildAndReplyIdentityInvalidateRatherThanBeingTrusted() async throws {
        let mismatch = EngineCompanionTransport(build: "2")
        let client = CompanionClient(transport: mismatch, build: "1")
        await #expect(throws: CompanionError.versionMismatch) { try await client.check() }
        #expect(await mismatch.invalidations == 1)
        let identity = EngineCompanionTransport()
        await identity.setMismatch()
        let second = CompanionClient(transport: identity, build: "1")
        await #expect(throws: CompanionError.malformedMessage) { try await second.check() }
        #expect(await identity.invalidations == 1)
    }
    @Test func lateHandshakeCannotResurrectAnExplicitlyDisconnectedClient() async throws {
        let transport = LateReplyCompanionTransport()
        let client = CompanionClient(transport: transport, build: "1")
        let pending = Task { try await client.check() }
        await transport.waitForRequest()
        await client.disconnect()
        await transport.deliverLateReply()
        await #expect(throws: CompanionError.disconnected) { try await pending.value }
        #expect(await client.isConnected() == false)
    }
    @Test func externalDisableAndFailedUnregisterStillClearTheChannel() async throws {
        let registration = TestCompanionRegistration(); let validator = TestCompanionValidator()
        let transport = EngineCompanionTransport()
        let service = SystemCompanionService(registration: registration, validation: validator,
            clientFactory: { CompanionClient(transport: transport, build: $0) })
        _ = try await service.enable(); _ = try await service.checkConnection()
        await registration.failUnregister()
        await #expect(throws: CompanionError.unregistrationFailed) { try await service.disable() }
        #expect(await transport.isConnected() == false)
        #expect(await service.installation().state == .enabled)
        await registration.setState(.needsApproval)
        #expect(await service.installation().state == .needsApproval)
        #expect(await transport.engine.hasSession == false)
    }
}
