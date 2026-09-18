import DesignSystem
import SwiftUI

/// A compact filled line chart for one rolling metric history.
///
/// Values are fractions of the chart's own height, `0...1`, so a series never needs a scale of
/// its own and two charts stacked above each other stay comparable.
struct PanelSparkline: View {
    let values: [Double]
    var tint: Color
    var height: CGFloat = 34
    /// Draws a filled area under the line. Off for a series shown beside another one.
    var isFilled = true

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, size.width > 0, size.height > 0 else { return }

            let step = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - CGFloat(min(max(value, 0), 1)) * size.height
                )
            }

            var line = Path()
            line.addLines(points)

            if isFilled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0.32), tint.opacity(0.02)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            context.stroke(
                line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Two series drawn on one set of axes, as the network and disk activity charts do.
struct PanelDualSparkline: View {
    let primary: [Double]
    let secondary: [Double]
    var primaryTint: Color
    var secondaryTint: Color
    var height: CGFloat = 40

    var body: some View {
        ZStack {
            PanelSparkline(values: primary, tint: primaryTint, height: height)
            PanelSparkline(values: secondary, tint: secondaryTint, height: height)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A thin capsule meter for a single fraction.
struct PanelMeter: View {
    let fraction: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LauncherPalette.separator)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
