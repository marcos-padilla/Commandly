import Foundation

/// Which kinds of idle sleep a keep-awake session holds off.
public struct SleepPreventionRequest: Sendable, Equatable {
    /// Holds off idle system sleep so background work keeps running.
    public let preventsSystemSleep: Bool
    /// Holds off idle display sleep so the screen stays lit.
    public let preventsDisplaySleep: Bool

    /// No assertion is held; the Mac follows its normal energy rules.
    public static let none = SleepPreventionRequest(
        preventsSystemSleep: false,
        preventsDisplaySleep: false
    )

    public init(preventsSystemSleep: Bool, preventsDisplaySleep: Bool) {
        self.preventsSystemSleep = preventsSystemSleep
        self.preventsDisplaySleep = preventsDisplaySleep
    }
}

/// Holds and releases the power assertions behind a keep-awake session.
///
/// Implementations own process-wide assertions, so a request replaces the previous one rather
/// than stacking on top of it. Releasing must be idempotent: the app releases on teardown even
/// when no assertion is held.
public protocol SleepPreventing: AnyObject, Sendable {
    /// Makes the held assertions match `request`, taking and dropping them as needed.
    func apply(_ request: SleepPreventionRequest)
    /// Drops every assertion this service holds.
    func release()
}

/// A reading of the Mac's current power source.
public struct PowerSourceSnapshot: Sendable, Equatable {
    /// Whether the Mac is running from its internal battery.
    public let isOnBattery: Bool
    /// Remaining charge as a whole percentage, `0...100`.
    public let percentRemaining: Int

    public init(isOnBattery: Bool, percentRemaining: Int) {
        self.isOnBattery = isOnBattery
        self.percentRemaining = percentRemaining
    }
}

/// Reads the Mac's power source without subscribing to it.
///
/// `nil` means the Mac reported no internal battery (a desktop) or the reading failed; callers
/// must treat that as "unknown" rather than as "on battery".
public protocol PowerSourceReading: Sendable {
    /// Returns the current power source, or `nil` when none can be read.
    func snapshot() -> PowerSourceSnapshot?
}

/// Reports whether a display other than the built-in one is attached.
public protocol ExternalDisplayReading: Sendable {
    /// `true` when at least one attached display is not built in, `nil` when the list is
    /// unavailable and the previous answer should stand.
    func hasExternalDisplay() -> Bool?
}

/// Moves the pointer by a single point and back, so macOS sees user activity.
///
/// This posts synthetic mouse events and therefore requires Accessibility permission; without it
/// the move is refused by the system and `nudge()` reports failure.
public protocol PointerNudging: Sendable {
    /// Performs one nudge. Returns `false` when the event could not be posted.
    @discardableResult
    func nudge() -> Bool
}

/// Reports whether the login session screen is currently locked.
public protocol ScreenLockReading: Sendable {
    /// `true` while the screen is locked by the login session.
    func isScreenLocked() -> Bool
}
