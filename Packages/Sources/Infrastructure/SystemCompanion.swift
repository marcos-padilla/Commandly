import Foundation

/// Closed cross-application domains. Availability is independently reported; a connection is not a grant.
public enum CompanionCapability: String, Codable, CaseIterable, Sendable { case metadata, windows, menus, selectedText, configuredTriggers, applicationLifecycle }
/// The foundation implements metadata only and reports future capabilities honestly.
public enum CompanionCapabilityState: String, Codable, Sendable { case available, notImplemented, disabled, needsPermission, unavailable }
/// A capability's state contains no captured user content or raw OS permission data.
public struct CompanionCapabilityStatus: Codable, Equatable, Sendable {
    public let capability: CompanionCapability
    public let state: CompanionCapabilityState
    public init(capability: CompanionCapability, state: CompanionCapabilityState) { self.capability = capability; self.state = state }
}
/// Authenticated metadata for an exact compatible companion build.
public struct CompanionStatus: Codable, Equatable, Sendable {
    public let build: String
    public let protocolVersion: Int
    public let capabilities: [CompanionCapabilityStatus]
    public init(build: String, protocolVersion: Int, capabilities: [CompanionCapabilityStatus]) {
        self.build = build; self.protocolVersion = protocolVersion; self.capabilities = capabilities
    }
}
/// Installation state is distinct from protocol compatibility and capability permission.
public enum CompanionInstallationState: String, Equatable, Sendable { case notInstalled, disabled, needsApproval, enabled, ready, versionMismatch, unavailable, managedByCompanion }
/// Fixed recovery reasons deliberately exclude underlying native error descriptions and private paths.
public enum CompanionError: String, Codable, Error, Sendable {
    case unavailable, invalidSignature, missingProvisioningProfile, invalidConfiguration, wrongUserSession
    case malformedMessage, oversizedMessage, unsupportedVersion, versionMismatch, replayedRequest, unknownSession
    case expiredSession, tooManyRequests, canceled, timedOut, disconnected, unsupportedOperation, registrationFailed, unregistrationFailed
}
/// Read-only registration metadata; refreshing it does not open a channel or launch a service.
public struct CompanionInstallationSnapshot: Equatable, Sendable {
    public let state: CompanionInstallationState
    public let error: CompanionError?
    public let status: CompanionStatus?
    public init(state: CompanionInstallationState, error: CompanionError? = nil, status: CompanionStatus? = nil) {
        self.state = state; self.error = error; self.status = status
    }
}
/// Explicit setup boundary. Constructors and status reads must not register or connect.
public protocol SystemCompanionManaging: Sendable {
    func installation() async -> CompanionInstallationSnapshot
    /// Opens the separately signed companion setup app. It does not register or grant any capability.
    func openSetup() async throws
    func enable() async throws -> CompanionInstallationSnapshot
    func disable() async throws -> CompanionInstallationSnapshot
    func checkConnection() async throws -> CompanionStatus
    func openApprovalSettings() async
    func disconnect() async
}

/// Existing owner-only implementations do not silently claim to open an external setup application.
public extension SystemCompanionManaging {
    func openSetup() async throws { throw CompanionError.unsupportedOperation }
}
