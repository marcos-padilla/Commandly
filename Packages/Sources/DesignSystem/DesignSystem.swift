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
    /// Minimum width that keeps the Applications table and inspector readable side by side.
    public static let settingsApplicationsMinWidth: CGFloat = 1_200
    /// Minimum height for the hierarchy-and-inspector Applications settings pane.
    public static let settingsApplicationsMinHeight: CGFloat = 640
    /// Preferred Settings window width on first presentation.
    public static let settingsIdealWidth: CGFloat = 1_280
    /// Preferred Settings window height on first presentation.
    public static let settingsIdealHeight: CGFloat = 720
    /// Settings sidebar width.
    public static let settingsSidebarWidth: CGFloat = 188
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

/// Adaptive colors for the keyboard launcher itself.
///
/// The dark appearance layers a near-black navy tint over a native blur material.
/// The tint preserves legibility while allowing restrained desktop color and
/// luminance to show through like a native macOS utility panel.
public enum LauncherPalette {
    /// Main launcher canvas. Alpha intentionally preserves the material beneath it.
    public static let canvas = adaptiveColor(
        light: NSColor(red: 0.930, green: 0.950, blue: 0.980, alpha: 0.68),
        dark: NSColor(red: 0.018, green: 0.028, blue: 0.050, alpha: 0.68)
    )
    /// Header and footer chrome.
    public static let chrome = adaptiveColor(
        light: NSColor(red: 0.900, green: 0.925, blue: 0.965, alpha: 0.58),
        dark: NSColor(red: 0.030, green: 0.046, blue: 0.078, alpha: 0.64)
    )
    /// Slightly lifted list surface used by command sidebars.
    public static let sidebar = adaptiveColor(
        light: NSColor(red: 0.925, green: 0.945, blue: 0.975, alpha: 0.50),
        dark: NSColor(red: 0.025, green: 0.040, blue: 0.070, alpha: 0.56)
    )
    /// Detail canvas, intentionally quieter than the sidebar.
    public static let detail = adaptiveColor(
        light: NSColor(red: 0.960, green: 0.975, blue: 0.990, alpha: 0.46),
        dark: NSColor(red: 0.016, green: 0.026, blue: 0.046, alpha: 0.50)
    )
    /// Selected-row fill with enough contrast in both appearances.
    public static let selection = adaptiveColor(
        light: NSColor(red: 0.200, green: 0.420, blue: 0.780, alpha: 0.13),
        dark: NSColor(red: 0.255, green: 0.520, blue: 0.980, alpha: 0.18)
    )
    /// Hairline separators and selected-row outlines.
    public static let separator = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.09),
        dark: NSColor.white.withAlphaComponent(0.09)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

/// Adaptive material tints for the macOS Settings window.
public enum SettingsPalette {
    /// Translucent window tint placed over the native blur material.
    public static let canvas = adaptiveColor(
        light: NSColor(red: 0.930, green: 0.950, blue: 0.980, alpha: 0.58),
        dark: NSColor(red: 0.022, green: 0.032, blue: 0.054, alpha: 0.64)
    )
    /// Sidebar tint, slightly more saturated than the detail canvas.
    public static let sidebar = adaptiveColor(
        light: NSColor(red: 0.875, green: 0.915, blue: 0.970, alpha: 0.48),
        dark: NSColor(red: 0.028, green: 0.050, blue: 0.086, alpha: 0.56)
    )
    /// Very low-opacity tint used under native Liquid Glass cards.
    public static let card = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.13),
        dark: NSColor.white.withAlphaComponent(0.035)
    )
    /// Hairline used around glass cards and between the sidebar and detail pane.
    public static let border = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.42),
        dark: NSColor.white.withAlphaComponent(0.10)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}
