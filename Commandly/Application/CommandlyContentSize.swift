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

extension View {
    /// Applies persisted text-size preference to scaled fonts and Dynamic Type.
    func commandlyContentSize(_ preference: AppTextSizePreference) -> some View {
        self
            .commandlyTextScale(preference.scaleFactor)
            .dynamicTypeSize(preference.dynamicTypeSize)
            .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: preference)
    }
}
