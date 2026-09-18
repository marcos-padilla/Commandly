import Foundation
import Infrastructure
import Testing
@testable import Commandly

private actor WindowLayoutSettingsFixture: SystemCompanionManaging, CompanionWindowLayoutCalling {
    private var connected = false
    private var enabled = false
    private(set) var enableRequests = 0
    func installation() -> CompanionInstallationSnapshot { .init(state: connected ? .ready : .managedByCompanion, status: connected ? status() : nil) }
    func checkConnection() -> CompanionStatus { connected = true; enabled = false; return status() }
    func openSetup() {}
    func enable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    func disable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    func openApprovalSettings() {}
    func disconnect() { connected = false; enabled = false }
    func requestWindowLayout(_ request: CompanionWindowLayoutRequest) throws -> CompanionWindowLayoutReply {
        guard connected, case .setEnabled(let value) = request else { throw CompanionError.disconnected }
        enableRequests += 1; enabled = value; return .enabled(value)
    }
    private func status() -> CompanionStatus {
        .init(build: "1", protocolVersion: CompanionLimits.protocolVersion, capabilities: [.init(capability: .metadata, state: .available), .init(capability: .windows, state: enabled ? .available : .disabled)])
    }
}
@Test @MainActor func windowLayoutCapabilityRequiresExplicitToggleAndResetsAfterDisconnect() async {
    let fixture = WindowLayoutSettingsFixture()
    let model = SystemIntegrationSettingsModel(service: fixture, isFixture: true, windowLayouts: fixture, openAccessibility: {})
    #expect(model.windowLayoutsEnabled == false)
    #expect(model.canChangeWindowLayouts == false)
    model.checkConnection(); await model.waitForWorkForTesting()
    #expect(model.canChangeWindowLayouts)
    #expect(await fixture.enableRequests == 0)
    model.setWindowLayoutsEnabled(true); await model.waitForWorkForTesting()
    #expect(model.windowLayoutsEnabled)
    #expect(await fixture.enableRequests == 1)
    model.disconnect(); await model.waitForWorkForTesting()
    #expect(model.windowLayoutsEnabled == false)
    model.checkConnection(); await model.waitForWorkForTesting()
    #expect(model.windowLayoutsEnabled == false)
    #expect(await fixture.enableRequests == 1)
}
