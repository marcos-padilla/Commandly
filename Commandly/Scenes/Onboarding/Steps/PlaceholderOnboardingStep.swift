import SwiftUI
import DesignSystem

/// Lightweight placeholder for steps that will ask preferences or permissions later.
struct PlaceholderOnboardingStep: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: Spacing.lg.rawValue) {
            Spacer(minLength: Spacing.xl.rawValue)

            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(BrandPalette.accentSoft)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.sm.rawValue) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SemanticColors.color(for: .primaryText))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xl.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.xxl.rawValue)
        .accessibilityElement(children: .combine)
    }
}
