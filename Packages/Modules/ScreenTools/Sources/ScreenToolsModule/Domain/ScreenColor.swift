import Foundation

/// A colour sampled from the screen, in sRGB.
///
/// Components are clamped to `0...1` on creation, so a sampler that reports a wide-gamut value
/// outside the range cannot produce nonsense output downstream.
public struct ScreenColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Creates a colour, clamping every component.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(1, max(0, value))
        }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }
}

/// How a sampled colour is written to the clipboard.
///
/// Raw values are persisted as the user's chosen format, so they must stay stable.
public enum ScreenColorFormat: String, Sendable, CaseIterable, Codable {
    case hex
    case hexWithAlpha
    case rgb
    case rgba
    case hsl
    case swiftUI

    /// User-facing name, used by the settings control.
    public var title: String {
        switch self {
        case .hex: return "Hex"
        case .hexWithAlpha: return "Hex with alpha"
        case .rgb: return "RGB"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI"
        }
    }
}

/// Formats a sampled colour as text.
///
/// Pure and deterministic: the same colour and format always produce the same string, which is
/// what makes the output testable without sampling a real screen.
public enum ScreenColorFormatter {
    /// Returns `color` written in `format`.
    public static func string(for color: ScreenColor, format: ScreenColorFormat) -> String {
        switch format {
        case .hex:
            return "#\(hexComponent(color.red))\(hexComponent(color.green))\(hexComponent(color.blue))"
        case .hexWithAlpha:
            return "#\(hexComponent(color.red))\(hexComponent(color.green))"
                + "\(hexComponent(color.blue))\(hexComponent(color.alpha))"
        case .rgb:
            return "rgb(\(byte(color.red)), \(byte(color.green)), \(byte(color.blue)))"
        case .rgba:
            return "rgba(\(byte(color.red)), \(byte(color.green)), \(byte(color.blue)), \(decimal(color.alpha)))"
        case .hsl:
            let hsl = hslComponents(for: color)
            return "hsl(\(Int(hsl.hue.rounded())), \(Int(hsl.saturation.rounded()))%, \(Int(hsl.lightness.rounded()))%)"
        case .swiftUI:
            return "Color(red: \(decimal(color.red)), green: \(decimal(color.green)), blue: \(decimal(color.blue)))"
        }
    }

    private static func byte(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }

    private static func hexComponent(_ value: Double) -> String {
        String(format: "%02X", byte(value))
    }

    private static func decimal(_ value: Double) -> String {
        // Three places keeps the text short while round-tripping an 8-bit channel exactly enough
        // to reproduce the same byte.
        String(format: "%.3f", value)
    }

    static func hslComponents(
        for color: ScreenColor
    ) -> (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2

        guard delta > 0 else { return (0, 0, lightness * 100) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maximum == color.red {
            hue = 60 * (((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maximum == color.green {
            hue = 60 * (((color.blue - color.red) / delta) + 2)
        } else {
            hue = 60 * (((color.red - color.green) / delta) + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, min(1, max(0, saturation)) * 100, lightness * 100)
    }
}
