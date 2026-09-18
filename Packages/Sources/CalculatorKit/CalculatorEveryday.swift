import Foundation

enum CalculatorEveryday {
    private static let n = CalculatorExpandedSupport.numberPattern

    static func evaluate(_ text: String, original: String) -> CalculatorUtilities.Result? {
        if let v = values(
            #"^scale (\#(n)) cups from (\#(n)) servings to (\#(n)) servings$"#,
            text
        ), v[1] > 0 {
            return result(v[0] * v[2] / v[1], original, suffix: " cups")
        }
        if let v = values(
            #"^unit price for (\#(n)) dollars and (\#(n)) items$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1], original, suffix: " per item")
        }
        if let v = values(
            #"^better unit price between (\#(n)) for (\#(n)) and (\#(n)) for (\#(n))$"#,
            text
        ), v[0] > 0, v[1] >= 0, v[2] > 0, v[3] >= 0 {
            let firstUnitPrice = v[1] / v[0]
            let secondUnitPrice = v[3] / v[2]
            let selected = firstUnitPrice <= secondUnitPrice
                ? "\(CalculatorExpandedSupport.plain(v[0])) for \(CalculatorExpandedSupport.plain(v[1]))"
                : "\(CalculatorExpandedSupport.plain(v[2])) for \(CalculatorExpandedSupport.plain(v[3]))"
            return CalculatorExpandedSupport.text(
                selected,
                expression: original,
                notes: ["Compared price per unit; lower is better."]
            )
        }
        if let v = values(
            #"^fuel cost for (\#(n)) miles at (\#(n)) mpg and (\#(n)) per gallon$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1] * v[2], original)
        }
        if let v = values(
            #"^fuel cost per mile at (\#(n)) per gallon and (\#(n)) mpg$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1], original, suffix: " per mile")
        }
        if let v = values(
            #"^paint needed for (\#(n)) square feet at (\#(n)) square feet per gallon$"#,
            text
        ), v[1] > 0, v[0] >= 0 {
            return result(v[0] / v[1], original, suffix: " gal")
        }
        if let v = values(
            #"^paint cans needed for (\#(n)) square feet at (\#(n)) square feet per can$"#,
            text
        ), v[1] > 0, v[0] >= 0 {
            return result(ceil(v[0] / v[1]), original, suffix: " cans")
        }
        if let v = values(
            #"^tiles needed for (\#(n)) square feet with (\#(n))% waste and (\#(n)) square feet per tile$"#,
            text
        ), v[0] >= 0, v[1] >= 0, v[2] > 0 {
            return result(ceil(v[0] * (1 + v[1] / 100) / v[2]), original, suffix: " tiles")
        }
        if let v = values(
            #"^battery runtime for (\#(n)) wh at (\#(n)) w$"#,
            text
        ), v[0] >= 0, v[1] > 0 {
            return result(v[0] / v[1], original, suffix: " h")
        }
        if let v = values(
            #"^battery charge time for (\#(n)) wh at (\#(n)) w with (\#(n))% efficiency$"#,
            text
        ), v[0] >= 0, v[1] > 0, v[2] > 0, v[2] <= 100 {
            return result(
                v[0] / (v[1] * v[2] / 100),
                original,
                suffix: " h",
                notes: ["Assumes constant charging power and the stated end-to-end efficiency."]
            )
        }
        if let v = values(
            #"^grade for (\#(n)) points out of (\#(n))$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1] * 100, original, suffix: "%")
        }
        if let v = values(
            #"^weighted grade current (\#(n)) worth (\#(n))% final (\#(n)) worth (\#(n))%$"#,
            text
        ), v[1] >= 0, v[3] >= 0, v[1] + v[3] > 0 {
            return result(
                (v[0] * v[1] + v[2] * v[3]) / (v[1] + v[3]),
                original,
                suffix: "%"
            )
        }
        if let v = values(
            #"^needed final score for target (\#(n)) current (\#(n)) worth (\#(n))% final worth (\#(n))%$"#,
            text
        ), v[3] > 0 {
            return result((v[0] * 100 - v[1] * v[2]) / v[3], original, suffix: "%")
        }
        if let v = values(
            #"^average speed for (\#(n)) miles at (\#(n)) mph and (\#(n)) miles at (\#(n)) mph$"#,
            text
        ), v[1] > 0, v[3] > 0, v[0] + v[2] >= 0 {
            let totalTime = v[0] / v[1] + v[2] / v[3]
            guard totalTime > 0 else { return nil }
            return result((v[0] + v[2]) / totalTime, original, suffix: " mph")
        }
        if let v = values(
            #"^ppi for (\#(n)) by (\#(n)) at (\#(n)) inches$"#,
            text
        ), v[2] > 0 {
            return result(hypot(v[0], v[1]) / v[2], original, suffix: " ppi")
        }
        if let v = values(
            #"^map distance for (\#(n)) cm at scale 1:(\#(n)) in km$"#,
            text
        ), v[0] >= 0, v[1] > 0 {
            return result(v[0] * v[1] / 100_000, original, suffix: " km")
        }
        if let v = values(
            #"^probability percent from odds (\#(n)) to (\#(n))$"#,
            text
        ), v[0] >= 0, v[1] >= 0, v[0] + v[1] > 0 {
            return result(v[0] / (v[0] + v[1]) * 100, original, suffix: "%")
        }
        if let v = values(
            #"^odds from probability (\#(n))%$"#,
            text
        ), v[0] > 0, v[0] < 100 {
            let ratio = v[0] / (100 - v[0])
            let scaled = bestIntegerRatio(ratio)
            return CalculatorExpandedSupport.text(
                "\(scaled.numerator):\(scaled.denominator)",
                expression: original
            )
        }
        if let v = values(
            #"^split (\#(n)) with (\#(n))% tax and (\#(n))% tip among (\#(n)) people$"#,
            text
        ), v[3] > 0 {
            return result(v[0] * (1 + v[1] / 100 + v[2] / 100) / v[3], original)
        }
        return nil
    }

    private static func bestIntegerRatio(_ value: Double) -> (numerator: Int, denominator: Int) {
        for denominator in 1...10_000 {
            let numerator = Int((value * Double(denominator)).rounded())
            if abs(Double(numerator) / Double(denominator) - value) < 1e-10 {
                let divisor = CalculatorExpandedSupport.greatestCommonDivisor(numerator, denominator)
                return (numerator / divisor, denominator / divisor)
            }
        }
        return (Int((value * 1_000).rounded()), 1_000)
    }

    private static func values(_ pattern: String, _ text: String) -> [Double]? {
        guard let groups = CalculatorExpandedSupport.captures(pattern, in: text) else {
            return nil
        }
        let parsed = groups.map(Double.init)
        return parsed.allSatisfy({ $0 != nil }) ? parsed.compactMap { $0 } : nil
    }

    private static func result(
        _ value: Double,
        _ original: String,
        suffix: String = "",
        notes: [String] = []
    ) -> CalculatorUtilities.Result? {
        CalculatorExpandedSupport.numeric(
            value,
            expression: original,
            kind: .business,
            suffix: suffix,
            notes: notes
        )
    }
}
