import Foundation

/// Provides UUID values for testable identity generation.
public protocol UUIDProviding: Sendable {
    /// Returns a UUID.
    func uuid() -> UUID
}

/// System-backed UUID provider.
public struct SystemUUIDProvider: UUIDProviding {
    /// Creates a system UUID provider.
    public init() {}

    public func uuid() -> UUID {
        UUID()
    }
}

/// Deterministic UUID provider for tests.
public struct FixedUUIDProvider: UUIDProviding {
    private let fixedUUID: UUID

    /// Creates a provider that always returns the given UUID.
    public init(uuid: UUID) {
        self.fixedUUID = uuid
    }

    public func uuid() -> UUID {
        fixedUUID
    }
}
