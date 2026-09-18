import Foundation

enum CalculatorStatisticsAndSequences {
    private static let n = CalculatorExpandedSupport.numberPattern

    static func evaluate(_ text: String, original: String) -> CalculatorUtilities.Result? {
        statistics(text, original: original) ?? sequences(text, original: original)
    }

    private static func statistics(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        if let groups = CalculatorExpandedSupport.captures(
            #"^weighted (average|sum) of (.+)$"#,
            in: text
        ),
        let pairs = weightedPairs(groups[1]) {
            let weightedSum = pairs.reduce(0) { $0 + $1.value * $1.weight }
            if groups[0] == "sum" {
                return CalculatorExpandedSupport.numeric(weightedSum, expression: original)
            }
            let totalWeight = pairs.reduce(0) { $0 + $1.weight }
            guard totalWeight != 0 else { return nil }
            return CalculatorExpandedSupport.numeric(
                weightedSum / totalWeight,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^geometric mean of (.+)$"#,
            in: text
        ),
        let values = CalculatorExpandedSupport.numberList(groups[0]),
        values.allSatisfy({ $0 > 0 }) {
            let mean = exp(values.reduce(0) { $0 + log($1) } / Double(values.count))
            return CalculatorExpandedSupport.numeric(mean, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^harmonic mean of (.+)$"#,
            in: text
        ),
        let values = CalculatorExpandedSupport.numberList(groups[0]),
        values.allSatisfy({ $0 != 0 }) {
            let denominator = values.reduce(0) { $0 + 1 / $1 }
            guard denominator != 0 else { return nil }
            return CalculatorExpandedSupport.numeric(
                Double(values.count) / denominator,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^root mean square of (.+)$"#,
            in: text
        ),
        let values = CalculatorExpandedSupport.numberList(groups[0]) {
            let meanSquare = values.reduce(0) { $0 + $1 * $1 } / Double(values.count)
            return CalculatorExpandedSupport.numeric(sqrt(meanSquare), expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^sample (variance|standard deviation) of (.+)$"#,
            in: text
        ),
        let values = CalculatorExpandedSupport.numberList(groups[1]),
        values.count > 1 {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + pow($1 - mean, 2) }
                / Double(values.count - 1)
            let value = groups[0] == "variance" ? variance : sqrt(variance)
            return CalculatorExpandedSupport.numeric(value, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^z score of (\#(n)) with mean (\#(n)) and standard deviation (\#(n))$"#,
            in: text
        ),
        let value = Double(groups[0]),
        let mean = Double(groups[1]),
        let deviation = Double(groups[2]),
        deviation != 0 {
            return CalculatorExpandedSupport.numeric(
                (value - mean) / deviation,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^coefficient of variation for mean (\#(n)) and standard deviation (\#(n))$"#,
            in: text
        ),
        let mean = Double(groups[0]),
        let deviation = Double(groups[1]),
        mean != 0 {
            return CalculatorExpandedSupport.numeric(
                abs(deviation / mean) * 100,
                expression: original,
                suffix: "%"
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^standard error for standard deviation (\#(n)) and sample size (\d+)$"#,
            in: text
        ),
        let deviation = Double(groups[0]),
        let count = Int(groups[1]),
        count > 0 {
            return CalculatorExpandedSupport.numeric(
                deviation / sqrt(Double(count)),
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^margin of error for standard deviation (\#(n)) sample size (\d+) at 95%$"#,
            in: text
        ),
        let deviation = Double(groups[0]),
        let count = Int(groups[1]),
        count > 0 {
            return CalculatorExpandedSupport.numeric(
                1.96 * deviation / sqrt(Double(count)),
                expression: original,
                notes: ["Uses the normal approximation at 95% confidence."]
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^linear interpolation from (\#(n)) to (\#(n)) at (\#(n))%$"#,
            in: text
        ),
        let start = Double(groups[0]),
        let end = Double(groups[1]),
        let percent = Double(groups[2]) {
            return CalculatorExpandedSupport.numeric(
                start + (end - start) * percent / 100,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^normalize (\#(n)) from range (\#(n)) to (\#(n))$"#,
            in: text
        ),
        let value = Double(groups[0]),
        let minimum = Double(groups[1]),
        let maximum = Double(groups[2]),
        maximum != minimum {
            return CalculatorExpandedSupport.numeric(
                (value - minimum) / (maximum - minimum),
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^map (\#(n)) from range (\#(n)) to (\#(n)) into (\#(n)) to (\#(n))$"#,
            in: text
        ),
        let value = Double(groups[0]),
        let inputMinimum = Double(groups[1]),
        let inputMaximum = Double(groups[2]),
        let outputMinimum = Double(groups[3]),
        let outputMaximum = Double(groups[4]),
        inputMaximum != inputMinimum {
            let progress = (value - inputMinimum) / (inputMaximum - inputMinimum)
            return CalculatorExpandedSupport.numeric(
                outputMinimum + progress * (outputMaximum - outputMinimum),
                expression: original
            )
        }
        return nil
    }

    private static func sequences(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        if let groups = CalculatorExpandedSupport.captures(
            #"^(?:fibonacci number (\d+)|(\d+)(?:st|nd|rd|th) fibonacci number)$"#,
            in: text
        ),
        let index = Int(groups[0].isEmpty ? groups[1] : groups[0]),
        index <= 92 {
            return CalculatorExpandedSupport.numeric(fibonacci(index), expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^sum of first (\d+) integers$"#,
            in: text
        ),
        let count = Int(groups[0]),
        (0...1_000_000_000).contains(count) {
            return CalculatorExpandedSupport.numeric(
                Double(count) * (Double(count) + 1) / 2,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^sum integers from (-?\d+) to (-?\d+)$"#,
            in: text
        ),
        let first = Int(groups[0]),
        let last = Int(groups[1]),
        abs(Double(first)) <= 1_000_000_000,
        abs(Double(last)) <= 1_000_000_000 {
            let low = min(first, last)
            let high = max(first, last)
            let count = Double(high) - Double(low) + 1
            return CalculatorExpandedSupport.numeric(
                count * (Double(low) + Double(high)) / 2,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^arithmetic sequence term (\d+) first (\#(n)) difference (\#(n))$"#,
            in: text
        ),
        let term = Int(groups[0]),
        let first = Double(groups[1]),
        let difference = Double(groups[2]),
        term > 0 {
            return CalculatorExpandedSupport.numeric(
                first + Double(term - 1) * difference,
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^arithmetic series sum (\d+) terms first (\#(n)) difference (\#(n))$"#,
            in: text
        ),
        let count = Int(groups[0]),
        let first = Double(groups[1]),
        let difference = Double(groups[2]),
        count >= 0 {
            let sum = Double(count) / 2 * (2 * first + Double(count - 1) * difference)
            return CalculatorExpandedSupport.numeric(sum, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^geometric sequence term (\d+) first (\#(n)) ratio (\#(n))$"#,
            in: text
        ),
        let term = Int(groups[0]),
        let first = Double(groups[1]),
        let ratio = Double(groups[2]),
        term > 0, term <= 10_000 {
            return CalculatorExpandedSupport.numeric(
                first * pow(ratio, Double(term - 1)),
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^geometric series sum (\d+) terms first (\#(n)) ratio (\#(n))$"#,
            in: text
        ),
        let count = Int(groups[0]),
        let first = Double(groups[1]),
        let ratio = Double(groups[2]),
        count >= 0, count <= 10_000 {
            let sum = ratio == 1
                ? first * Double(count)
                : first * (1 - pow(ratio, Double(count))) / (1 - ratio)
            return CalculatorExpandedSupport.numeric(sum, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^(triangular|pentagonal|hexagonal) number (\d+)$"#,
            in: text
        ),
        let index = Int(groups[1]),
        (0...1_000_000_000).contains(index) {
            let valueIndex = Double(index)
            let value: Double
            switch groups[0] {
            case "triangular":
                value = valueIndex * (valueIndex + 1) / 2
            case "pentagonal":
                value = valueIndex * (3 * valueIndex - 1) / 2
            default:
                value = valueIndex * (2 * valueIndex - 1)
            }
            return CalculatorExpandedSupport.numeric(value, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^sum of (squares|cubes) from 1 to (\d+)$"#,
            in: text
        ),
        let count = Int(groups[1]),
        (0...1_000_000_000).contains(count) {
            let valueCount = Double(count)
            let value = groups[0] == "squares"
                ? valueCount * (valueCount + 1) * (2 * valueCount + 1) / 6
                : pow(valueCount * (valueCount + 1) / 2, 2)
            return CalculatorExpandedSupport.numeric(value, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^greatest power of 2 not exceeding (\d+)$"#,
            in: text
        ),
        let value = Int(groups[0]),
        value > 0 {
            let power = 1 << (Int.bitWidth - 1 - value.leadingZeroBitCount)
            return CalculatorExpandedSupport.numeric(power, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^is (\d+) a power of 2$"#,
            in: text
        ),
        let value = Int(groups[0]) {
            return CalculatorExpandedSupport.text(
                String(value > 0 && value & (value - 1) == 0),
                expression: original
            )
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^digital root of (\d+)$"#,
            in: text
        ),
        let value = Int(groups[0]) {
            let root = value == 0 ? 0 : 1 + (value - 1) % 9
            return CalculatorExpandedSupport.numeric(root, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^digit sum of (\d+)$"#,
            in: text
        ) {
            let sum = groups[0].compactMap(\.wholeNumberValue).reduce(0, +)
            return CalculatorExpandedSupport.numeric(sum, expression: original)
        }

        if let groups = CalculatorExpandedSupport.captures(
            #"^number of digits in (-?\d+)$"#,
            in: text
        ) {
            let count = groups[0].filter(\.isNumber).count
            return CalculatorExpandedSupport.numeric(count, expression: original)
        }
        return nil
    }

    private static func weightedPairs(_ input: String) -> [(value: Double, weight: Double)]? {
        let canonical = input.replacingOccurrences(
            of: #"\s*(?:;|\band\b)\s*"#,
            with: ",",
            options: .regularExpression
        )
        let parts = canonical.split(separator: ",")
        let pairs = parts.compactMap { part -> (Double, Double)? in
            guard let groups = CalculatorExpandedSupport.captures(
                #"^\s*(\#(n))\s+weight\s+(\#(n))\s*$"#,
                in: String(part)
            ),
            let value = Double(groups[0]),
            let weight = Double(groups[1])
            else {
                return nil
            }
            return (value, weight)
        }
        return pairs.count == parts.count && !pairs.isEmpty ? pairs : nil
    }

    private static func fibonacci(_ index: Int) -> Int {
        guard index > 0 else { return 0 }
        var previous = 0
        var current = 1
        for _ in 1..<index {
            (previous, current) = (current, previous + current)
        }
        return current
    }
}
