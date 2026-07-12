import Foundation

/// Provides the current date for testable time-dependent logic.
public protocol DateProviding: Sendable {
    /// Returns the current date.
    func now() -> Date
}

/// System-backed date provider.
public struct SystemDateProvider: DateProviding {
    /// Creates a system date provider.
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Deterministic date provider for tests.
public struct FixedDateProvider: DateProviding {
    private let fixedDate: Date

    /// Creates a provider that always returns the given date.
    public init(date: Date) {
        self.fixedDate = date
    }

    public func now() -> Date {
        fixedDate
    }
}
