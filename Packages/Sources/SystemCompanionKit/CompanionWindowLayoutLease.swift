import Foundation
import Infrastructure
import os

/// Helper-owned identity. It is never accepted from the caller or sent in a reply.
public struct CompanionLayoutApplicationIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let birth: CompanionProcessBirth
    public let executablePath: String
    public let bundleIdentifier: String
    public init(processIdentifier: Int32, birth: CompanionProcessBirth, executablePath: String, bundleIdentifier: String) {
        self.processIdentifier = processIdentifier; self.birth = birth; self.executablePath = executablePath; self.bundleIdentifier = bundleIdentifier
    }
}

/// Immutable authority snapshot carried only within the helper.
public struct CompanionWindowLayoutContext: Equatable, Sendable {
    public let session: UUID
    public let epoch: UUID
    public let application: CompanionLayoutApplicationIdentity
}

/// Synchronous revocation boundary, readable by the AX worker before every native write.
/// OSAllocatedUnfairLock owns only Sendable values; no native AX objects cross executors.
public final class CompanionWindowLayoutLease: Sendable {
    private struct State: Sendable {
        var session: UUID?
        var enabled = false
        var locked = false
        var epoch = UUID()
        var application: CompanionLayoutApplicationIdentity?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    public init() {}
    public var capabilityState: CompanionCapabilityState {
        state.withLock { $0.session != nil && $0.enabled && $0.locked == false ? .available : .disabled }
    }
    public var isConnected: Bool { state.withLock { $0.session != nil } }
    public func connect(session: UUID) {
        state.withLock { $0 = State(session: session) }
    }
    public func setEnabled(_ enabled: Bool, session: UUID) throws {
        try state.withLock {
            guard $0.session == session else { throw CompanionWindowLayoutError.disconnected }
            guard $0.locked == false || enabled == false else { throw CompanionWindowLayoutError.locked }
            $0.enabled = enabled; $0.application = nil; $0.epoch = UUID()
        }
    }
    public func beginExternalActivation() -> UUID? {
        state.withLock {
            guard $0.session != nil, $0.enabled, $0.locked == false else { return nil }
            $0.application = nil; $0.epoch = UUID(); return $0.epoch
        }
    }
    public func finishExternalActivation(_ identity: CompanionLayoutApplicationIdentity, epoch: UUID) {
        state.withLock {
            guard $0.session != nil, $0.enabled, $0.locked == false, $0.epoch == epoch else { return }
            $0.application = identity
        }
    }
    public func activateExternal(_ identity: CompanionLayoutApplicationIdentity?) {
        state.withLock {
            guard $0.session != nil, $0.enabled, $0.locked == false else { return }
            // Every external activation changes the epoch, even reactivation of the same process.
            $0.application = identity; $0.epoch = UUID()
        }
    }
    public func releaseTargets(session: UUID) throws {
        try state.withLock {
            guard $0.session == session else { throw CompanionWindowLayoutError.disconnected }
            $0.epoch = UUID()
        }
    }
    public func displayChanged() { state.withLock { $0.epoch = UUID() } }
    public func setLocked(_ locked: Bool) {
        state.withLock { $0.locked = locked; $0.application = nil; $0.epoch = UUID() }
    }
    public func disconnect() { state.withLock { $0 = State() } }
    public func snapshot(session: UUID) throws -> CompanionWindowLayoutContext {
        try state.withLock {
            guard $0.session == session else { throw CompanionWindowLayoutError.disconnected }
            guard $0.enabled else { throw CompanionWindowLayoutError.disabled }
            guard $0.locked == false else { throw CompanionWindowLayoutError.locked }
            guard let application = $0.application else { throw CompanionWindowLayoutError.noExternalApplication }
            return .init(session: session, epoch: $0.epoch, application: application)
        }
    }
    public func validate(_ context: CompanionWindowLayoutContext) throws {
        guard try snapshot(session: context.session) == context else { throw CompanionWindowLayoutError.staleTarget }
    }
}
