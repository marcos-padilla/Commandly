import Foundation

/// A native diagnostic retains only an allowlisted domain and numeric code, never localized descriptions/userInfo.
public struct CompanionNativeDiagnostic: Equatable, Sendable {
    public enum Domain: String, Sendable { case serviceManagement = "SMAppServiceErrorDomain", cocoa = "NSCocoaErrorDomain", posix = "NSPOSIXErrorDomain", osStatus = "NSOSStatusErrorDomain", other = "Other macOS error" }
    public let domain: Domain
    public let code: Int
    public init(error: any Error) {
        let native = error as NSError
        domain = Domain(rawValue: native.domain) ?? .other
        code = Int(Int32(clamping: native.code))
    }
}
/// Sanitized failure from a registration operation, with no native description or filesystem paths.
public struct CompanionSetupFailure: Error, Sendable {
    public let reason: CompanionError
    public let diagnostic: CompanionNativeDiagnostic?
    public init(reason: CompanionError, diagnostic: CompanionNativeDiagnostic? = nil) { self.reason = reason; self.diagnostic = diagnostic }
}
/// Setup state is owned by the independent companion, which can read its own Service Management registration.
public struct CompanionSetupSnapshot: Equatable, Sendable {
    public let state: CompanionInstallationState
    public let error: CompanionError?
    public let diagnostic: CompanionNativeDiagnostic?
    public init(state: CompanionInstallationState, error: CompanionError? = nil, diagnostic: CompanionNativeDiagnostic? = nil) {
        self.state = state; self.error = error; self.diagnostic = diagnostic
    }
}
/// Only a visible, unsandboxed companion setup flow uses this registration interface.
public protocol CompanionSetupManaging: Sendable {
    func snapshot() async -> CompanionSetupSnapshot
    func enable() async throws -> CompanionSetupSnapshot
    func disable() async throws -> CompanionSetupSnapshot
    func openApprovalSettings() async
}
/// Launches the verified companion application through the normal application-launch boundary.
public protocol CompanionSetupOpening: Sendable {
    func openSetup() async throws
    func openApprovalSettings() async
}
