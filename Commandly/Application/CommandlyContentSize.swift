import SwiftUI
import DesignSystem

extension AppTextSizePreference {
    /// Point-size multiplier for Commandly UI chrome and copy.
    nonisolated var scaleFactor: CGFloat {
        switch self {
        case .standard:
            return CommandlyTextScale.standard
        case .larger:
            return CommandlyTextScale.larger
        }
    }

    /// Dynamic Type bucket paired with the preference for semantic fonts.
    nonisolated var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .standard:
            return .medium
        case .larger:
            return .xLarge
        }
    }
}

extension AppViewModePreference {
    /// Layout metrics for the selected view mode.
    nonisolated var layoutDensity: CommandlyLayoutDensity {
        switch self {
        case .comfortable:
            return .comfortable
        case .compact:
            return .compact
        }
    }
}

extension View {
    /// Applies persisted text-size preference to scaled fonts and Dynamic Type.
    func commandlyContentSize(_ preference: AppTextSizePreference) -> some View {
        self
            .commandlyTextScale(preference.scaleFactor)
            .dynamicTypeSize(preference.dynamicTypeSize)
            .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: preference)
    }

    /// Applies persisted view-mode density to launcher and settings layout.
    func commandlyViewMode(_ preference: AppViewModePreference) -> some View {
        commandlyLayoutDensity(preference.layoutDensity)
    }
}
