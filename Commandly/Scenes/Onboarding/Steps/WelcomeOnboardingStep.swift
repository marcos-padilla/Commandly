import SwiftUI
import DesignSystem

struct WelcomeOnboardingStep: View {
    var body: some View {
        VStack(spacing: Spacing.lg.rawValue) {
            Spacer(minLength: Spacing.xxl.rawValue)

            OnboardingMark(size: 76)

            VStack(spacing: Spacing.sm.rawValue) {
                Text("Command your Mac.")
                    .commandlyFont(size: 40, weight: .bold, design: .rounded)
                    .foregroundStyle(BrandPalette.accent)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Let's set you up with a fast, private, keyboard-first launcher for everyday work.")
                    .commandlyFont(size: 16, weight: .regular)
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xxl.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.xxl.rawValue)
        .accessibilityElement(children: .combine)
    }
}
