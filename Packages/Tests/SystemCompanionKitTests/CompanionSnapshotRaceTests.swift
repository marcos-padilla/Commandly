import Testing
@testable import SystemCompanionKit

struct CompanionSnapshotRaceTests {
    @Test func disconnectDuringClientStatusReadCannotReturnConnected() async throws {
        let transport = SnapshotCompanionTransport()
        let client = CompanionClient(transport: transport, build: "1"); _ = try await client.check()
        await transport.pauseNextSnapshot()
        let status = Task { await client.isConnected() }
        await transport.waitForSnapshot(); await client.disconnect(); await transport.deliverSnapshot()
        #expect(await status.value == false)
    }
    @Test func disableDuringServiceStatusReadCannotReturnStaleReady() async throws {
        let transport = SnapshotCompanionTransport(); let registration = TestCompanionRegistration()
        let service = SystemCompanionService(registration: registration, validation: TestCompanionValidator(),
            clientFactory: { CompanionClient(transport: transport, build: $0) })
        _ = try await service.enable(); _ = try await service.checkConnection()
        await transport.pauseNextSnapshot()
        let status = Task { await service.installation() }
        await transport.waitForSnapshot(); _ = try await service.disable(); await transport.deliverSnapshot()
        #expect(await status.value.state != .ready)
        #expect(await status.value.status == nil)
        #expect(await service.installation().state == .disabled)
    }
}
