import AppKit
import Foundation
import Infrastructure

@MainActor final class NativeSystemSettingsWorkspace: SystemSettingsWorkspaceOpening {
    /// Keep the verified system-volume recipient even if another app installation is running.
    static func verifiedApplicationConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        return configuration
    }

    func openPane(_ url: URL, applicationURL: URL) async throws {
        try Task.checkCancellation()
        let configuration = Self.verifiedApplicationConfiguration()
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
    }

    func openApplication(_ applicationURL: URL) async throws {
        try Task.checkCancellation()
        let configuration = Self.verifiedApplicationConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }
}

/// Pins URL dispatch to the verified built-in app. URL completion means the OS accepted a request;
/// no Accessibility read, private API or Apple event is used to inspect the destination window.
@MainActor final class NativeSystemSettingsOpener: SystemSettingsOpening {
    private let resolver: any SystemSettingsResolving
    private let workspace: any SystemSettingsWorkspaceOpening

    init(resolver: any SystemSettingsResolving, workspace: any SystemSettingsWorkspaceOpening) {
        self.resolver = resolver
        self.workspace = workspace
    }

    func open(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationResult {
        try Task.checkCancellation()
        let plan = try await resolver.resolve(pane)
        try Task.checkCancellation()
        guard plan.applicationURL.isFileURL, plan.applicationURL.host == nil || plan.applicationURL.host == "localhost",
              plan.applicationURL.lastPathComponent == "System Settings.app" else {
            throw SystemSettingsNavigationError.unavailable
        }
        if let pane, let url = plan.paneURL, url == SystemSettingsPaneRoute.forPane(pane).url {
            do {
                try await workspace.openPane(url, applicationURL: plan.applicationURL)
                try Task.checkCancellation()
                return .requestedPane(pane)
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Only one fallback; a failed or cancelled launch must not produce a retry loop.
                try Task.checkCancellation()
            }
        }
        do {
            try await workspace.openApplication(plan.applicationURL)
            try Task.checkCancellation()
            return .openedApplication(fallbackFor: pane)
        } catch is CancellationError { throw CancellationError() }
        catch { throw SystemSettingsNavigationError.navigationFailed }
    }
}

@MainActor struct SystemSettingsApplicationServices {
    let opener: any SystemSettingsOpening
    static var live: Self {
        .init(opener: NativeSystemSettingsOpener(resolver: NativeSystemSettingsResolver(), workspace: NativeSystemSettingsWorkspace()))
    }
    static var inMemory: Self { .init(opener: InMemorySystemSettingsOpener()) }
}

/// Deliberately fails rather than simulating a successful native navigation in a fixture.
private actor InMemorySystemSettingsOpener: SystemSettingsOpening {
    func open(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationResult {
        throw SystemSettingsNavigationError.unavailable
    }
}
