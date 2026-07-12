import SwiftUI
import DesignSystem

struct FeaturesOnboardingStep: View {
    let features: [OnboardingFeature]

    private let cardWidth: CGFloat = 210
    private let cardPreviewHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            introHeader
                .padding(.horizontal, Spacing.xxl.rawValue)
                .padding(.top, Spacing.xxl.rawValue + Spacing.md.rawValue)
                .padding(.bottom, Spacing.xl.rawValue)

            featureCarousel
                .frame(maxHeight: .infinity, alignment: .center)

            Spacer(minLength: Spacing.lg.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md.rawValue) {
            Text("Built-in")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(BrandPalette.accentSoft)
                .padding(.horizontal, Spacing.sm.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue + 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )

            Text("From the start")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .accessibilityAddTraits(.isHeader)

            Text("Commandly ships the everyday productivity tools that keep you moving—without leaving the keyboard.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var featureCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md.rawValue) {
                ForEach(features) { feature in
                    FeatureShowcaseCard(
                        feature: feature,
                        width: cardWidth,
                        previewHeight: cardPreviewHeight
                    )
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.72)
                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.xxl.rawValue)
            .padding(.vertical, Spacing.sm.rawValue)
        }
        .scrollTargetBehavior(.viewAligned)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Spacing.lg.rawValue)

                Color.black

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Spacing.xl.rawValue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feature highlights")
        .accessibilityHint("Scroll horizontally to see more features")
    }
}

struct FeatureShowcaseCard: View {
    let feature: OnboardingFeature
    var width: CGFloat = 210
    var previewHeight: CGFloat = 168

    var body: some View {
        VStack(spacing: Spacing.sm.rawValue) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .fill(BrandPalette.elevatedSurface)

                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                BrandPalette.accent.opacity(0.28),
                                BrandPalette.accent.opacity(0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )

                FeaturePreviewIllustration(featureID: feature.id)
                    .padding(Spacing.md.rawValue)
            }
            .frame(width: width, height: previewHeight)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: BrandPalette.accent.opacity(0.12), radius: 18, y: 8)

            Text(feature.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .multilineTextAlignment(.center)
                .frame(width: width)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.blurb)")
    }
}

/// Lightweight, feature-specific illustrations for the showcase cards.
private struct FeaturePreviewIllustration: View {
    let featureID: String

    var body: some View {
        Group {
            switch featureID {
            case "launcher":
                launcherPreview
            case "search":
                searchPreview
            case "clipboard":
                clipboardPreview
            case "links":
                linksPreview
            case "snippets":
                snippetsPreview
            case "windows":
                windowsPreview
            default:
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(BrandPalette.accentSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var launcherPreview: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(height: 22)
                .overlay(alignment: .leading) {
                    HStack(spacing: Spacing.xxs.rawValue) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Open…")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.leading, Spacing.xs.rawValue)
                }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == 1 ? BrandPalette.accent.opacity(0.55) : Color.white.opacity(0.08))
                        .frame(height: 28)
                }
            }
        }
        .padding(Spacing.xs.rawValue)
    }

    private var searchPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            capsuleRow(icon: "magnifyingglass", text: "calendar tomorrow", emphasized: true)
            resultRow(title: "Meetings", subtitle: "Command")
            resultRow(title: "Calendar.app", subtitle: "Application")
            resultRow(title: "Notes", subtitle: "File")
        }
        .padding(Spacing.xs.rawValue)
    }

    private var clipboardPreview: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            ForEach(["doc.text", "photo", "link", "list.bullet"], id: \.self) { icon in
                VStack(spacing: Spacing.xxs.rawValue) {
                    RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 44)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BrandPalette.accentSoft)
                        }
                }
            }
        }
    }

    private var linksPreview: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            ForEach(
                [("globe", "Docs"), ("envelope", "Inbox"), ("hammer", "Build")],
                id: \.0
            ) { icon, label in
                HStack(spacing: Spacing.xs.rawValue) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrandPalette.accentSoft)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .padding(.horizontal, Spacing.xs.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue + 1)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
        .padding(Spacing.xs.rawValue)
    }

    private var snippetsPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
            Text(";addr")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.accentSoft)
                .padding(.horizontal, Spacing.xs.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: Spacing.xxs.rawValue) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 110, height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 86, height: 6)
            }
            .padding(Spacing.sm.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .padding(Spacing.xs.rawValue)
    }

    private var windowsPreview: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(BrandPalette.accent.opacity(0.35))
                .frame(width: 52)
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .padding(Spacing.sm.rawValue)
    }

    private func capsuleRow(icon: String, text: String, emphasized: Bool) -> some View {
        HStack(spacing: Spacing.xxs.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(emphasized ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, Spacing.xxs.rawValue + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(emphasized ? BrandPalette.accent.opacity(0.28) : Color.white.opacity(0.06))
        )
    }

    private func resultRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(subtitle)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, Spacing.xxs.rawValue)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
