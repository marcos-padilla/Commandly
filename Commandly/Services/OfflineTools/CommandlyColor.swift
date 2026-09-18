import AppKit
import Foundation

/// One finite, bounded, gamma-encoded sRGB color. No color profile, device or permission is read.
nonisolated struct CommandlyColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Finite values clamp to sRGB/alpha bounds. Non-finite inputs fail instead of reaching integer
    /// serialization or AppKit with NaN/infinity. The existing optional screen-sampler accepts nil.
    init?(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        guard red.isFinite, green.isFinite, blue.isFinite, alpha.isFinite else { return nil }
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    init?(string: String) {
        guard let parsed = CommandlyColorParser.parse(string) else { return nil }
        self = parsed
    }

    /// Compatibility forms retain alpha; the explicit `.hex` output format is always six digits.
    var hex: String { formatted(alpha < 1 ? .hexWithAlpha : .hex) }
    var rgb: String {
        alpha < 1 ? formatted(.rgba) : "rgb(\(Self.decimal(red * 255)), \(Self.decimal(green * 255)), \(Self.decimal(blue * 255)))"
    }
    var hsl: String { formatted(.hsl) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var defaultFormat: CommandlyColorFormat { alpha < 1 ? .hexWithAlpha : .hex }

    func formatted(_ format: CommandlyColorFormat) -> String {
        switch format {
        case .hex, .hexWithAlpha:
            let channels = [red, green, blue] + (format == .hexWithAlpha ? [alpha] : [])
            return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        case .rgba:
            return "rgba(\(Self.decimal(red * 255)), \(Self.decimal(green * 255)), \(Self.decimal(blue * 255)), \(Self.decimal(alpha)))"
        case .rgbaPercentage:
            return "rgba(\(Self.decimal(red * 100))%, \(Self.decimal(green * 100))%, \(Self.decimal(blue * 100))%, \(Self.decimal(alpha * 100))%)"
        case .rgbCSS4:
            return "rgb(\(Self.decimal(red * 255)) \(Self.decimal(green * 255)) \(Self.decimal(blue * 255)) / \(Self.decimal(alpha)))"
        case .hsl:
            let maximum = max(red, green, blue), minimum = min(red, green, blue)
            let lightness = (maximum + minimum) / 2
            let delta = maximum - minimum
            var hue = 0.0
            var saturation = 0.0
            if delta > 0 {
                // This equivalent denominator avoids cancellation at nearly black/white values.
                saturation = delta / (lightness <= 0.5 ? maximum + minimum : 2 - maximum - minimum)
                if maximum == red { hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
                else if maximum == green { hue = 60 * (((blue - red) / delta) + 2) }
                else { hue = 60 * (((red - green) / delta) + 4) }
                if hue < 0 { hue += 360 }
            }
            let components = "\(Self.decimal(hue)) \(Self.decimal(saturation * 100))% \(Self.decimal(lightness * 100))%"
            return "hsl(\(components) / \(Self.decimal(alpha)))"
        }
    }

    private static func decimal(_ value: Double) -> String {
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

/// Explicit outputs shown in Color Tools and root color-result actions in the same stable order.
nonisolated enum CommandlyColorFormat: String, CaseIterable, Identifiable, Sendable {
    case hex, hexWithAlpha, rgba, rgbaPercentage, rgbCSS4, hsl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hex: "Hex"
        case .hexWithAlpha: "Hex with Alpha"
        case .rgba: "RGBA"
        case .rgbaPercentage: "RGBA (Percentage)"
        case .rgbCSS4: "RGB (CSS4)"
        case .hsl: "HSL"
        }
    }
    var preservesAlpha: Bool { self != .hex }
}
