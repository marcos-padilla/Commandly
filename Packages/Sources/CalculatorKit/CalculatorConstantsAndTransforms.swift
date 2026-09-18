import Foundation

enum CalculatorConstantsAndTransforms {
    private static let n = CalculatorExpandedSupport.numberPattern

    static func evaluate(_ text: String, original: String) -> CalculatorUtilities.Result? {
        constant(text, original: original) ?? transform(text, original: original)
    }

    private static func constant(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        let constants: [String: (Double, String, String)] = [
            "speed of light constant": (299_792_458, " m/s", "Exact SI value."),
            "gravitational constant": (6.67430e-11, " m³·kg⁻¹·s⁻²", "CODATA value."),
            "planck constant": (6.626_070_15e-34, " J·Hz⁻¹", "Exact SI value."),
            "reduced planck constant": (1.054_571_817e-34, " J·s", "Derived from h ÷ 2π."),
            "avogadro constant": (6.022_140_76e23, " mol⁻¹", "Exact SI value."),
            "boltzmann constant": (1.380_649e-23, " J/K", "Exact SI value."),
            "elementary charge constant": (1.602_176_634e-19, " C", "Exact SI value."),
            "standard gravity constant": (9.80665, " m/s²", "Conventional standard value."),
            "molar gas constant": (8.314_462_618_153_24, " J·mol⁻¹·K⁻¹", "Derived SI value."),
            "vacuum permittivity": (8.854_187_818_8e-12, " F/m", "CODATA value."),
            "vacuum permeability": (1.256_637_061_27e-6, " N/A²", "CODATA value."),
            "electron mass constant": (9.109_383_713_9e-31, " kg", "CODATA value."),
            "proton mass constant": (1.672_621_925_95e-27, " kg", "CODATA value."),
            "astronomical unit in meters": (149_597_870_700, " m", "Exact IAU value."),
            "light year in meters": (9_460_730_472_580_800, " m", "Uses a Julian year."),
            "parsec in meters": (3.085_677_581_491_367e16, " m", "Derived astronomical value."),
            "mean earth radius": (6_371_008.8, " m", "IUGG mean radius."),
            "earth mass constant": (5.9722e24, " kg", "Nominal rounded value."),
        ]
        let aliases = [
            "speed of light": "speed of light constant",
            "newtonian constant of gravitation": "gravitational constant",
            "newton's gravitational constant": "gravitational constant",
            "planck's constant": "planck constant",
            "hbar constant": "reduced planck constant",
            "avogadro's number": "avogadro constant",
            "boltzmann's constant": "boltzmann constant",
            "elementary charge": "elementary charge constant",
            "standard gravitational acceleration": "standard gravity constant",
            "universal gas constant": "molar gas constant",
            "earth mean radius": "mean earth radius",
            "mass of earth": "earth mass constant",
        ]
        guard let item = constants[aliases[text] ?? text] else { return nil }
        return CalculatorExpandedSupport.numeric(
            item.0,
            expression: original,
            kind: .scientific,
            suffix: item.1,
            notes: [item.2]
        )
    }

