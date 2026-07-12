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
}

/// Shared layout constants for future surfaces.
public enum LayoutConstants {
    /// Default minimum launcher width.
    public static let launcherMinWidth: CGFloat = 640
    /// Default minimum launcher height.
    public static let launcherMinHeight: CGFloat = 420
    /// Default settings window width.
    public static let settingsMinWidth: CGFloat = 520
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
