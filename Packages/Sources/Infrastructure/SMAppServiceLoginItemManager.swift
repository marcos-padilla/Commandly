import Foundation
import ServiceManagement

/// Production login-item adapter backed by `SMAppService.mainApp`.
public struct SMAppServiceLoginItemManager: LoginItemManaging, Sendable {
    /// Creates a login-item manager for the main app bundle.
    public init() {}

    public func status() async -> LoginItemStatus {
        mapStatus(SMAppService.mainApp.status)
    }

    public func setEnabled(_ enabled: Bool) async throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            throw LoginItemError.updateFailed
        }
    }

    private func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}
