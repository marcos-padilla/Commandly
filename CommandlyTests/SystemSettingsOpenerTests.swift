import AppKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct SystemSettingsOpenerTests {
    @Test func nativeConfigurationKeepsVerifiedApplicationWithoutForcingNewInstance() {
        let configuration = NativeSystemSettingsWorkspace.verifiedApplicationConfiguration()
        #expect(configuration.activates)
        #expect(!configuration.allowsRunningApplicationSubstitution)
        #expect(!configuration.createsNewApplicationInstance)
    }

    @Test func dispatchesExactPaneToResolvedApplication() async throws {
        let workspace = SettingsTestWorkspace()
        let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(), workspace: workspace)
        #expect(try await service.open(.displays) == .requestedPane(.displays))
        #expect(workspace.panes.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.Displays-Settings.extension"])
        #expect(workspace.applications.isEmpty)
        #expect(workspace.recipients.allSatisfy { $0 == SettingsTestResolver.applicationURL })
    }
    @Test func missingOrMalformedRouteFallsBackToApplication() async throws {
        for mode in [SettingsTestResolver.Mode.missingPane, .malformedPane] {
            let workspace = SettingsTestWorkspace()
            let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(mode: mode), workspace: workspace)
            #expect(try await service.open(.displays) == .openedApplication(fallbackFor: .displays))
            #expect(workspace.panes.isEmpty)
            #expect(workspace.applications == [SettingsTestResolver.applicationURL])
        }
    }
    @Test func failedPaneGetsOneFallbackAndTotalFailureIsRecoverable() async throws {
        let workspace = SettingsTestWorkspace(); workspace.failPane = true
        let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(), workspace: workspace)
        #expect(try await service.open(.displays) == .openedApplication(fallbackFor: .displays))
        #expect(workspace.panes.count == 1 && workspace.applications.count == 1)
        workspace.failApplication = true
        await #expect(throws: SystemSettingsNavigationError.navigationFailed) { _ = try await service.open(.displays) }
        #expect(workspace.panes.count == 2 && workspace.applications.count == 2)
    }
    @Test func invalidRecipientAndResolverFailureNeverDispatch() async {
        for mode in [SettingsTestResolver.Mode.invalidApplication, .unavailable] {
            let workspace = SettingsTestWorkspace()
            let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(mode: mode), workspace: workspace)
            await #expect(throws: SystemSettingsNavigationError.unavailable) { _ = try await service.open(.displays) }
            #expect(workspace.panes.isEmpty && workspace.applications.isEmpty)
        }
    }
    @Test func cancellationBeforeDispatchAndAfterDispatchNeverTriggersFallback() async throws {
        let workspace = SettingsTestWorkspace()
        let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(), workspace: workspace)
        let queued = Task { try await service.open(.displays) }
        queued.cancel()
        await #expect(throws: CancellationError.self) { _ = try await queued.value }
        #expect(workspace.panes.isEmpty && workspace.applications.isEmpty)
        workspace.holdPane = true
        let active = Task { try await service.open(.displays) }
        await workspace.waitForPane()
        active.cancel(); workspace.releasePane()
        await #expect(throws: CancellationError.self) { _ = try await active.value }
        #expect(workspace.panes.count == 1 && workspace.applications.isEmpty)
    }
    @Test func applicationOnlyRequestDoesNotDispatchPane() async throws {
        let workspace = SettingsTestWorkspace()
        let service = NativeSystemSettingsOpener(resolver: SettingsTestResolver(), workspace: workspace)
        #expect(try await service.open(nil) == .openedApplication(fallbackFor: nil))
        #expect(workspace.panes.isEmpty && workspace.applications.count == 1)
    }
}

private actor SettingsTestResolver: SystemSettingsResolving {
    enum Mode: Sendable { case normal, missingPane, malformedPane, invalidApplication, unavailable }
    static let applicationURL = URL(fileURLWithPath: "/generated/System Settings.app", isDirectory: true)
    let mode: Mode
    init(mode: Mode = .normal) { self.mode = mode }
    func resolve(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationPlan {
        if mode == .unavailable { throw SystemSettingsNavigationError.unavailable }
        let app = mode == .invalidApplication ? URL(string: "https://example.com/System%20Settings.app") : Self.applicationURL
        guard let app else { throw SystemSettingsNavigationError.unavailable }
        let route: URL?
        if mode == .missingPane { route = nil }
        else if mode == .malformedPane { route = URL(string: "https://example.com") }
        else { route = pane.flatMap { SystemSettingsPaneRoute.forPane($0).url } }
        return .init(applicationURL: app, paneURL: route)
    }
}

@MainActor private final class SettingsTestWorkspace: SystemSettingsWorkspaceOpening {
    var panes: [URL] = []; var applications: [URL] = []; var recipients: [URL] = []
    var failPane = false; var failApplication = false; var holdPane = false
    private var paneWaiter: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    func openPane(_ url: URL, applicationURL: URL) async throws {
        panes.append(url); recipients.append(applicationURL)
        if holdPane {
            await withCheckedContinuation { continuation in
                paneWaiter = continuation
                startedWaiter?.resume(); startedWaiter = nil
            }
        }
        if failPane { throw SystemSettingsNavigationError.navigationFailed }
    }
    func openApplication(_ applicationURL: URL) async throws {
        applications.append(applicationURL)
        if failApplication { throw SystemSettingsNavigationError.navigationFailed }
    }
    func waitForPane() async {
        if paneWaiter != nil { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func releasePane() { paneWaiter?.resume(); paneWaiter = nil }
}
