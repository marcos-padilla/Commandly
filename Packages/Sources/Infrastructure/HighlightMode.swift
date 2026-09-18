import Foundation

/// Color used for click and keyboard feedback while Highlight Mode is active.
public enum HighlightModeAccent: String, CaseIterable, Codable, Sendable {
    case blue
    case green
    case orange
    case pink
}

/// Diameter of the clear cursor area shown through the dimming overlay.
public enum HighlightModeSpotlightSize: String, CaseIterable, Codable, Sendable {
    case compact
    case medium
    case large
}

/// How long transient click and keyboard feedback remains visible.
public enum HighlightModeDisplayDuration: String, CaseIterable, Codable, Sendable {
    case short
    case standard
    case long
}

/// Non-secret visual behavior supplied by Commandly's Applications settings pane.
public struct HighlightModeConfiguration: Equatable, Sendable {
    public let showsMouseClicks: Bool
    public let showsKeyboardShortcuts: Bool
    public let showsTypedText: Bool
    public let showsCursorSpotlight: Bool
    public let spotlightSize: HighlightModeSpotlightSize
    public let accent: HighlightModeAccent
    public let displayDuration: HighlightModeDisplayDuration

    public init(
        showsMouseClicks: Bool = true,
        showsKeyboardShortcuts: Bool = true,
        showsTypedText: Bool = true,
        showsCursorSpotlight: Bool = true,
        spotlightSize: HighlightModeSpotlightSize = .medium,
        accent: HighlightModeAccent = .blue,
        displayDuration: HighlightModeDisplayDuration = .standard
    ) {
        self.showsMouseClicks = showsMouseClicks
        self.showsKeyboardShortcuts = showsKeyboardShortcuts
        self.showsTypedText = showsTypedText
        self.showsCursorSpotlight = showsCursorSpotlight
        self.spotlightSize = spotlightSize
        self.accent = accent
        self.displayDuration = displayDuration
    }

    public static let `default` = HighlightModeConfiguration()
}

/// Current app-lifetime state of Highlight Mode.
public struct HighlightModeState: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

/// Typed failures produced while enabling the global visualization surface.
public enum HighlightModeError: Error, Equatable, Sendable {
    case accessibilityDenied
    case eventMonitoringUnavailable
}

/// Controls a privacy-sensitive, app-lifetime click and keyboard visualization session.
///
/// Implementations must keep captured input ephemeral. They must never persist, log, upload, or
/// place typed text or shortcut events on the pasteboard.
@MainActor
public protocol HighlightModeControlling: AnyObject, Sendable {
    /// Current activation state.
    var state: HighlightModeState { get }

    /// Enables or disables visualization after explicit user intent.
    func setEnabled(
        _ isEnabled: Bool,
        configuration: HighlightModeConfiguration
    ) async throws -> HighlightModeState

    /// Applies non-secret appearance settings to an active session.
    func updateConfiguration(_ configuration: HighlightModeConfiguration)

    /// Stops monitoring and removes every overlay without prompting.
    func stop()
}

/// Deterministic implementation for app and composition tests. It never monitors real input.
@MainActor
public final class InMemoryHighlightModeService: HighlightModeControlling {
    public private(set) var state: HighlightModeState
    public private(set) var configuration: HighlightModeConfiguration

    public init(
        state: HighlightModeState = HighlightModeState(isEnabled: false),
        configuration: HighlightModeConfiguration = .default
    ) {
        self.state = state
        self.configuration = configuration
    }

    public func setEnabled(
        _ isEnabled: Bool,
        configuration: HighlightModeConfiguration
    ) async throws -> HighlightModeState {
        self.configuration = configuration
        state = HighlightModeState(isEnabled: isEnabled)
        return state
    }

    public func updateConfiguration(_ configuration: HighlightModeConfiguration) {
        self.configuration = configuration
    }

    public func stop() {
        state = HighlightModeState(isEnabled: false)
    }
}
