import AppKit
import Foundation
import Infrastructure
import ServiceManagement

/// Opens the sealed embedded helper as an independent application, not a spawned sandbox-inheriting child.
/// No arguments, environment variables, Apple events, or payloads are passed. The helper's default mode is setup.
@MainActor
public final class NativeCompanionSetupOpener: CompanionSetupOpening {
    private let applicationURL: URL
    private let validation: NativeCompanionInstallationValidator
    private var setupApplication: NSRunningApplication?
    public init(applicationURL: URL) {
        self.applicationURL = applicationURL
        validation = NativeCompanionInstallationValidator(applicationURL: applicationURL)
    }
    public func openSetup() async throws {
        _ = try await validation.validate()
        try Task.checkCancellation()
        if let setupApplication, setupApplication.isTerminated == false {
            guard setupApplication.activate(options: [.activateAllWindows]) else { throw CompanionError.unavailable }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true; configuration.hides = false; configuration.addsToRecentItems = false
        // A running --service process must never absorb a request for the visible setup application.
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        // AppKit explicitly ignores OpenConfiguration.arguments for a sandboxed caller. No argument workaround.
        let helper = applicationURL.appendingPathComponent(CompanionIdentity.helperRelativePath, isDirectory: true)
        do { setupApplication = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration) }
        catch { throw CompanionSetupFailure(reason: .unavailable, diagnostic: .init(error: error)) }
    }
    public func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}
