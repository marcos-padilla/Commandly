import AppKit
import SwiftUI

/// Spacing scale for Commandly UI.
public enum Spacing: CGFloat, Sendable {
    case xxxs = 2
    case xxs = 4
    case xs = 8
    case sm = 12
    case md = 16
    case lg = 24
    case xl = 32
    case xxl = 48
}

/// Corner radius scale.
public enum CornerRadius: CGFloat, Sendable {
    case none = 0
    case sm = 6
    case md = 10
    case lg = 16
    case xl = 22
}

/// Typography roles. Concrete fonts are resolved by the app.
public enum TypographyRole: String, Sendable, CaseIterable {
    case display
    case title
    case body
    case callout
    case caption
}

/// Motion duration tokens in seconds.
public enum MotionDuration: Double, Sendable {
    case instant = 0.0
    case fast = 0.12
    case normal = 0.2
    case slow = 0.35
    /// Longer choreographed moments such as onboarding celebrations.
    case celebration = 1.25
}

/// Shared layout constants for future surfaces.
public enum LayoutConstants {
    /// Default minimum launcher width.
    public static let launcherMinWidth: CGFloat = 640
    /// Default minimum launcher height.
    public static let launcherMinHeight: CGFloat = 420
    /// Ideal launcher panel width.
    public static let launcherIdealWidth: CGFloat = 720
    /// Ideal launcher panel height.
    public static let launcherIdealHeight: CGFloat = 480
    /// Default settings window width.
    public static let settingsMinWidth: CGFloat = 720
    /// Default settings window height.
    public static let settingsMinHeight: CGFloat = 460
    /// Settings sidebar width.
    public static let settingsSidebarWidth: CGFloat = 168
    /// Minimum onboarding window width.
    public static let onboardingMinWidth: CGFloat = 960
    /// Minimum onboarding window height.
    public static let onboardingMinHeight: CGFloat = 640
    /// Ideal onboarding window width.
    public static let onboardingIdealWidth: CGFloat = 1080
    /// Ideal onboarding window height.
    public static let onboardingIdealHeight: CGFloat = 720
}

/// Semantic color roles. Mapped to system colors for light/dark compatibility.
public enum SemanticColorRole: String, Sendable, CaseIterable {
    case background
    case secondaryBackground
    case primaryText
    case secondaryText
    case accent
    case danger
    case success
}

/// Resolves semantic roles to SwiftUI colors using system colors.
public enum SemanticColors {
    /// Returns a system-backed color for the given role.
    public static func color(for role: SemanticColorRole) -> Color {
        switch role {
        case .background:
            return Color(nsColor: .windowBackgroundColor)
        case .secondaryBackground:
            return Color(nsColor: .controlBackgroundColor)
        case .primaryText:
            return Color(nsColor: .labelColor)
        case .secondaryText:
            return Color(nsColor: .secondaryLabelColor)
        case .accent:
            return Color.accentColor
        case .danger:
            return Color(nsColor: .systemRed)
        case .success:
            return Color(nsColor: .systemGreen)
        }
    }
}

/// Commandly brand blues for surfaces that intentionally depart from system accent.
///
/// Prefer `SemanticColors` for standard chrome. Use this palette for onboarding
/// and other branded moments that need a consistent blue identity.
public enum BrandPalette {
    /// Primary brand blue (`#4C8DFF`).
    public static let accent = Color(red: 0.298, green: 0.553, blue: 1.0)
    /// Softer blue for secondary emphasis (`#7AAFFF`).
    public static let accentSoft = Color(red: 0.478, green: 0.686, blue: 1.0)
    /// Deep navy used in dark branded backgrounds (`#0B1220`).
    public static let deepBackground = Color(red: 0.043, green: 0.071, blue: 0.125)
    /// Elevated panel / card fill on dark surfaces (`#121A2A`).
    public static let elevatedSurface = Color(red: 0.071, green: 0.102, blue: 0.165)
    /// Soft blue glow for feature cards and highlights.
    public static let glow = Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.35)
    /// Muted stroke for progress dashes and dividers.
    public static let mutedStroke = Color.white.opacity(0.14)
}
