import SwiftUI

/// Layout density tokens for Comfortable vs Compact view modes.
public struct CommandlyLayoutDensity: Equatable, Sendable {
    /// Multiplier applied to spacing and padding baselines.
    public var spacingScale: CGFloat
    /// Vertical padding inside list / settings rows.
    public var rowVerticalPadding: CGFloat
    /// Horizontal padding inside list rows.
    public var rowHorizontalPadding: CGFloat
    /// Icon tile size in launcher rows.
    public var iconSize: CGFloat
    /// Launcher panel height.
    public var launcherHeight: CGFloat
    /// Search field vertical padding.
    public var searchVerticalPadding: CGFloat
    /// Section header top padding.
    public var sectionHeaderTopPadding: CGFloat
    /// Settings page stack spacing.
    public var pageStackSpacing: CGFloat

    public static let comfortable = CommandlyLayoutDensity(
        spacingScale: 1.0,
        rowVerticalPadding: 3,
        rowHorizontalPadding: 8,
        iconSize: 24,
        launcherHeight: LayoutConstants.launcherIdealHeight,
        searchVerticalPadding: 10,
        sectionHeaderTopPadding: 6,
        pageStackSpacing: 12
    )

    public static let compact = CommandlyLayoutDensity(
        spacingScale: 0.82,
        rowVerticalPadding: 2,
        rowHorizontalPadding: 7,
        iconSize: 21,
        launcherHeight: 400,
        searchVerticalPadding: 7,
        sectionHeaderTopPadding: 4,
        pageStackSpacing: 8
    )

    public func spacing(_ token: Spacing) -> CGFloat {
        token.rawValue * spacingScale
    }
}

private struct CommandlyLayoutDensityKey: EnvironmentKey {
    static let defaultValue = CommandlyLayoutDensity.comfortable
}

public extension EnvironmentValues {
    /// Comfortable vs compact layout metrics for Commandly surfaces.
    var commandlyLayoutDensity: CommandlyLayoutDensity {
        get { self[CommandlyLayoutDensityKey.self] }
        set { self[CommandlyLayoutDensityKey.self] = newValue }
    }
}

public extension View {
    /// Sets layout density for this subtree.
    func commandlyLayoutDensity(_ density: CommandlyLayoutDensity) -> some View {
        environment(\.commandlyLayoutDensity, density)
            .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: density)
    }
}
