import Foundation

/// Continuous deadlines are injectable; tests advance controlled clocks without arbitrary delays.
public protocol CompanionDeadlineClock: Sendable {
    func now() -> ContinuousClock.Instant
    func sleep(until deadline: ContinuousClock.Instant) async throws
}
/// Native deadlines use the standard continuous clock, including time spent asleep.
public struct NativeCompanionDeadlineClock: CompanionDeadlineClock {
    public init() {}
    public func now() -> ContinuousClock.Instant { ContinuousClock().now }
    public func sleep(until deadline: ContinuousClock.Instant) async throws { try await ContinuousClock().sleep(until: deadline) }
}
