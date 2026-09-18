import Foundation

/// Screen-relative top-left geometry. Values are untrusted until `isValid` is checked.
public struct CompanionNormalizedWindowRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    /// Allows floating-point thirds while rejecting nonfinite and offscreen geometry.
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x <= 1 && y <= 1 && width <= 1 && height <= 1
            && x + width <= 1.000_001 && y + height <= 1.000_001
    }
}

/// Only explicit capability control and an Apply transaction cross the authenticated bound channel.
/// Capturing takes place when Apply begins, not when the launcher appears. Handles expire after 3 seconds.
public enum CompanionWindowLayoutRequest: Codable, Equatable, Sendable {
    case setEnabled(Bool)
    case releaseTargets
    case captureFocused
    case apply(handle: CompanionTargetHandle, rect: CompanionNormalizedWindowRect)
}

/// Native writes can time out after the target has already changed; unknown never means unchanged.
public enum CompanionWindowMutationState: String, Codable, Sendable { case accepted, refused, unknown, notAttempted }
/// A write can be acknowledged yet constrained by the target app, or have an uncertain delivery outcome.
public enum CompanionWindowLayoutOutcome: String, Codable, Sendable { case applied, constrained, unverified, partial, failed, uncertain }
/// Content-free receipt. A missing readback is distinct from a measured mismatch.
public struct CompanionWindowLayoutReceipt: Codable, Equatable, Sendable {
    public let outcome: CompanionWindowLayoutOutcome
    public let resizeState: CompanionWindowMutationState
    public let positionState: CompanionWindowMutationState
    public let readbackMatches: Bool
    public let readbackAvailable: Bool
    public var resizeAccepted: Bool { resizeState == .accepted }
    public var positionAccepted: Bool { positionState == .accepted }
    /// Reject contradictory readback flags, illegal write ordering, and fabricated outcomes after decoding.
    public var isValid: Bool {
        if readbackMatches && readbackAvailable == false { return false }
        if resizeState != .accepted && positionState != .notAttempted { return false }
        if resizeState == .notAttempted { return false }
        return self == Self(resizeState: resizeState, positionState: positionState, readbackMatches: readbackMatches, readbackAvailable: readbackAvailable)
    }
    public init(resizeState: CompanionWindowMutationState, positionState: CompanionWindowMutationState,
                readbackMatches: Bool = false, readbackAvailable: Bool = false) {
        self.resizeState = resizeState; self.positionState = positionState
        self.readbackMatches = readbackMatches; self.readbackAvailable = readbackAvailable
        if resizeState == .unknown || positionState == .unknown { outcome = .uncertain }
        else if resizeState == .accepted && positionState == .accepted {
            outcome = readbackAvailable ? (readbackMatches ? .applied : .constrained) : .unverified
        } else if resizeState == .accepted || positionState == .accepted { outcome = .partial }
        else { outcome = .failed }
    }
    public init(resizeAccepted: Bool, positionAccepted: Bool, readbackMatches: Bool, readbackAvailable: Bool = true) {
        self.init(resizeState: resizeAccepted ? .accepted : .refused,
                  positionState: positionAccepted ? .accepted : (resizeAccepted ? .refused : .notAttempted),
                  readbackMatches: readbackMatches, readbackAvailable: readbackAvailable)
    }
}

/// Fixed, non-content-bearing failures. Native TCC prompting is deliberately absent.
public enum CompanionWindowLayoutError: String, Codable, Error, Sendable {
    case disabled, disconnected, locked, permissionDenied, noExternalApplication, noFocusedWindow
    case staleTarget, expiredTarget, invalidGeometry, unsupportedWindow, displayChanged, canceled, timedOut, unavailable
}

/// Typed reply with no arbitrary native error text.
public enum CompanionWindowLayoutReply: Codable, Equatable, Sendable {
    case enabled(Bool)
    case released
    case captured(CompanionTargetHandle)
    case applied(CompanionWindowLayoutReceipt)
    case failure(CompanionWindowLayoutError)
}

/// The app adapter invokes this only for an explicit Apply or capability setting.
public protocol CompanionWindowLayoutCalling: Sendable {
    func requestWindowLayout(_ request: CompanionWindowLayoutRequest) async throws -> CompanionWindowLayoutReply
}

/// Inert composition default until the reviewed bound capability is available.
public struct UnavailableCompanionWindowLayoutCaller: CompanionWindowLayoutCalling {
    public init() {}
    public func requestWindowLayout(_ request: CompanionWindowLayoutRequest) async throws -> CompanionWindowLayoutReply {
        .failure(.disabled)
    }
}

/// Compile-time review gate; it is not a user default or an IPC setting. Root review must explicitly open it.
public enum CompanionWindowLayoutReleaseGate {
    public static let reviewed = true
}
