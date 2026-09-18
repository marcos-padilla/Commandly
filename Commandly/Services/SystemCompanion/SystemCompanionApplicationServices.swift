import Foundation
import Infrastructure
import SystemCompanionKit

@MainActor
struct SystemCompanionApplicationServices {
    let manager: any SystemCompanionManaging
    let settings: SystemIntegrationSettingsModel
    let keyboardTriggers: any CompanionKeyboardTriggerOperating
    let appMenus: any CompanionAppMenuCalling
    let windowLayouts: any CompanionWindowLayoutCalling
    static func live(applicationURL: URL = Bundle.main.bundleURL) -> Self {
        let manager = CompanionMainService(opening: NativeCompanionSetupOpener(applicationURL: applicationURL),
            validation: NativeCompanionInstallationValidator(applicationURL: applicationURL),
            clientFactory: { build in
                let allow = CompanionWindowLayoutReleaseGate.reviewed
                let connector = NativeCompanionBoundConnector(allowReviewedWindowLayouts: allow, allowReviewedAppMenus: CompanionAppMenuReleaseGate.reviewed, allowReviewedKeyboardTriggers: CompanionKeyboardTriggerReleaseGate.reviewed)
                return CompanionClient(transport: CompanionBoundTransport(build: build, connector: connector, allowReviewedWindowLayouts: allow, allowReviewedAppMenus: CompanionAppMenuReleaseGate.reviewed, allowReviewedKeyboardTriggers: CompanionKeyboardTriggerReleaseGate.reviewed), build: build)
            })
        return .init(manager: manager, settings: SystemIntegrationSettingsModel(service: manager, windowLayouts: manager, appMenus: manager), keyboardTriggers: manager, appMenus: manager, windowLayouts: manager)
    }
    static func inMemory() -> Self {
        let manager = GeneratedSystemCompanionManager()
        return .init(manager: manager, settings: SystemIntegrationSettingsModel(service: manager, isFixture: true), keyboardTriggers: UnavailableCompanionKeyboardTriggers(), appMenus: UnavailableCompanionAppMenuCaller(), windowLayouts: UnavailableCompanionWindowLayoutCaller())
    }
}

private actor GeneratedSystemCompanionManager {
    private var state: CompanionInstallationState = .managedByCompanion
    func installation() -> CompanionInstallationSnapshot { .init(state: state) }
    func openSetup() {}
    func enable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    func disable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    func checkConnection() async throws -> CompanionStatus {

        state = .ready
        return FoundationCompanionMetadata(build: "1").status()
    }
    func openApprovalSettings() {}
    func disconnect() { state = .managedByCompanion }
}
extension GeneratedSystemCompanionManager: SystemCompanionManaging {}
