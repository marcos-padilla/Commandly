import Foundation
import Infrastructure
import Observation

@Observable
@MainActor
final class SystemCompanionSetupModel {
    private(set) var snapshot = CompanionSetupSnapshot(state: .unavailable)
    private(set) var isBusy = false
    private(set) var message: String?
    var showsEnableExplanation = false
    @ObservationIgnored private let service: any CompanionSetupManaging
    @ObservationIgnored private var work: Task<Void, Never>?
    init(service: any CompanionSetupManaging) { self.service = service }
    func refresh() { run { [service] in await service.snapshot() } }
    func requestEnable() { if isBusy == false { showsEnableExplanation = true } }
    func confirmEnable() { showsEnableExplanation = false; run { [service] in try await service.enable() } }
    func disable() { run { [service] in try await service.disable() } }
    func openSettings() { Task { [service] in await service.openApprovalSettings() } }
    func permitsClosing() -> Bool {
        if isBusy { message = "Wait for the current macOS operation to finish before closing this setup window."; return false }
        return true
    }
    var stateTitle: String {
        switch snapshot.state {
        case .disabled: "Background Service Disabled"
        case .enabled, .ready: "Background Service Enabled"
        case .needsApproval: "Needs Approval in Login Items"
        case .notInstalled: "Service Not Found"
        case .versionMismatch: "Versions Do Not Match"
        case .managedByCompanion, .unavailable: "Status Unavailable"
        }
    }
    private func run(_ operation: @escaping @Sendable () async throws -> CompanionSetupSnapshot) {
        guard isBusy == false else { return }
        isBusy = true; message = nil
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isBusy = false; work = nil }
            do {
                snapshot = try await operation()
                if let reason = snapshot.error { message = Self.message(reason) }
            } catch {
                snapshot = await service.snapshot()
                let reason = (error as? CompanionSetupFailure)?.reason ?? (error as? CompanionError) ?? .unavailable
                message = Self.message(reason)
            }
        }
    }
    private static func message(_ reason: CompanionError) -> String {
        switch reason {
        case .invalidSignature: "Use the correctly signed companion bundled with Commandly. This copy could not be verified."
        case .invalidConfiguration, .missingProvisioningProfile: "The bundled service configuration is incomplete. Install a matching Commandly build."
        case .versionMismatch: "The companion and Commandly builds must match. Install the complete matching app."
        case .registrationFailed: "macOS did not confirm registration. Refresh the status and review Login Items."
        case .unregistrationFailed: "macOS did not confirm that the background service was disabled. Retry Disable and review Login Items."
        case .wrongUserSession: "Open this setup app in your normal logged-in user account. Root and other login sessions are not supported."
        default: "The operation could not be completed. Refresh the status before trying again."
        }
    }
}
