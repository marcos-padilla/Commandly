import AppKit
import Foundation
import Infrastructure
import Observation

@Observable
@MainActor
final class SystemIntegrationSettingsModel {
    private(set) var snapshot = CompanionInstallationSnapshot(state: .managedByCompanion)
    private(set) var isBusy = false
    private(set) var message: String?
    let isFixture: Bool
    @ObservationIgnored private let appMenus: any CompanionAppMenuCalling
    @ObservationIgnored private let windowLayouts: any CompanionWindowLayoutCalling
    @ObservationIgnored private let openAccessibility: @MainActor () -> Void
    @ObservationIgnored private let service: any SystemCompanionManaging
    @ObservationIgnored private var work: Task<Void, Never>?
    init(service: any SystemCompanionManaging, isFixture: Bool = false,
         windowLayouts: any CompanionWindowLayoutCalling = UnavailableCompanionWindowLayoutCaller(),
         appMenus: any CompanionAppMenuCalling = UnavailableCompanionAppMenuCaller(),
         openAccessibility: @escaping @MainActor () -> Void = {
             guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
             NSWorkspace.shared.open(url)
         }) {
        self.service = service; self.isFixture = isFixture; self.windowLayouts = windowLayouts; self.appMenus = appMenus; self.openAccessibility = openAccessibility
    }
    var appMenusEnabled: Bool { snapshot.state == .ready && snapshot.status?.capabilities.contains(.init(capability: .menus, state: .available)) == true }
    var canChangeAppMenus: Bool {
        snapshot.state == .ready && snapshot.status?.capabilities.contains(where: { $0.capability == .menus && [.available, .disabled, .needsPermission].contains($0.state) }) == true
    }
    func setAppMenusEnabled(_ enabled: Bool) {
        guard canChangeAppMenus else { return }
        run(success: enabled ? "App Menus enabled for this connection. Accessibility is checked when you read menus; no permission was granted." : "App Menus disabled. Remembered app and menu targets were cleared.") { [appMenus, service] in
            guard case .enabled(let actual) = try await appMenus.requestAppMenu(.setEnabled(enabled)), actual == enabled else { throw CompanionError.unavailable }
            return await service.installation()
        }
    }
    var windowLayoutsEnabled: Bool { snapshot.state == .ready && snapshot.status?.capabilities.contains(.init(capability: .windows, state: .available)) == true }
    var canChangeWindowLayouts: Bool {
        snapshot.state == .ready && snapshot.status?.capabilities.contains(where: { $0.capability == .windows && [.available, .disabled, .needsPermission].contains($0.state) }) == true
    }
    func setWindowLayoutsEnabled(_ enabled: Bool) {
        guard canChangeWindowLayouts else { return }
        run(success: enabled ? "Window Layouts enabled for this connection. Accessibility is checked when you apply a layout; no permission was granted." : "Window Layouts disabled. Remembered app and window targets were cleared.") { [windowLayouts, service] in
            guard case .enabled(let actual) = try await windowLayouts.requestWindowLayout(.setEnabled(enabled)), actual == enabled else { throw CompanionError.unavailable }
            return await service.installation()
        }
    }
    func openWindowAccessibilitySettings() { openAccessibility() }
    func refresh() { run { [service] in await service.installation() } }
    func openSetup() {
        run(success: isFixture ? "Generated Companion Setup opened. No native registration was changed." : "Companion Setup opened. Enable or disable the background service there, then return here to Check Connection.") { [service] in
            try await service.openSetup()
            return await service.installation()
        }
    }
    func disconnect() {
        run(success: "This app’s connection was closed. The background service registration and macOS permissions are unchanged.") { [service] in
            await service.disconnect()
            return await service.installation()
        }
    }
    func checkConnection() {
        run { [service] in
            let status = try await service.checkConnection()
            return .init(state: .ready, status: status)
        }
    }
    func openApprovalSettings() { Task { [service] in await service.openApprovalSettings() } }
    func waitForWorkForTesting() async { await work?.value }
    var stateTitle: String {
        switch snapshot.state {
        case .managedByCompanion: "Managed in Companion Setup"
        case .notInstalled: "Not Installed"
        case .disabled: "Disabled"
        case .needsApproval: "Needs Approval"
        case .enabled: "Enabled — Connection Unchecked"
        case .ready: "Ready — Metadata Connection"
        case .versionMismatch: "Version Mismatch"
        case .unavailable: "Unavailable"
        }
    }
    private func run(success: String? = nil, _ action: @escaping @Sendable () async throws -> CompanionInstallationSnapshot) {
        guard isBusy == false else { return }
        isBusy = true; message = nil
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isBusy = false; work = nil }
            do { snapshot = try await action(); message = snapshot.error.map(Self.message) ?? success }
            catch {
                snapshot = await service.installation()
                let failure = error as? CompanionSetupFailure
                message = Self.message(failure?.reason ?? (error as? CompanionError) ?? .unavailable)
                if let diagnostic = failure?.diagnostic {
                    message = (message ?? "") + " macOS diagnostic: \(diagnostic.domain.rawValue) / \(diagnostic.code)."
                }
            }
        }
    }
    static func message(_ error: CompanionError) -> String {
        switch error {
        case .invalidSignature: "This app and its bundled companion need matching Apple signatures. Use a correctly signed Commandly build."
        case .missingProvisioningProfile: "The app-group entitlement needs an authorized provisioning profile in this build before the connection can be checked."
        case .versionMismatch, .unsupportedVersion: "The app and companion versions do not match. Install the matching build, then refresh registration in Companion Setup."
        case .registrationFailed, .unregistrationFailed: "Open Companion Setup to manage registration and review the macOS status there."
        case .wrongUserSession: "The companion did not belong to this user’s login session. The connection was rejected."
        case .timedOut: "The companion did not reply in time. Open Companion Setup to review registration and Login Items approval before checking again."
        case .canceled: "The connection check was canceled."
        case .disconnected: "The companion connection ended. Enable or review the background service in Companion Setup, then check again."
        default: "System Integration is unavailable. Open Companion Setup or install a matching, correctly signed Commandly build."
        }
    }
}
