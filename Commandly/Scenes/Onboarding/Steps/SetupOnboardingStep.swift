import SwiftUI
import DesignSystem

/// Setup preferences step — stacked choice cards, distinct from competitor onboarding layouts.
struct SetupOnboardingStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.xxl.rawValue)
                .padding(.top, Spacing.xxl.rawValue + Spacing.md.rawValue)
                .padding(.bottom, Spacing.xl.rawValue)

            VStack(spacing: Spacing.md.rawValue) {
                SetupPreferenceCard(
                    icon: "power.circle.fill",
                    title: "Open at Login",
                    subtitle: "Launch Commandly automatically when you sign in to your Mac.",
                    isOn: Binding(
                        get: { viewModel.opensAtLogin },
                        set: { viewModel.setOpensAtLogin($0) }
                    ),
                    isDisabled: viewModel.isUpdatingLoginItem
                )

                SetupPreferenceCard(
                    icon: "face.smiling.inverse",
                    title: "Commandly Emoji Picker",
                    subtitle: "Prefer Commandly's emoji picker when it ships. We'll remember this choice.",
                    isOn: Binding(
                        get: { viewModel.prefersCommandlyEmojiPicker },
                        set: { viewModel.setPrefersCommandlyEmojiPicker($0) }
                    )
                )

                if let hint = viewModel.loginItemApprovalHint {
                    statusBanner(text: hint, tone: .info)
                }

                if let error = viewModel.loginItemErrorMessage {
                    statusBanner(text: error, tone: .error)
                }
            }
            .padding(.horizontal, Spacing.xxl.rawValue)
            .frame(maxWidth: 640, alignment: .leading)

            Spacer(minLength: Spacing.lg.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            Task { await viewModel.preparePreferencesStep() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md.rawValue) {
            Text("Setup")
                .commandlyFont(size: 11, weight: .semibold)
                .tracking(0.6)
                .foregroundStyle(BrandPalette.accentSoft)
                .padding(.horizontal, Spacing.sm.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue + 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )

            Text("Make it feel familiar")
                .commandlyFont(size: 36, weight: .bold, design: .rounded)
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .accessibilityAddTraits(.isHeader)

            Text("Two quick choices. Change them anytime later—nothing here leaves your Mac.")
                .commandlyFont(size: 15, weight: .regular)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .frame(maxWidth: 480, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private enum BannerTone {
        case info
        case error
    }

    private func statusBanner(text: String, tone: BannerTone) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm.rawValue) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .commandlyFont(size: 13, weight: .semibold)
                .foregroundStyle(tone == .error ? SemanticColors.color(for: .danger) : BrandPalette.accentSoft)

            Text(text)
                .commandlyFont(size: 12, weight: .medium)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(BrandPalette.elevatedSurface.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SetupPreferenceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md.rawValue) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(BrandPalette.accent.opacity(isOn ? 0.28 : 0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .commandlyFont(size: 18, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs.rawValue) {
                Text(title)
                    .commandlyFont(size: 15, weight: .semibold)
                    .foregroundStyle(SemanticColors.color(for: .primaryText))

                Text(subtitle)
                    .commandlyFont(size: 12, weight: .regular)
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm.rawValue)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(BrandPalette.accent)
                .disabled(isDisabled)
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .padding(Spacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                .fill(BrandPalette.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            BrandPalette.accent.opacity(isOn ? 0.45 : 0.12),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: BrandPalette.accent.opacity(isOn ? 0.14 : 0.04), radius: 16, y: 6)
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: isOn)
    }
}

#Preview {
    SetupOnboardingStep(viewModel: .preview(step: .preferences))
        .frame(width: 960, height: 640)
        .background(OnboardingBackdrop())
        .preferredColorScheme(.dark)
}
