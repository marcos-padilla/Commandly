import Foundation

/// Menu reads and invocation are explicit, separate operations. No caller process or AX path is accepted.
public enum CompanionAppMenuRequest: Codable, Equatable, Sendable {
    case setEnabled(Bool)
    case snapshot
    case invoke(CompanionTargetHandle)
    case release
}
/// Finite recoverable failures, never native error text or private menu contents.
public enum CompanionAppMenuError: String, Error, Codable, Sendable {
    case disabled, disconnected, permissionDenied, locked, noApplication, stale, expired, busy
    case unsupported, tooLarge, timedOut, canceled, unavailable, invalidData, persistence
}
/// Persistable identity contains component hashes and indices, never menu titles or snapshots.
public struct CompanionMenuIdentity: Codable, Hashable, Sendable {
    public struct Component: Codable, Hashable, Sendable {
        public let index: Int
        public let digest: String
        public init(index: Int, digest: String) { self.index = index; self.digest = digest }
    }
    public let bundleIdentifier: String
    public let path: [Component]
    public init(bundleIdentifier: String, path: [Component]) { self.bundleIdentifier = bundleIdentifier; self.path = path }
    public var isValid: Bool {
        !bundleIdentifier.isEmpty && bundleIdentifier.utf8.count <= 255 && !path.isEmpty && path.count <= 12
            && path.allSatisfy { (0..<500).contains($0.index) && $0.digest.utf8.count == 64 && $0.digest.allSatisfy { "0123456789abcdef".contains($0) } }
    }
}
/// Transient current-app menu label and opaque authority. Never persisted or used as invocation input.
public struct CompanionAppMenuItem: Codable, Equatable, Identifiable, Sendable {
    public var id: CompanionTargetHandle { handle }
    public let handle: CompanionTargetHandle
    public let title: String
    public let ancestors: [String]
    public let enabled: Bool
    public let identity: CompanionMenuIdentity
    public init(handle: CompanionTargetHandle, title: String, ancestors: [String], enabled: Bool, identity: CompanionMenuIdentity) {
        self.handle = handle; self.title = title; self.ancestors = ancestors; self.enabled = enabled; self.identity = identity
    }
}
/// At most 500 items from one helper-owned external-app context, valid for at most 30 seconds.
public struct CompanionAppMenuSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let bundleIdentifier: String
    public let items: [CompanionAppMenuItem]
    public init(id: UUID = UUID(), bundleIdentifier: String, items: [CompanionAppMenuItem]) {
        self.id = id; self.bundleIdentifier = bundleIdentifier; self.items = items
    }
}
/// AX success means accepted, not a verified semantic result. A timed-out press must never be retried automatically.
public enum CompanionMenuInvocationOutcome: String, Codable, Sendable { case accepted, outcomeUnknown }
/// Closed response schema for the separately reviewed authenticated action router.
public enum CompanionAppMenuReply: Codable, Equatable, Sendable {
    case enabled(Bool), snapshot(CompanionAppMenuSnapshot), invoked(CompanionMenuInvocationOutcome), released
    case failure(CompanionAppMenuError)
}
/// The sandboxed client uses only an authenticated bound transport; no AX access belongs in its implementation.
public protocol CompanionAppMenuCalling: Sendable {
    func requestAppMenu(_ request: CompanionAppMenuRequest) async throws -> CompanionAppMenuReply
}

/// Inert app composition for fixtures or unavailable helper builds.
public struct UnavailableCompanionAppMenuCaller: CompanionAppMenuCalling {
    public init() {}
    public func requestAppMenu(_ request: CompanionAppMenuRequest) async throws -> CompanionAppMenuReply { .failure(.disabled) }
}
/// Root review opens the closed action route; each authenticated session still starts disabled.
public enum CompanionAppMenuReleaseGate { public static let reviewed = true }
