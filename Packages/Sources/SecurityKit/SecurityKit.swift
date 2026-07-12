import Foundation

/// Key used to look up a secret in secure storage.
public struct SecureStoreKey: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a secure store key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Contract for storing sensitive values outside of source control and UserDefaults.
public protocol SecureStoring: Sendable {
    /// Reads a sensitive value.
    func read(_ key: SecureStoreKey) async throws -> Data?
    /// Writes a sensitive value.
    func write(_ key: SecureStoreKey, value: Data) async throws
    /// Deletes a sensitive value.
    func delete(_ key: SecureStoreKey) async throws
}

/// Categories of macOS permissions Commandly may request.
public enum PermissionKind: String, Sendable, CaseIterable, Equatable {
    case accessibility
    case appleEvents
    case screenRecording
    case files
    case notifications
    case calendar
    case contacts
}

/// Current state of a permission.
public enum PermissionState: String, Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case restricted
}

/// Contract for checking permission state without prompting.
public protocol PermissionChecking: Sendable {
    /// Returns the current state for a permission kind.
    func state(for kind: PermissionKind) async -> PermissionState
}

/// Contract for requesting a permission. Must only be used after contextual user intent.
public protocol PermissionRequesting: Sendable {
    /// Requests a permission and returns the resulting state.
    func request(_ kind: PermissionKind) async -> PermissionState
}

/// Combined permission service for check + request flows.
public protocol PermissionServicing: PermissionChecking, PermissionRequesting {}

/// In-memory permission service for tests. Never prompts the system.
///
/// `@unchecked Sendable`: guarded by an internal lock for concurrent test use.
public final class InMemoryPermissionService: PermissionServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [PermissionKind: PermissionState]

    /// Creates a service with predetermined states.
    public init(states: [PermissionKind: PermissionState] = [:]) {
        self.states = states
    }

    public func state(for kind: PermissionKind) async -> PermissionState {
        lock.withLock { states[kind] ?? .notDetermined }
    }

    public func request(_ kind: PermissionKind) async -> PermissionState {
        lock.withLock {
            let next = states[kind] == .denied ? PermissionState.denied : .authorized
            states[kind] = next
            return next
        }
    }

    /// Overwrites the stored state for a permission kind (tests only).
    public func setState(_ state: PermissionState, for kind: PermissionKind) {
        lock.withLock { states[kind] = state }
    }
}

/// In-memory permission checker for tests. Never prompts the system.
public struct InMemoryPermissionChecker: PermissionChecking, Sendable {
    private let states: [PermissionKind: PermissionState]

    /// Creates a checker with predetermined states.
    public init(states: [PermissionKind: PermissionState] = [:]) {
        self.states = states
    }

    public func state(for kind: PermissionKind) async -> PermissionState {
        states[kind] ?? .notDetermined
    }
}

/// Sensitive value wrapper that avoids accidental string interpolation into logs.
public struct SensitiveValue<Value: Sendable>: Sendable {
    private let value: Value

    /// Creates a sensitive value wrapper.
    public init(_ value: Value) {
        self.value = value
    }

    /// Reveals the underlying value intentionally.
    public func reveal() -> Value {
        value
    }
}

extension SensitiveValue: CustomStringConvertible {
    public var description: String {
        "<redacted>"
    }
}

extension SensitiveValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<redacted>"
    }
}
