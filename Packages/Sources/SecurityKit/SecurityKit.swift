import Foundation

/// Key used to look up a secret in secure storage.
public struct SecureStoreKey: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a secure store key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Whether the key contains a stable, nonempty storage identifier.
    public var isValid: Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

/// Sanitized failures produced by secure-storage implementations.
///
/// These cases deliberately omit storage keys, secret values, Keychain status codes, and other
/// operation-specific payloads so they are safe to surface or interpolate into diagnostics.
public enum SecureStoreError: Error, Sendable, Equatable {
    /// The supplied logical storage key was empty or otherwise invalid.
    case invalidKey
    /// The secure store was initialized with invalid configuration.
    case invalidConfiguration
    /// The process is not permitted to access the requested secure store.
    case accessDenied
    /// Secure storage could not perform an interaction in the current device state.
    case interactionNotAllowed
    /// The secure-storage service is currently unavailable.
    case unavailable
    /// Secure storage returned data in an unexpected format.
    case invalidData
    /// The operation failed for a reason that is intentionally not exposed.
    case operationFailed
}

extension SecureStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The secure storage key is invalid."
        case .invalidConfiguration:
            return "Secure storage is not configured correctly."
        case .accessDenied:
            return "Secure storage access was denied."
        case .interactionNotAllowed:
            return "Secure storage is locked or unavailable for interaction."
        case .unavailable:
            return "Secure storage is unavailable."
        case .invalidData:
            return "Secure storage returned invalid data."
        case .operationFailed:
            return "The secure storage operation failed."
        }
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

/// Actor-confined secure storage for deterministic tests and previews.
///
/// Values remain in memory only and are discarded with the store. Production code should inject a
/// platform secure-storage adapter instead.
public actor InMemorySecureStore: SecureStoring {
    private var values: [SecureStoreKey: Data]

    /// Creates an in-memory store with optional predetermined values.
    public init(values: [SecureStoreKey: Data] = [:]) {
        self.values = values
    }

    public func read(_ key: SecureStoreKey) async throws -> Data? {
        try Task.checkCancellation()
        try validate(key)
        return values[key]
    }

    public func write(_ key: SecureStoreKey, value: Data) async throws {
        try Task.checkCancellation()
        try validate(key)
        values[key] = value
    }

    public func delete(_ key: SecureStoreKey) async throws {
        try Task.checkCancellation()
        try validate(key)
        values[key] = nil
    }

    private func validate(_ key: SecureStoreKey) throws {
        guard key.isValid else {
            throw SecureStoreError.invalidKey
        }
    }
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
public struct SensitiveValue<Value: Sendable>: Sendable, CustomReflectable {
    private let value: Value

    /// Creates a sensitive value wrapper.
    public init(_ value: Value) {
        self.value = value
    }

    /// Reveals the underlying value intentionally.
    public func reveal() -> Value {
        value
    }

    /// Prevents reflection-based diagnostics from exposing the wrapped value.
    public var customMirror: Mirror {
        Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
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
