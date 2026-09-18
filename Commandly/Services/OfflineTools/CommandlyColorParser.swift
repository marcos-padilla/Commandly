import Foundation

/// Bounded standalone CSS literal parser shared by the editor and root search. This deliberately
/// does not evaluate CSS variables, calc(), relative colors, escapes, comments, or interpolation.
nonisolated enum CommandlyColorParser {
    static let maximumInputBytes = 256

    static func parse(_ input: String) -> CommandlyColor? {
        let prefix = Array(input.utf8.prefix(maximumInputBytes + 1))
        guard !prefix.isEmpty, prefix.count <= maximumInputBytes, prefix.allSatisfy({ $0 < 128 }) else { return nil }
        let bytes = Array(prefix.drop(while: whitespace).reversed().drop(while: whitespace).reversed())
        guard !bytes.isEmpty else { return nil }
        if bytes.first == 35 { return hex(Array(bytes.dropFirst())) }
        let lower = bytes.map { (65 ... 90).contains($0) ? $0 + 32 : $0 }
        guard lower.last == 41, let open = lower.firstIndex(of: 40) else { return nil }
        let name = String(decoding: lower[..<open], as: UTF8.self)
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name) else { return nil }
        var reader = Reader(bytes: Array(lower[(open + 1)..<(lower.count - 1)]))
        guard let values = reader.components() else { return nil }
        let alpha = values.alpha.flatMap { scalar($0, scale: 1, percentScale: 100, allowsMissing: !values.legacy) } ?? (values.alpha == nil ? 1 : .nan)
        if name == "rgb" || name == "rgba" {
            if values.legacy {
                guard values.channels.allSatisfy({ $0.unit == .number }) || values.channels.allSatisfy({ $0.unit == .percent }) else { return nil }
            }
            guard let red = scalar(values.channels[0], scale: 255, percentScale: 100, allowsMissing: !values.legacy),
                  let green = scalar(values.channels[1], scale: 255, percentScale: 100, allowsMissing: !values.legacy),
                  let blue = scalar(values.channels[2], scale: 255, percentScale: 100, allowsMissing: !values.legacy) else { return nil }
            return CommandlyColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        if values.legacy, values.channels[1].unit != .percent || values.channels[2].unit != .percent { return nil }
        guard let hue = hue(values.channels[0], allowsMissing: !values.legacy),
              let saturation = scalar(values.channels[1], scale: 100, percentScale: 100, allowsMissing: !values.legacy),
              let lightness = scalar(values.channels[2], scale: 100, percentScale: 100, allowsMissing: !values.legacy) else { return nil }
        // CSS HSL resolves to sRGB. Negative saturation clamps to zero; out-of-gamut resolved
        // channels clip at this tool's bounded sRGB value boundary, without color-profile I/O.
        let amplitude = max(0, saturation) * min(lightness, 1 - lightness)
        guard amplitude.isFinite else { return nil }
        func channel(_ offset: Double) -> Double {
            let k = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            return lightness - amplitude * max(-1, min(k - 3, 9 - k, 1))
        }
        return CommandlyColor(red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
    }

    private static func hex(_ digits: [UInt8]) -> CommandlyColor? {
        guard [3, 4, 6, 8].contains(digits.count) else { return nil }
        var values: [Double] = []
        for byte in digits {
            let value: UInt8
            switch byte {
            case 48 ... 57: value = byte - 48
            case 65 ... 70: value = byte - 55
            case 97 ... 102: value = byte - 87
            default: return nil
            }
            values.append(Double(value))
        }
        let channels: [Double]
        if digits.count <= 4 { channels = values.map { $0 / 15 } }
        else { channels = stride(from: 0, to: values.count, by: 2).map { (values[$0] * 16 + values[$0 + 1]) / 255 } }
        return CommandlyColor(red: channels[0], green: channels[1], blue: channels[2], alpha: channels.count == 4 ? channels[3] : 1)
    }

    private static func scalar(_ value: Component, scale: Double, percentScale: Double, allowsMissing: Bool) -> Double? {
        switch value.unit {
        case .number: value.value / scale
        case .percent: value.value / percentScale
        case .missing: allowsMissing ? 0 : nil
        default: nil
        }
    }

    private static func hue(_ value: Component, allowsMissing: Bool) -> Double? {
        let degrees: Double
        switch value.unit {
        case .number, .deg: degrees = value.value.truncatingRemainder(dividingBy: 360)
        case .grad: degrees = value.value.truncatingRemainder(dividingBy: 400) * 0.9
        case .rad: degrees = value.value.truncatingRemainder(dividingBy: 2 * .pi) * 180 / .pi
        case .turn: degrees = value.value.truncatingRemainder(dividingBy: 1) * 360
        case .missing: return allowsMissing ? 0 : nil
        case .percent: return nil
        }
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func whitespace(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }
    private enum Unit: Equatable { case number, percent, deg, grad, rad, turn, missing }
    private struct Component: Equatable { let value: Double; let unit: Unit }
    private struct Components { let channels: [Component]; let alpha: Component?; let legacy: Bool }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func skipWhitespace() -> Bool {
            let start = index
            while let byte = current, whitespace(byte) { index += 1 }
            return index > start
        }
        mutating func components() -> Components? {
            _ = skipWhitespace()
            guard let first = component() else { return nil }
            var separated = skipWhitespace()
            let legacy = current == 44
            var channels = [first]
            for _ in 0 ..< 2 {
                if legacy { guard current == 44 else { return nil }; index += 1; _ = skipWhitespace() }
                else { guard separated else { return nil } }
                guard let next = component() else { return nil }
                channels.append(next)
                separated = skipWhitespace()
            }
            var alpha: Component?
            if current == (legacy ? 44 : 47) {
                index += 1; _ = skipWhitespace()
                guard let next = component() else { return nil }
                alpha = next; _ = skipWhitespace()
            }
            guard index == bytes.count else { return nil }
            return Components(channels: channels, alpha: alpha, legacy: legacy)
        }
        mutating func component() -> Component? {
            if bytes[index...].starts(with: [110, 111, 110, 101]) { index += 4; return Component(value: 0, unit: .missing) }
            let start = index
            if current == 43 || current == 45 { index += 1 }
            let integerStart = index
            while let byte = current, (48 ... 57).contains(byte) { index += 1 }
            var hasDigits = index > integerStart
            if current == 46 {
                index += 1
                let fractionStart = index
                while let byte = current, (48 ... 57).contains(byte) { index += 1 }
                guard index > fractionStart else { return nil }
                hasDigits = true
            }
            guard hasDigits else { return nil }
            if current == 101 {
                index += 1
                if current == 43 || current == 45 { index += 1 }
                let exponentStart = index
                while let byte = current, (48 ... 57).contains(byte) { index += 1 }
                guard index > exponentStart else { return nil }
            }
            guard let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)), number.isFinite else { return nil }
            let unitStart = index
            if current == 37 { index += 1 }
            else { while let byte = current, (97 ... 122).contains(byte) { index += 1 } }
            let unit: Unit
            switch String(decoding: bytes[unitStart..<index], as: UTF8.self) {
            case "": unit = .number
            case "%": unit = .percent
            case "deg": unit = .deg
            case "grad": unit = .grad
            case "rad": unit = .rad
            case "turn": unit = .turn
            default: return nil
            }
            return Component(value: number, unit: unit)
        }
    }
}
