import Foundation
import Infrastructure
import os

/// Helper-local OS identity; it is neither Codable nor accepted from an IPC caller.
public struct CompanionMenuApplicationIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let birth: CompanionProcessBirth
    public let executablePath: String
    public let bundleIdentifier: String
    public init(processIdentifier: Int32, birth: CompanionProcessBirth, executablePath: String, bundleIdentifier: String) {
        self.processIdentifier = processIdentifier; self.birth = birth; self.executablePath = executablePath; self.bundleIdentifier = bundleIdentifier
    }
}
/// A captured authority epoch, retained only by the helper.
public struct CompanionMenuContext: Equatable, Sendable {
    public let session: UUID
    public let epoch: UUID
    public let application: CompanionMenuApplicationIdentity
}
/// Synchronous revocation reaches the worker before native calls, without sending AX values across actors.
public final class CompanionMenuLease: Sendable {
    private struct State: Sendable {
        var session: UUID?
        var enabled = false
        var locked = false
        var epoch = UUID()
        var application: CompanionMenuApplicationIdentity?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    public init() {}
    public var isConnected: Bool { state.withLock { $0.session != nil } }
    public var capabilityState: CompanionCapabilityState { state.withLock { $0.session != nil && $0.enabled && !$0.locked ? .available : .disabled } }
    public func connect(session: UUID) { state.withLock { $0 = State(session: session) } }
    public func setEnabled(_ enabled: Bool, session: UUID) throws {
        try state.withLock {
            guard $0.session == session else { throw CompanionAppMenuError.disconnected }
            guard !$0.locked || !enabled else { throw CompanionAppMenuError.locked }
            $0.enabled = enabled; $0.application = nil; $0.epoch = UUID()
        }
    }
    public func activateExternal(_ identity: CompanionMenuApplicationIdentity?) {
        state.withLock {
            guard $0.session != nil, $0.enabled, !$0.locked else { return }
            $0.application = identity; $0.epoch = UUID()
        }
    }
    public func beginExternalActivation() -> UUID? {
        state.withLock {
            guard $0.session != nil, $0.enabled, !$0.locked else { return nil }
            $0.application = nil; $0.epoch = UUID(); return $0.epoch
        }
    }
    public func finishExternalActivation(_ identity: CompanionMenuApplicationIdentity, epoch: UUID) {
        state.withLock {
            guard $0.session != nil, $0.enabled, !$0.locked, $0.epoch == epoch else { return }
            $0.application = identity
        }
    }
    public func release(session: UUID) throws {
        try state.withLock {
            guard $0.session == session else { throw CompanionAppMenuError.disconnected }
            $0.epoch = UUID()
        }
    }
    public func setLocked() { state.withLock { $0.locked = true; $0.application = nil; $0.epoch = UUID() } }
    public func disconnect() { state.withLock { $0 = State() } }
    public func snapshot(session: UUID) throws -> CompanionMenuContext {
        try state.withLock {
            guard $0.session == session else { throw CompanionAppMenuError.disconnected }
            guard $0.enabled else { throw CompanionAppMenuError.disabled }
            guard !$0.locked else { throw CompanionAppMenuError.locked }
            guard let app = $0.application else { throw CompanionAppMenuError.noApplication }
            return .init(session: session, epoch: $0.epoch, application: app)
        }
    }
    public func validate(_ context: CompanionMenuContext) throws {
        guard try snapshot(session: context.session) == context else { throw CompanionAppMenuError.stale }
    }
}
