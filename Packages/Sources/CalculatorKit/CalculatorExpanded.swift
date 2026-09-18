import Foundation

/// Routes structured, deterministic calculations that are broader than the
/// expression grammar but still have a single unambiguous interpretation.
enum CalculatorExpanded {
    static func evaluate(_ original: String) -> CalculatorUtilities.Result? {
        let text = canonicalQuery(original)
        return CalculatorStatisticsAndSequences.evaluate(text, original: original)
            ?? CalculatorGeometryAndPhysics.evaluate(text, original: original)
            ?? CalculatorConstantsAndTransforms.evaluate(text, original: original)
            ?? CalculatorEveryday.evaluate(text, original: original)
    }

    static func looksLikeQuery(_ input: String) -> Bool {
        let input = canonicalQuery(input)
        let prefixes = [
            "weighted average", "weighted sum", "geometric mean", "harmonic mean",
            "root mean square", "sample variance", "sample standard deviation", "z score",
            "coefficient of variation", "standard error", "margin of error", "linear interpolation",
            "fibonacci", "sum of first", "sum integers",
            "arithmetic sequence", "arithmetic series", "geometric sequence", "geometric series",
            "triangular number", "pentagonal number", "hexagonal number", "sum of squares",
            "sum of cubes", "greatest power of", "digital root", "digit sum", "number of digits",
            "area of a trapezoid", "area of a parallelogram", "area of a rhombus",
            "area of an ellipse", "circumference of an ellipse", "interior angle",
            "sum interior angles", "exterior angle", "area of a regular", "volume of a sphere",
            "surface area of a cylinder", "surface area of a cone", "volume of a pyramid",
            "volume of a triangular prism", "volume of a torus", "distance between points",
            "slope between points", "midpoint between", "missing angle of triangle",
            "area of triangle sides", "arc length", "sector area",
            "speed for distance", "acceleration from", "force for mass", "momentum for mass",
            "kinetic energy", "potential energy", "power for energy", "pressure for force",
            "density for mass", "mass for density", "work for force", "impulse for force",
            "frequency for period", "period for frequency", "wavelength at speed", "wave speed",
            "current for voltage", "resistance for voltage", "electrical power", "electrical energy",
            "charge for current", "mass energy", "photon energy", "free fall distance",
            "ideal gas pressure", "centripetal force", "centripetal acceleration", "spring energy",
            "hooke force", "gravitational force", "roman numeral",
            "pixels in 4k", "megapixels for", "uncompressed rgb size", "audio size",
            "video bitrate", "aspect ratio of", "luhn check",
            "unit price", "better unit price", "fuel cost", "paint needed",
            "paint cans", "tiles needed", "battery runtime", "battery charge time",
            "grade for", "weighted grade", "needed final score", "average speed",
            "ppi for", "map distance", "probability percent", "odds from probability",
        ]
        if prefixes.contains(where: input.hasPrefix) { return true }
        let constants: Set<String> = [
            "speed of light", "speed of light constant", "gravitational constant",
            "newtonian constant of gravitation", "newton's gravitational constant",
            "planck constant", "planck's constant", "reduced planck constant", "hbar constant",
            "avogadro constant", "avogadro's number", "boltzmann constant",
            "boltzmann's constant", "elementary charge", "elementary charge constant",
            "standard gravity constant", "standard gravitational acceleration",
            "molar gas constant", "universal gas constant", "vacuum permittivity",
            "vacuum permeability", "electron mass constant", "proton mass constant",
            "astronomical unit in meters", "light year in meters", "parsec in meters",
            "mean earth radius", "earth mean radius", "earth mass constant", "mass of earth",
        ]
        if constants.contains(input) { return true }

        let specificPatterns = [
            #"^normalize [-+.\de]+ from range [-+.\de]+ to [-+.\de]+$"#,
            #"^map [-+.\de]+ from range [-+.\de]+ to [-+.\de]+ into [-+.\de]+ to [-+.\de]+$"#,
            #"^height for \d+:\d+ aspect ratio width [-+.\de]+$"#,
            #"^scale [-+.\de]+ cups from [-+.\de]+ servings to [-+.\de]+ servings$"#,
            #"^split [-+.\de]+ with [-+.\de]+% tax and [-+.\de]+% tip among [-+.\de]+ people$"#,
        ]
        if specificPatterns.contains(where: {
            input.range(of: $0, options: .regularExpression) != nil
        }) {
            return true
        }

        let containedPhrases = [
            "fibonacci number", " a power of 2", " degrees as slope percent",
            " slope percent as degrees", " to roman numerals", " as roman numerals",
            " as decimal", " as fraction", " as mixed fraction",
            " in scientific notation", " in engineering notation",
            " degrees as degrees minutes seconds", " degrees 30 minutes as decimal degrees",
            " as decimal degrees", " basis points as percent", " percent as basis points",
            " as unix permissions",
        ]
        return containedPhrases.contains(where: input.contains)
    }

    private static func canonicalQuery(_ input: String) -> String {
        var text = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prefixes = [
            "what is", "what's", "calculate", "compute", "find",
            "give me", "show me", "value of",
        ]
        for prefix in prefixes where text.hasPrefix(prefix + " ") {
            text.removeFirst(prefix.count)
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("the ") {
                text.removeFirst(4)
            }
            break
        }
        return text
    }
}

enum CalculatorExpandedSupport {
    static let numberPattern = #"[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[-+]?\d+)?"#

    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text)
            else {
                return ""
            }
            return String(text[range])
        }
    }

    static func double(_ value: String) -> Double? {
        Double(value)
    }

    static func integer(_ value: String) -> Int? {
        Int(value)
    }

    static func numberList(_ input: String) -> [Double]? {
        let canonical = input.replacingOccurrences(
            of: #"\s*(?:;|\band\b)\s*"#,
            with: ",",
            options: .regularExpression
        )
        let values = canonical.split(separator: ",").map {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    static func numeric(
        _ value: Double,
        expression: String,
        kind: CalculatorResultKind = .scientific,
        suffix: String = "",
        notes: [String] = []
    ) -> CalculatorUtilities.Result? {
        guard value.isFinite else { return nil }
        let decimal = Decimal(value)
        return CalculatorUtilities.Result(
            kind: kind,
            primaryValue: .decimal(decimal),
            formattedPrimaryValue: NSDecimalNumber(decimal: decimal).stringValue + suffix,
            metadata: .init(notes: notes),
            displayExpression: expression
        )
    }

    static func numeric(
        _ value: Int,
        expression: String,
        kind: CalculatorResultKind = .scientific,
        suffix: String = "",
        notes: [String] = []
    ) -> CalculatorUtilities.Result? {
        numeric(
            Double(value),
            expression: expression,
            kind: kind,
            suffix: suffix,
            notes: notes
        )
    }

    static func text(
        _ value: String,
        expression: String,
        notes: [String] = []
    ) -> CalculatorUtilities.Result {
        CalculatorUtilities.Result(
            kind: .developerUtility,
            primaryValue: .text(value),
            formattedPrimaryValue: value,
            metadata: .init(notes: notes),
            displayExpression: expression
        )
    }

    static func plain(_ value: Double, maximumFractionDigits: Int = 12) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value, abs(value) <= Double(Int.max) {
            return String(Int(value))
        }
        return String(format: "%.*g", maximumFractionDigits, value)
    }

    static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = abs(first)
        var b = abs(second)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}
