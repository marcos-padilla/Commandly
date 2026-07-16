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
    case xxl = 28
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

/// Shared motion curves for navigation and compact control feedback.
public enum CommandlyMotion {
    /// A calm spring for sidebar, page, and presentation changes.
    public static let navigation = Animation.spring(response: 0.36, dampingFraction: 0.88)
    /// A tighter spring for compact interactive controls.
    public static let control = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// A restrained hover transition that does not call attention to itself.
    public static let hover = Animation.easeOut(duration: MotionDuration.fast.rawValue)
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
    public static let settingsMinWidth: CGFloat = 900
    /// Default settings window height.
    public static let settingsMinHeight: CGFloat = 560
    /// Minimum width that keeps the Applications table and inspector readable side by side.
    public static let settingsApplicationsMinWidth: CGFloat = 900
    /// Minimum height for the hierarchy-and-inspector Applications settings pane.
    public static let settingsApplicationsMinHeight: CGFloat = 640
    /// Preferred Settings window width on first presentation.
    public static let settingsIdealWidth: CGFloat = 1_080
    /// Preferred Settings window height on first presentation.
    public static let settingsIdealHeight: CGFloat = 720
    /// Settings sidebar width.
    public static let settingsSidebarWidth: CGFloat = 228
    /// Minimum width for the searchable documentation browser.
    public static let documentationMinWidth: CGFloat = 880
    /// Minimum height for the searchable documentation browser.
    public static let documentationMinHeight: CGFloat = 600
    /// Preferred documentation window width on first presentation.
    public static let documentationIdealWidth: CGFloat = 1_180
    /// Preferred documentation window height on first presentation.
    public static let documentationIdealHeight: CGFloat = 760
    /// Documentation navigation sidebar width.
    public static let documentationSidebarWidth: CGFloat = 268
    /// Minimum onboarding window width.
    public static let onboardingMinWidth: CGFloat = 960
    /// Minimum onboarding window height.
    public static let onboardingMinHeight: CGFloat = 640
    /// Ideal onboarding window width.
    public static let onboardingIdealWidth: CGFloat = 1080
    /// Ideal onboarding window height.
    public static let onboardingIdealHeight: CGFloat = 720
    /// Floating Shelf board edge length (square).
    public static let shelfBoardSize: CGFloat = 188
    /// Width of Shelf's integrated item-detail board.
    public static let shelfDetailWidth: CGFloat = 420
    /// Height of Shelf's integrated item-detail board.
    public static let shelfDetailHeight: CGFloat = 360
    /// Height reserved for the direct-action targets shown during an incoming drag.
    public static let shelfInstantActionsHeight: CGFloat = 58
    /// Margin from the screen edge when placing Shelf in a preferred corner.
    public static let shelfScreenMargin: CGFloat = 28
    /// Continuous corner radius for the floating Shelf board.
    public static let shelfCornerRadius: CGFloat = 28
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

/// Semantic accent families for status, warning, success, and destructive moments.
///
/// Standard navigation and content stay neutral. When one of these colors is used,
/// labels, symbols, and accessibility state continue to carry the meaning.
public enum CommandlyTint: Sendable {
    case blue
    case cyan
    case teal
    case mint
    case green
    case yellow
    case orange
    case red
    case pink
    case purple
    case indigo
    case graphite

    /// System-backed color that adapts to the current appearance and contrast settings.
    public var color: Color {
        switch self {
        case .blue: return Color(nsColor: .systemBlue)
        case .cyan: return Color(nsColor: .systemCyan)
        case .teal: return Color(nsColor: .systemTeal)
        case .mint: return Color(nsColor: .systemMint)
        case .green: return Color(nsColor: .systemGreen)
        case .yellow: return Color(nsColor: .systemYellow)
        case .orange: return Color(nsColor: .systemOrange)
        case .red: return Color(nsColor: .systemRed)
        case .pink: return Color(nsColor: .systemPink)
        case .purple: return Color(nsColor: .systemPurple)
        case .indigo: return Color(nsColor: .systemIndigo)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    /// A subtle fill for icon backgrounds, badges, and status callouts.
    public var softFill: Color {
        color.opacity(0.16)
    }
}

/// Neutral adaptive colors for the keyboard launcher.
///
/// The launcher gets its depth from the native window material. These overlays are
/// deliberately achromatic so results, focus, and real application artwork carry
/// the hierarchy instead of decorative brand color.
public enum LauncherPalette {
    /// Main launcher canvas. Alpha intentionally preserves the material beneath it.
    public static let canvas = adaptiveColor(
        light: NSColor(white: 0.94, alpha: 0.46),
        dark: NSColor(white: 0.075, alpha: 0.54)
    )
    /// Header and footer chrome.
    public static let chrome = adaptiveColor(
        light: NSColor(white: 0.94, alpha: 0.24),
        dark: NSColor(white: 0.10, alpha: 0.24)
    )
    /// Slightly lifted list surface used by command sidebars.
    public static let sidebar = adaptiveColor(
        light: NSColor(white: 0.92, alpha: 0.42),
        dark: NSColor(white: 0.09, alpha: 0.46)
    )
    /// Detail canvas, intentionally quieter than the sidebar.
    public static let detail = adaptiveColor(
        light: NSColor(white: 0.97, alpha: 0.40),
        dark: NSColor(white: 0.065, alpha: 0.44)
    )
    /// Selected-row fill with enough contrast in both appearances.
    public static let selection = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.105)
    )
    /// Quiet content card fill used for selected calculations and detail groupings.
    public static let surface = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.38),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    /// Hover fill for content rows; intentionally subtler than selection.
    public static let hover = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.055)
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

/// Neutral adaptive material tints for the macOS Settings window.
public enum SettingsPalette {
    /// Translucent window tint placed over the native blur material.
    public static let canvas = adaptiveColor(
        light: NSColor(white: 0.94, alpha: 0.70),
        dark: NSColor(white: 0.085, alpha: 0.76)
    )
    /// Sidebar tint, separated from the detail plane by luminance rather than hue.
    public static let sidebar = adaptiveColor(
        light: NSColor(white: 0.90, alpha: 0.80),
        dark: NSColor(white: 0.105, alpha: 0.84)
    )
    /// Quieter and more opaque detail canvas behind readable content.
    public static let detail = adaptiveColor(
        light: NSColor(white: 0.965, alpha: 0.94),
        dark: NSColor(white: 0.13, alpha: 0.94)
    )
    /// Standard material-like fill for grouped content in the detail layer.
    public static let surface = adaptiveColor(
        light: NSColor.clear,
        dark: NSColor.clear
    )
    /// Slightly stronger grouped fill for nested or selected content.
    public static let elevatedSurface = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.045)
    )
    /// Low-contrast input fill used beneath native text controls.
    public static let field = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    /// Accent wash for selected navigation rows and focused content.
    public static let selection = Color.accentColor.opacity(0.22)
    /// Quiet pointer-hover treatment for navigation and content rows.
    public static let hover = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.065)
    )
    /// Native accent-backed focus ring for custom fields.
    public static let focusRing = Color.accentColor.opacity(0.48)
    /// Compatibility alias for legacy grouped surfaces; new Settings content is flat.
    public static let card = adaptiveColor(
        light: NSColor.clear,
        dark: NSColor.clear
    )
    /// Hairline used around glass cards and between the sidebar and detail pane.
    public static let border = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.095),
        dark: NSColor.white.withAlphaComponent(0.105)
    )
    /// Restrained shadow color for floating controls and transient overlays.
    public static let shadow = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.black.withAlphaComponent(0.30)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}
