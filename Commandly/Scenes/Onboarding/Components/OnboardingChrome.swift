import SwiftUI
import DesignSystem

/// Geometric mark used on the welcome step — original to Commandly, not a competitor logo.
struct OnboardingMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BrandPalette.accent.opacity(0.25),
                            BrandPalette.accent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 1.15, height: size * 1.15)

            Image(systemName: "command")
                .commandlyFont(size: size * 0.42, weight: .semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandPalette.accentSoft, BrandPalette.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .accessibilityHidden(true)
        }
        .frame(width: size * 1.15, height: size * 1.15)
        .accessibilityLabel("Commandly")
    }
}

/// Elegant step progress with morphing active segment and completed-state glow.
struct OnboardingProgressIndicator: View {
    let currentIndex: Int
    let total: Int

    @State private var glowPulse = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(fill(for: index))
                    .frame(width: width(for: index), height: 4)
                    .shadow(color: shadow(for: index), radius: index == currentIndex ? 8 : 0, y: 0)
                    .overlay {
                        if index == currentIndex {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.55),
                                            Color.white.opacity(0.05),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .blendMode(.plusLighter)
                                .opacity(glowPulse ? 0.9 : 0.35)
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: currentIndex)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(total)")
    }

    private func width(for index: Int) -> CGFloat {
        if index == currentIndex { return 28 }
        if index < currentIndex { return 10 }
        return 8
    }

    private func fill(for index: Int) -> some ShapeStyle {
        if index == currentIndex {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [BrandPalette.accentSoft, BrandPalette.accent],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        if index < currentIndex {
            return AnyShapeStyle(BrandPalette.accent.opacity(0.45))
        }
        return AnyShapeStyle(Color.white.opacity(0.14))
    }

    private func shadow(for index: Int) -> Color {
        index == currentIndex ? BrandPalette.accent.opacity(glowPulse ? 0.75 : 0.4) : .clear
    }
}

/// Shared footer chrome: optional back, progress, primary action.
struct OnboardingFooter: View {
    let stepIndex: Int
    let stepCount: Int
    let showsBackButton: Bool
    let showsPrimaryAction: Bool
    let primaryTitle: String
    let onBack: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md.rawValue) {
            HStack(spacing: Spacing.sm.rawValue) {
                if showsBackButton {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .commandlyFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(circleChrome)
                    }
                    .buttonStyle(OnboardingChromeButtonStyle())
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.85)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                    .accessibilityLabel("Back")
                }

                VStack(alignment: .leading, spacing: 6) {
                    OnboardingProgressIndicator(currentIndex: stepIndex, total: stepCount)

                    Text("Step \(stepIndex + 1) of \(stepCount)")
                        .commandlyFont(size: 10, weight: .medium, design: .rounded)
                        .foregroundStyle(Color.white.opacity(0.38))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: stepIndex)
                }
            }

            Spacer(minLength: Spacing.md.rawValue)

            if showsPrimaryAction {
                Button(action: onPrimary) {
                    HStack(spacing: Spacing.xs.rawValue) {
                        Text(primaryTitle)
                            .commandlyFont(size: 13, weight: .semibold, design: .rounded)
                            .contentTransition(.opacity)

                        Image(systemName: "arrow.right")
                            .commandlyFont(size: 11, weight: .semibold)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Spacing.lg.rawValue)
                    .padding(.vertical, 10)
                    .background(primaryBackground)
                    .overlay(primaryBorder)
                    .shadow(color: BrandPalette.accent.opacity(0.35), radius: 16, y: 6)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
                .accessibilityLabel(primaryTitle)
            }
        }
        .padding(.horizontal, Spacing.xl.rawValue)
        .padding(.top, Spacing.md.rawValue)
        .padding(.bottom, Spacing.md.rawValue + 2)
        .background(footerBackground)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsBackButton)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsPrimaryAction)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: primaryTitle)
    }

    private var circleChrome: some View {
        Circle()
            .fill(Color.white.opacity(0.06))
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var primaryBackground: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        BrandPalette.accentSoft,
                        BrandPalette.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.04),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
            }
    }

    private var primaryBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
    }

    private var footerBackground: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(BrandPalette.deepBackground.opacity(0.72))

            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)

            LinearGradient(
                colors: [
                    BrandPalette.accent.opacity(0.10),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            BrandPalette.accent.opacity(0.25),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .opacity(0.9)
        }
    }
}

/// Soft press feedback for circular chrome controls.
private struct OnboardingChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Springy primary CTA with a slight lift on press.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .shadow(
                color: BrandPalette.accent.opacity(configuration.isPressed ? 0.18 : 0.35),
                radius: configuration.isPressed ? 8 : 16,
                y: configuration.isPressed ? 2 : 6
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

/// Dark branded backdrop with a subtle blue wash.
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            BrandPalette.deepBackground

            RadialGradient(
                colors: [
                    BrandPalette.accent.opacity(0.18),
                    BrandPalette.accent.opacity(0.04),
                    .clear
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.clear,
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
