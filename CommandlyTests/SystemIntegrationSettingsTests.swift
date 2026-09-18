import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct SystemIntegrationSettingsTests {
    @Test func generatedMainOpensSetupThenChecksAndDisconnectsOnlyItsChannel() async throws {
        let services = SystemCompanionApplicationServices.inMemory()
        let model = services.settings
        #expect(model.snapshot.state == .managedByCompanion && model.isFixture)
        model.refresh(); await model.waitForWorkForTesting()
        #expect(model.snapshot.state == .managedByCompanion)
        model.openSetup(); await model.waitForWorkForTesting()
        #expect(model.snapshot.state == .managedByCompanion)
        #expect(model.message?.contains("No native registration") == true)
        model.checkConnection(); await model.waitForWorkForTesting()
        #expect(model.snapshot.state == .ready)
        #expect(model.snapshot.status?.capabilities.filter { $0.state == .available }.map(\.capability) == [.metadata])
        model.disconnect(); await model.waitForWorkForTesting()
        #expect(model.snapshot.state == .managedByCompanion)
        #expect(model.message?.contains("registration and macOS permissions are unchanged") == true)
        await #expect(throws: CompanionError.unsupportedOperation) { try await services.manager.disable() }
    }
}
