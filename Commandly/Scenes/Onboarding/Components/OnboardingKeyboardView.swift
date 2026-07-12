import SwiftUI
import DesignSystem

/// Full MacBook Pro keyboard that mirrors live hardware key presses.
struct OnboardingKeyboardView: View {
    var pressedKeyIDs: Set<MacKeyboardKeyID>
    var isCelebrating: Bool

    @State private var pulse = false

    private let keySpacing: CGFloat = 5
    private let rowSpacing: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let metrics = KeyboardMetrics.make(
                availableWidth: proxy.size.width,
                keySpacing: keySpacing
            )

            VStack(spacing: rowSpacing) {
                ForEach(Array(MacBookProKeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                    keyboardRow(row, metrics: metrics)
                }
            }
            .padding(Spacing.md.rawValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(
                color: BrandPalette.accent.opacity(isCelebrating ? 0.35 : 0.12),
                radius: isCelebrating ? 36 : 18,
                y: 12
            )
            .scaleEffect(isCelebrating ? 1.015 : 1.0)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: isCelebrating)
        }
        .aspectRatio(1.72, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Full MacBook Pro keyboard. Option and Space are highlighted for the shortcut.")
    }

    @ViewBuilder
    private func keyboardRow(_ row: [MacKeyboardKeySpec], metrics: KeyboardMetrics) -> some View {
        // Arrow cluster is rendered as a special group on the modifier row.
        if row.contains(where: { $0.id == .leftArrow }) {
            modifierRow(row, metrics: metrics)
        } else {
            HStack(spacing: keySpacing) {
                ForEach(row) { key in
                    keyView(for: key, metrics: metrics)
                }
            }
        }
    }

    private func modifierRow(_ row: [MacKeyboardKeySpec], metrics: KeyboardMetrics) -> some View {
        let leading = row.filter {
            ![MacKeyboardKeyID.leftArrow, .upArrow, .downArrow, .rightArrow].contains($0.id)
        }

        return HStack(spacing: keySpacing) {
            ForEach(leading) { key in
                keyView(for: key, metrics: metrics)
            }

            Spacer(minLength: keySpacing)

            arrowCluster(metrics: metrics)
        }
    }

    private func arrowCluster(metrics: KeyboardMetrics) -> some View {
        let width = metrics.width(forUnits: 1)
        let height = metrics.keyHeight

        return HStack(spacing: keySpacing) {
            keyView(
                for: MacKeyboardKeySpec(id: .leftArrow, label: "←", keyCodes: [123]),
                metrics: metrics
            )

            VStack(spacing: 3) {
                keyView(
                    for: MacKeyboardKeySpec(id: .upArrow, label: "↑", keyCodes: [126]),
                    metrics: metrics,
                    heightOverride: (height - 3) / 2
                )
                keyView(
                    for: MacKeyboardKeySpec(id: .downArrow, label: "↓", keyCodes: [125]),
                    metrics: metrics,
                    heightOverride: (height - 3) / 2
                )
            }
            .frame(width: width)

            keyView(
                for: MacKeyboardKeySpec(id: .rightArrow, label: "→", keyCodes: [124]),
                metrics: metrics
            )
        }
    }

    private func keyView(
        for key: MacKeyboardKeySpec,
        metrics: KeyboardMetrics,
        heightOverride: CGFloat? = nil
    ) -> some View {
        let pressed = isPressed(key.id)
        let shouldPulse = key.isHotkeyTarget && pulse && !pressed && !isCelebrating

        return KeyboardKeyView(
            label: key.label,
            caption: key.caption,
            width: metrics.width(forUnits: key.widthUnits),
            height: heightOverride ?? (key.isFunctionRow ? metrics.functionKeyHeight : metrics.keyHeight),
            isAccent: key.isHotkeyTarget,
            isPressed: pressed,
            pulse: shouldPulse,
            isFunctionRow: key.isFunctionRow
        )
    }

    private func isPressed(_ id: MacKeyboardKeyID) -> Bool {
        if isCelebrating, id == .leftOption || id == .rightOption || id == .space {
            return true
        }
        return pressedKeyIDs.contains(id)
    }
}

private struct KeyboardMetrics {
    let unitWidth: CGFloat
    let keyHeight: CGFloat
    let functionKeyHeight: CGFloat

    static func make(availableWidth: CGFloat, keySpacing: CGFloat) -> KeyboardMetrics {
        // Widest row is the number row: 13×1 + delete 1.6 = 14.6 units, 13 gaps.
        let units: CGFloat = 14.6
        let gaps: CGFloat = 13
        let usable = max(availableWidth - (gaps * keySpacing), 1)
        let unit = floor((usable / units) * 10) / 10
        return KeyboardMetrics(
            unitWidth: unit,
            keyHeight: max(unit * 0.92, 28),
            functionKeyHeight: max(unit * 0.72, 22)
        )
    }

    func width(forUnits units: CGFloat) -> CGFloat {
        // Account for internal spacing between fractional units as continuous width.
        unitWidth * units
    }
}

private struct KeyboardKeyView: View {
    let label: String
    var caption: String?
    var width: CGFloat
    var height: CGFloat
    var isAccent: Bool
    var isPressed: Bool
    var pulse: Bool
    var isFunctionRow: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isFunctionRow ? 7 : 8, style: .continuous)
                .fill(keyFill)
                .overlay(
                    RoundedRectangle(cornerRadius: isFunctionRow ? 7 : 8, style: .continuous)
                        .strokeBorder(keyStroke, lineWidth: isAccent ? 1.4 : 1)
                )
                .shadow(
                    color: glowColor,
                    radius: isPressed ? 12 : (pulse ? 10 : (isAccent ? 5 : 0)),
                    y: 0
                )

            VStack(spacing: 1) {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(
                            size: fontSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(labelColor)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: isFunctionRow ? 6 : 7, weight: .medium))
                        .foregroundStyle(captionColor)
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .offset(y: isPressed ? 1 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .animation(.easeInOut(duration: 1.1), value: pulse)
    }

    private var fontSize: CGFloat {
        if isFunctionRow { return 9 }
        if caption != nil { return 12 }
        return label.count > 1 ? 10 : 12
    }

    private var labelColor: Color {
        if isAccent { return .white }
        if isPressed { return .white.opacity(0.95) }
        return .white.opacity(isFunctionRow ? 0.45 : 0.62)
    }

    private var captionColor: Color {
        if isAccent { return BrandPalette.accentSoft }
        return .white.opacity(0.32)
    }

    private var glowColor: Color {
        if isAccent {
            return BrandPalette.accent.opacity(isPressed ? 0.7 : (pulse ? 0.45 : 0.22))
        }
        if isPressed {
            return BrandPalette.accent.opacity(0.35)
        }
        return .clear
    }

    private var keyFill: LinearGradient {
        if isAccent {
            return LinearGradient(
                colors: [
                    BrandPalette.accent.opacity(isPressed ? 0.95 : 0.55),
                    BrandPalette.accent.opacity(isPressed ? 0.75 : 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isPressed {
            return LinearGradient(
                colors: [
                    BrandPalette.accent.opacity(0.45),
                    BrandPalette.accent.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(isFunctionRow ? 0.06 : 0.09),
                Color.white.opacity(0.035)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var keyStroke: Color {
        if isAccent {
            return BrandPalette.accentSoft.opacity(isPressed ? 0.95 : 0.65)
        }
        if isPressed {
            return BrandPalette.accentSoft.opacity(0.55)
        }
        return Color.white.opacity(0.08)
    }
}
