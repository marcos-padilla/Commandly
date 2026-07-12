import SwiftUI
import DesignSystem

/// Final onboarding step: teach ⌥Space with a live keyboard and celebration.
struct ReadyOnboardingStep: View {
    @Bindable var viewModel: OnboardingViewModel

    @State private var appeared = false
    @State private var burst = false
    @State private var successOpacity = 0.0

    var body: some View {
        ZStack {
            if viewModel.isCelebratingHotkey {
                celebrationLayer
            }

            VStack(spacing: Spacing.lg.rawValue) {
                header
                    .opacity(viewModel.isCelebratingHotkey ? 0.35 : 1)
                    .animation(.easeOut(duration: MotionDuration.normal.rawValue), value: viewModel.isCelebratingHotkey)

                OnboardingKeyboardView(
                    pressedKeyIDs: viewModel.pressedKeyIDs,
                    isCelebrating: viewModel.isCelebratingHotkey
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .rotation3DEffect(
                    .degrees(appeared ? 0 : 6),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.65
                )

                instructionChip
                    .opacity(viewModel.isCelebratingHotkey ? 0 : 1)

                if viewModel.isCelebratingHotkey {
                    successBanner
                        .opacity(successOpacity)
                        .scaleEffect(successOpacity > 0 ? 1 : 0.9)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xl.rawValue)
            .padding(.top, Spacing.xl.rawValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            HotkeyEventMonitor(
                isEnabled: viewModel.step == .ready && viewModel.hotkeyPhase == .waiting,
                onPressedKeysChange: { keys in
                    viewModel.updatePressedKeys(keys)
                },
                onOptionSpace: {
                    viewModel.handleOptionSpaceHotkey()
                }
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.05)) {
                appeared = true
            }
        }
        .onChange(of: viewModel.hotkeyPhase) { _, phase in
            guard phase == .celebrating else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                burst = true
                successOpacity = 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Press Option and Space together to open Commandly")
    }

    private var header: some View {
        VStack(spacing: Spacing.sm.rawValue) {
            Text("Hotkey")
                .commandlyFont(size: 11, weight: .semibold)
                .tracking(0.6)
                .foregroundStyle(BrandPalette.accentSoft)
                .padding(.horizontal, Spacing.sm.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue + 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )

            Text("Open Commandly instantly")
                .commandlyFont(size: 28, weight: .bold, design: .rounded)
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Press any key to see it light up. Then hit ⌥ Space to open Commandly.")
                .commandlyFont(size: 14, weight: .regular)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
    }

    private var instructionChip: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            keyBadge("⌥")
            Text("+")
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
            keyBadge("Space")
            Text("to open")
                .commandlyFont(size: 13, weight: .medium)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
        }
        .padding(.horizontal, Spacing.md.rawValue)
        .padding(.vertical, Spacing.sm.rawValue)
        .background(
            Capsule(style: .continuous)
                .fill(BrandPalette.elevatedSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(BrandPalette.accent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityLabel("Press Option Space to open")
    }

    private func keyBadge(_ title: String) -> some View {
        Text(title)
            .commandlyFont(size: 13, weight: .semibold, design: .rounded)
            .foregroundStyle(Color.white)
            .padding(.horizontal, Spacing.sm.rawValue)
            .padding(.vertical, Spacing.xxs.rawValue + 1)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                    .fill(BrandPalette.accent.opacity(0.55))
            )
    }

    private var successBanner: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            Image(systemName: "checkmark.circle.fill")
                .commandlyFont(size: 22, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .symbolEffect(.bounce, value: successOpacity)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.hasConfirmedOptionSpaceHotkey ? "Shortcut locked in" : "You're in")
                    .commandlyFont(size: 16, weight: .semibold)
                    .foregroundStyle(SemanticColors.color(for: .primaryText))
                Text("Opening Commandly…")
                    .commandlyFont(size: 12, weight: .regular)
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
            }
        }
        .padding(.horizontal, Spacing.lg.rawValue)
        .padding(.vertical, Spacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(BrandPalette.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(BrandPalette.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: BrandPalette.accent.opacity(0.25), radius: 20, y: 8)
        .accessibilityLabel("Shortcut confirmed. Opening Commandly.")
    }

    private var celebrationLayer: some View {
        ZStack {
            RadialGradient(
                colors: [
                    BrandPalette.accent.opacity(burst ? 0.35 : 0.0),
                    BrandPalette.accent.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: burst ? 420 : 120
            )
            .blendMode(.plusLighter)
            .animation(.easeOut(duration: 0.9), value: burst)

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(BrandPalette.accentSoft.opacity(0.55))
                    .frame(width: CGFloat(4 + (index % 3)), height: CGFloat(4 + (index % 3)))
                    .offset(
                        x: burst ? burstOffset(index).x : 0,
                        y: burst ? burstOffset(index).y : 0
                    )
                    .opacity(burst ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.9).delay(Double(index) * 0.02),
                        value: burst
                    )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func burstOffset(_ index: Int) -> CGPoint {
        let angle = Double(index) / 12.0 * Double.pi * 2
        let radius = 120.0 + Double(index % 4) * 28.0
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}

#Preview {
    ReadyOnboardingStep(viewModel: .preview(step: .ready))
        .frame(width: 960, height: 640)
        .background(OnboardingBackdrop())
        .preferredColorScheme(.dark)
}
