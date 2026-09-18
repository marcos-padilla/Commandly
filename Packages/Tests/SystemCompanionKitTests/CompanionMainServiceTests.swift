import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionMainServiceTests {
    @Test func mainOpensSetupWithoutRegisteringOrConnectingAndCannotUseOwnerMutations() async throws {
        let opener = SetupFixtureOpener(); let validation = TestCompanionValidator(); let transport = EngineCompanionTransport()
        let service = CompanionMainService(opening: opener, validation: validation, clientFactory: { CompanionClient(transport: transport, build: $0) })
        #expect(await service.installation().state == .managedByCompanion)
        #expect(await opener.opens == 0)
        #expect(await validation.calls == 0)
        try await service.openSetup()
        #expect(await opener.opens == 1)
        #expect(await transport.exchanges == 0)
        #expect(await service.installation().state == .managedByCompanion)
        await #expect(throws: CompanionError.unsupportedOperation) { try await service.enable() }
        await #expect(throws: CompanionError.unsupportedOperation) { try await service.disable() }
        _ = try await service.checkConnection()
        #expect(await service.installation().state == .ready)
        await service.disconnect()
        #expect(await service.installation().state == .managedByCompanion)
        #expect(await opener.opens == 1)
        #expect(await transport.invalidations == 1)
    }
    @Test func changedGenerationBeforeSetupLaunchDiscardsOldValidatedRequest() async throws {
        let opener = SetupFixtureOpener(); let validation = SetupPausedValidator(); let transport = EngineCompanionTransport()
        let service = CompanionMainService(opening: opener, validation: validation, clientFactory: { CompanionClient(transport: transport, build: $0) })
        let operation = Task { try await service.openSetup() }
        await validation.waitUntilPaused(); await service.disconnect(); await validation.resume()
        await #expect(throws: CompanionError.canceled) { try await operation.value }
        #expect(await opener.opens == 0)
    }
    @Test func staleConnectionDoesNotClaimRegistrationOrReady() async throws {
        let opener = SetupFixtureOpener(); let transport = SnapshotCompanionTransport()
        let service = CompanionMainService(opening: opener, validation: TestCompanionValidator(), clientFactory: { CompanionClient(transport: transport, build: $0) })
        _ = try await service.checkConnection()
        await transport.pauseNextSnapshot()
        let snapshot = Task { await service.installation() }
        await transport.waitForSnapshot(); await service.disconnect(); await transport.deliverSnapshot()
        #expect(await snapshot.value.state == .managedByCompanion)
        #expect(await snapshot.value.status == nil)
    }
}
private actor SetupFixtureOpener: CompanionSetupOpening {
    var opens = 0; var settings = 0
    func openSetup() { opens += 1 }
    func openApprovalSettings() { settings += 1 }
}
