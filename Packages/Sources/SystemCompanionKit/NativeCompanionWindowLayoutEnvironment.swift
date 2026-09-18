import AppKit
import Foundation
import Infrastructure

/// Observer lifecycle belongs to the helper's authenticated connection, never the launcher.
@MainActor public protocol CompanionWindowLayoutObserving: AnyObject, Sendable {
    func start()
    func stop()
}

/// Observes activation identities only while an explicitly enabled, connected lease is alive.
/// The main PID is kernel-derived from the authenticated peer, never an IPC argument.
@MainActor public final class NativeCompanionWindowLayoutEnvironment: CompanionWindowLayoutEnvironment, CompanionWindowLayoutObserving {
    private struct Candidate: Equatable, Sendable {
        let pid: Int32
        let bundle: String
        let executablePath: String
    }
    private let metadata: any CompanionProcessMetadataReading
    private var identityTask: Task<Void, Never>?
    private let lease: CompanionWindowLayoutLease
    private let mainProcessIdentifier: Int32
    private let helperProcessIdentifier: Int32
    private var workspaceTokens: [NSObjectProtocol] = []
    private var displayToken: NSObjectProtocol?
    public init(lease: CompanionWindowLayoutLease, authenticatedMainProcessIdentifier: Int32,
                helperProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
                metadata: any CompanionProcessMetadataReading = NativeCompanionProcessMetadataReader()) {
        self.metadata = metadata
        self.lease = lease; self.mainProcessIdentifier = authenticatedMainProcessIdentifier
        self.helperProcessIdentifier = helperProcessIdentifier
    }
    public func start() {
        stop()
        let notifications = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(notifications.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let candidate = app.flatMap(Self.candidate)
            MainActor.assumeIsolated {
                guard let self else { return }
                if pid == self.mainProcessIdentifier || pid == self.helperProcessIdentifier { return }
                self.resolve(candidate)
            }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceTokens.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
        displayToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lease.displayChanged() }
        }
        observe(NSWorkspace.shared.frontmostApplication)
    }
    public func stop() {
        identityTask?.cancel(); identityTask = nil
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        if let displayToken { NotificationCenter.default.removeObserver(displayToken) }
        displayToken = nil
    }
    /// Host lock/revocation hooks synchronously revoke authority. There is no automatic unlock retry.
    public func lock() { lease.setLocked(true); stop() }
    public func validate(_ context: CompanionWindowLayoutContext) async throws -> [CompanionLayoutDisplay] {
        try lease.validate(context)
        guard let app = NSRunningApplication(processIdentifier: context.application.processIdentifier),
              let candidate = Self.candidate(app), try await resolveIdentity(candidate) == context.application else {
            throw CompanionWindowLayoutError.staleTarget
        }
        try lease.validate(context)
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { throw CompanionWindowLayoutError.staleTarget }
        if isOwn(frontmost) == false, Self.candidate(frontmost) != candidate { throw CompanionWindowLayoutError.staleTarget }
        let screens = NSScreen.screens
        guard let main = screens.first(where: { $0.frame.origin == .zero }), screens.count <= 32 else { throw CompanionWindowLayoutError.displayChanged }
        let top = main.frame.maxY
        return try screens.map { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                throw CompanionWindowLayoutError.displayChanged
            }
            func axFrame(_ rect: CGRect) -> CGRect { .init(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height) }
            return CompanionLayoutDisplay(identifier: number.uint32Value, frame: axFrame(screen.frame), visibleFrame: axFrame(screen.visibleFrame))
        }.sorted { $0.identifier < $1.identifier }
    }
    private func observe(_ app: NSRunningApplication?) {
        if let app, isOwn(app) { return }
        resolve(app.flatMap(Self.candidate))
    }
    private func isOwn(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == mainProcessIdentifier || app.processIdentifier == helperProcessIdentifier
    }
    private func resolve(_ candidate: Candidate?) {
        identityTask?.cancel()
        guard let epoch = lease.beginExternalActivation(), let candidate else { return }
        identityTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await resolveIdentity(candidate)
                try Task.checkCancellation()
                lease.finishExternalActivation(identity, epoch: epoch)
            } catch {
                // The begin step already cleared the target. A failed identity remains unavailable.
                return
            }
        }
    }
    private func resolveIdentity(_ candidate: Candidate) async throws -> CompanionLayoutApplicationIdentity {
        let before = try await metadata.read(pid: candidate.pid)
        guard let current = NSRunningApplication(processIdentifier: candidate.pid), Self.candidate(current) == candidate else {
            throw CompanionWindowLayoutError.staleTarget
        }
        let after = try await metadata.read(pid: candidate.pid)
        guard before == after, after.birth.isValid, after.pid == candidate.pid,
              after.executablePath == candidate.executablePath,
              let final = NSRunningApplication(processIdentifier: candidate.pid), Self.candidate(final) == candidate else {
            throw CompanionWindowLayoutError.staleTarget
        }
        return .init(processIdentifier: candidate.pid, birth: after.birth, executablePath: after.executablePath, bundleIdentifier: candidate.bundle)
    }
    nonisolated private static func candidate(_ app: NSRunningApplication) -> Candidate? {
        guard app.isTerminated == false, app.activationPolicy == .regular,
              let bundle = app.bundleIdentifier, let executable = app.executableURL?.path,
              bundle.isEmpty == false, bundle.utf8.count <= 255, executable.utf8.count <= 4096 else { return nil }
        return Candidate(pid: app.processIdentifier, bundle: bundle, executablePath: executable)
    }
}
