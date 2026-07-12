import Foundation

/// A clock abstraction for measuring elapsed time without depending on UI frameworks.
public protocol Clock: Sendable {
    /// Returns a monotonic timestamp suitable for measuring intervals.
    func monotonicTime() -> ContinuousClock.Instant
}

/// Continuous clock backed by the Swift standard library.
public struct ContinuousSystemClock: Clock {
    private let continuousClock: ContinuousClock

    /// Creates a continuous system clock.
    public init(continuousClock: ContinuousClock = ContinuousClock()) {
        self.continuousClock = continuousClock
    }

    public func monotonicTime() -> ContinuousClock.Instant {
        continuousClock.now
    }
}