    private static func transform(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n))/(\#(n)) as decimal$"#,
            in: text
        ),
        let numerator = Double(groups[0]),
        let denominator = Double(groups[1]),
        denominator != 0 {
            return numeric(numerator / denominator, original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) degrees (\#(n)) minutes(?: (\#(n)) seconds)? as decimal degrees$"#,
            in: text
        ),
        let degrees = Double(groups[0]),
        let minutes = Double(groups[1]),
        let seconds = Double(groups[2].isEmpty ? "0" : groups[2]),
        abs(minutes) < 60, abs(seconds) < 60 {
            let sign = degrees < 0 ? -1.0 : 1.0
            return numeric(sign * (abs(degrees) + abs(minutes) / 60 + abs(seconds) / 3_600), original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^height for (\d+):(\d+) aspect ratio width (\#(n))$"#,
            in: text
        ),
        let widthRatio = Double(groups[0]),
        let heightRatio = Double(groups[1]),
        let width = Double(groups[2]),
        widthRatio > 0, heightRatio > 0, width >= 0 {
            return numeric(width * heightRatio / widthRatio, original, suffix: " px")
        }
        if text == "pixels in 4k uhd" {
            return numeric(3_840 * 2_160, original, suffix: " pixels")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^megapixels for (\d+) by (\d+)$"#,
            in: text
        ),
        let width = Double(groups[0]),
        let height = Double(groups[1]) {
            return numeric(width * height / 1_000_000, original, suffix: " MP")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^uncompressed rgb size (\d+) by (\d+) at (\d+) bits per channel$"#,
            in: text
        ),
        let width = Double(groups[0]),
        let height = Double(groups[1]),
        let bits = Double(groups[2]),
        bits > 0 {
            return numeric(
                width * height * 3 * bits / 8,
                original,
                suffix: " bytes",
                notes: ["Assumes three uncompressed RGB channels and no row padding."]
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^audio size at (\#(n)) kbps for (\#(n)) minutes$"#,
            in: text
        ),
        let rate = Double(groups[0]),
        let minutes = Double(groups[1]),
        rate >= 0, minutes >= 0 {
            return numeric(
                rate * 1_000 * minutes * 60 / 8 / 1_000_000,
                original,
                suffix: " MB",
                notes: ["Uses decimal megabytes and excludes container overhead."]
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^video bitrate for (\#(n)) gb over (\#(n)) minutes$"#,
            in: text
        ),
        let gigabytes = Double(groups[0]),
        let minutes = Double(groups[1]),
        minutes > 0 {
            return numeric(
                gigabytes * 8_000 / (minutes * 60),
                original,
                suffix: " Mbps",
                notes: ["Uses decimal gigabytes and excludes container overhead."]
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) basis points as percent$"#,
            in: text
        ),
        let basisPoints = Double(groups[0]) {
            return numeric(basisPoints / 100, original, suffix: "%")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) percent as basis points$"#,
            in: text
        ),
        let percent = Double(groups[0]) {
            return numeric(percent * 100, original, suffix: " bps")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\d+) to roman numerals$"#,
            in: text
        ),
        let value = Int(groups[0]),
        (1...3_999).contains(value) {
            return CalculatorExpandedSupport.text(roman(value), expression: original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^roman numeral ([ivxlcdm]+) to decimal$"#,
            in: text
        ),
        let value = romanValue(groups[0]),
        roman(value).lowercased() == groups[0] {
            return CalculatorExpandedSupport.text(String(value), expression: original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) as (fraction|mixed fraction)$"#,
            in: text
        ),
        let fraction = decimalFraction(groups[0], mixed: groups[1] == "mixed fraction") {
            return CalculatorExpandedSupport.text(fraction, expression: original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) in (scientific|engineering) notation$"#,
            in: text
        ),
        let value = Double(groups[0]) {
            return CalculatorExpandedSupport.text(
                notation(value, engineering: groups[1] == "engineering"),
                expression: original
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^(\#(n)) degrees as degrees minutes seconds$"#,
            in: text
        ),
        let value = Double(groups[0]) {
            return CalculatorExpandedSupport.text(dms(value), expression: original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^aspect ratio of (\d+) by (\d+)$"#,
            in: text
        ),
        let width = Int(groups[0]),
        let height = Int(groups[1]),
        width > 0, height > 0 {
            let divisor = CalculatorExpandedSupport.greatestCommonDivisor(width, height)
            return CalculatorExpandedSupport.text(
                "\(width / divisor):\(height / divisor)",
                expression: original
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^luhn check ([\d -]+)$"#,
            in: text
        ) {
            let digits = groups[0].compactMap(\.wholeNumberValue)
            guard digits.count >= 2 else { return nil }
            let checksum = digits.reversed().enumerated().reduce(0) { partial, item in
                var digit = item.element
                if item.offset % 2 == 1 {
                    digit *= 2
                    if digit > 9 { digit -= 9 }
                }
                return partial + digit
            }
            return CalculatorExpandedSupport.text(
                String(checksum % 10 == 0),
                expression: original
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^([0-7]{3}) as unix permissions$"#,
            in: text
        ) {
            let permissions = groups[0].flatMap { digit -> [Character] in
                guard let value = digit.wholeNumberValue else { return [] }
                return [
                    value & 4 == 0 ? "-" : "r",
                    value & 2 == 0 ? "-" : "w",
                    value & 1 == 0 ? "-" : "x",
                ]
            }
            return CalculatorExpandedSupport.text(String(permissions), expression: original)
        }
        return nil
    }

    private static func numeric(
        _ value: Double,
        _ original: String,
        suffix: String = "",
        notes: [String] = []
    ) -> CalculatorUtilities.Result? {
        CalculatorExpandedSupport.numeric(
            value,
            expression: original,
            kind: .developerUtility,
            suffix: suffix,
            notes: notes
        )
    }

    private static func roman(_ value: Int) -> String {
        let symbols = [
            (1_000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var remainder = value
        var output = ""
        for (amount, symbol) in symbols {
            while remainder >= amount {
                output += symbol
                remainder -= amount
            }
        }
        return output
    }

    private static func romanValue(_ input: String) -> Int? {
        let values: [Character: Int] = [
            "I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1_000,
        ]
        let characters = Array(input.uppercased())
        guard !characters.isEmpty, characters.allSatisfy({ values[$0] != nil }) else {
            return nil
        }
        return characters.indices.reduce(0) { total, index in
            guard let value = values[characters[index]] else { return total }
            let next = index + 1 < characters.count ? values[characters[index + 1]] ?? 0 : 0
            return total + (value < next ? -value : value)
        }
    }

    private static func decimalFraction(_ raw: String, mixed: Bool) -> String? {
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              let decimalPoint = raw.firstIndex(of: ".")
        else {
            return mixed ? "\(raw) 0/1" : "\(raw)/1"
        }
        let digits = raw.distance(from: raw.index(after: decimalPoint), to: raw.endIndex)
        guard digits <= 12 else { return nil }
        let denominator = Int(pow(10.0, Double(digits)))
        let scaled = NSDecimalNumber(decimal: abs(value) * Decimal(denominator)).intValue
        let divisor = CalculatorExpandedSupport.greatestCommonDivisor(scaled, denominator)
        let numerator = scaled / divisor
        let reducedDenominator = denominator / divisor
        let sign = value < 0 ? "-" : ""
        if mixed {
            let whole = numerator / reducedDenominator
            let remainder = numerator % reducedDenominator
            if remainder == 0 { return sign + String(whole) }
            return "\(sign)\(whole) \(remainder)/\(reducedDenominator)"
        }
        return "\(sign)\(numerator)/\(reducedDenominator)"
    }

    private static func notation(_ value: Double, engineering: Bool) -> String {
        guard value != 0 else { return "0 × 10^0" }
        let rawExponent = Int(floor(log10(abs(value))))
        let exponent = engineering ? Int(floor(Double(rawExponent) / 3)) * 3 : rawExponent
        let mantissa = value / pow(10, Double(exponent))
        return "\(CalculatorExpandedSupport.plain(mantissa)) × 10^\(exponent)"
    }

    private static func dms(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let absolute = abs(value)
        let degrees = Int(floor(absolute))
        let rawMinutes = (absolute - Double(degrees)) * 60
        let minutes = Int(floor(rawMinutes))
        let seconds = ((rawMinutes - Double(minutes)) * 60).rounded(toPlaces: 9)
        return "\(sign)\(degrees)° \(minutes)′ \(CalculatorExpandedSupport.plain(seconds))″"
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
