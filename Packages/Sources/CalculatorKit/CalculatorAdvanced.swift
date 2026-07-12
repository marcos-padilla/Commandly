import Foundation

extension CalculatorUtilities {
    /// Prompt-catalog calculations that are structured commands rather than arithmetic grammar.
    static func advanced(_ original: String, lowered: String) -> Result? {
        if let groups = advancedCaptures(#"^(\d+(?:\.\d+)?) lumens$"#, lowered), let value = advancedDecimal(groups[0]) {
            return advancedText("\(plain(value)) lm", original, notes: ["Luminous flux; not converted to illuminance without an area and geometry model."])
        }
        if let result = advancedRounding(original, lowered) { return result }
        if let result = comparison(original, lowered) { return result }
        if let result = percentageBusiness(original, lowered) { return result }
        if let result = ratioAndProportion(original, lowered) { return result }
        if let result = algebra(original, lowered) { return result }
        if let result = primes(original, lowered) { return result }
        if let result = random(original, lowered) { return result }
        return nil
    }

    private static func advancedRounding(_ original: String, _ text: String) -> Result? {
        if let groups = advancedCaptures(#"^round\s+([-+]?\d+(?:\.\d+)?)\s+to the nearest\s+(\d+)$"#, text),
           let value = advancedDecimal(groups[0]), let increment = advancedDecimal(groups[1]), increment != 0 {
            return advancedNumeric(roundToIncrement(value, increment), original)
        }
        if let groups = advancedCaptures(#"^round\s+([-+]?\d+(?:\.\d+)?)\s+to the nearest\s+(hundred|thousand|million)$"#, text),
           let value = advancedDecimal(groups[0]) {
            let increment: Decimal = groups[1] == "hundred" ? 100 : groups[1] == "thousand" ? 1_000 : 1_000_000
            return advancedNumeric(roundToIncrement(value, increment), original)
        }
        if let groups = advancedCaptures(#"^([-+]?\d+(?:\.\d+)?)\s+rounded to\s+(\d+)\s+digits?$"#, text),
           let value = advancedDecimal(groups[0]), let places = Int(groups[1]), (0...12).contains(places) {
            return advancedNumeric(roundDecimalPlaces(value, places), original)
        }
        if let groups = advancedCaptures(#"^(?:round\s+)?([-+]?\d+(?:\.\d+)?)\s+to\s+(\d+)\s+(?:significant figures|significant digits|sig figs)$"#, text),
           let value = Double(groups[0]), let figures = Int(groups[1]), figures > 0, figures <= 15 {
            return advancedNumeric(Decimal(roundSignificant(value, figures)), original)
        }
        return nil
    }

    private static func comparison(_ original: String, _ text: String) -> Result? {
        if let groups = advancedCaptures(#"^is\s+([-+]?\d+(?:\.\d+)?)\s+greater than\s+([-+]?\d+(?:\.\d+)?)$"#, text),
           let lhs = advancedDecimal(groups[0]), let rhs = advancedDecimal(groups[1]) {
            return advancedText(lhs > rhs ? "true" : "false", original)
        }
        guard let groups = advancedCaptures(#"^([-+]?\d+(?:\.\d+)?)\s*(>=|<=|==|!=|>|<)\s*([-+]?\d+(?:\.\d+)?)$"#, text),
              let lhs = advancedDecimal(groups[0]), let rhs = advancedDecimal(groups[2]) else { return nil }
        let value: Bool
        switch groups[1] {
        case ">": value = lhs > rhs
        case ">=": value = lhs >= rhs
        case "<": value = lhs < rhs
        case "<=": value = lhs <= rhs
        case "==": value = lhs == rhs
        default: value = lhs != rhs
        }
        return advancedText(value ? "true" : "false", original)
    }

    private static func percentageBusiness(_ original: String, _ text: String) -> Result? {
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) to (\d+(?:\.\d+)?) (?:percent|%) change$"#, text), let old = advancedDecimal(g[0]), let new = advancedDecimal(g[1]), old != 0 { return advancedNumeric((new - old) / old * 100, original, suffix: "%") }
        if let g = advancedCaptures(#"^what (?:percentage|%) increase is (\d+(?:\.\d+)?) to (\d+(?:\.\d+)?)$"#, text), let old = advancedDecimal(g[0]), let new = advancedDecimal(g[1]), old != 0 { return advancedNumeric((new - old) / old * 100, original, suffix: "%") }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) out of (\d+(?:\.\d+)?) as a (?:percentage|%)$"#, text), let part = advancedDecimal(g[0]), let total = advancedDecimal(g[1]), total != 0 { return advancedNumeric(part / total * 100, original, suffix: "%") }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) is what (?:percentage|%) of (\d+(?:\.\d+)?)$"#, text), let part = advancedDecimal(g[0]), let total = advancedDecimal(g[1]), total != 0 { return advancedNumeric(part / total * 100, original, suffix: "%") }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) is (\d+(?:\.\d+)?)% more than what$"#, text), let total = advancedDecimal(g[0]), let rate = advancedDecimal(g[1]) { return advancedNumeric(total / (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) is (\d+(?:\.\d+)?)% less than what$"#, text), let total = advancedDecimal(g[0]), let rate = advancedDecimal(g[1]), rate != 100 { return advancedNumeric(total / (1 - rate / 100), original) }
        if let g = advancedCaptures(#"^what number plus (\d+(?:\.\d+)?)% equals (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0]), let total = advancedDecimal(g[1]) { return advancedNumeric(total / (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^what original amount becomes (\d+(?:\.\d+)?) after a (\d+(?:\.\d+)?)% increase$"#, text), let total = advancedDecimal(g[0]), let rate = advancedDecimal(g[1]) { return advancedNumeric(total / (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^split (\d+(?:\.\d+)?) plus (\d+(?:\.\d+)?)% tip between (\d+) people$"#, text), let base = advancedDecimal(g[0]), let rate = advancedDecimal(g[1]), let people = advancedDecimal(g[2]), people > 0 { return advancedNumeric(base * (1 + rate / 100) / people, original, notes: ["Per-person amount including tip."]) }
        if let g = advancedCaptures(#"^add (\d+(?:\.\d+)?)% sales tax to (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0]), let base = advancedDecimal(g[1]) { return advancedNumeric(base * (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) plus (\d+(?:\.\d+)?) percent tax$"#, text), let base = advancedDecimal(g[0]), let rate = advancedDecimal(g[1]) { return advancedNumeric(base * (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^(?:remove (\d+(?:\.\d+)?)% tax from|price before (\d+(?:\.\d+)?)% tax if total is) (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0].isEmpty ? g[1] : g[0]), let total = advancedDecimal(g[2]) { return advancedNumeric(total / (1 + rate / 100), original) }
        if let g = advancedCaptures(#"^take (\d+(?:\.\d+)?) percent off (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0]), let base = advancedDecimal(g[1]) { return advancedNumeric(base * (1 - rate / 100), original) }
        if let g = advancedCaptures(#"^price after (\d+(?:\.\d+)?)% discount on (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0]), let base = advancedDecimal(g[1]) { return advancedNumeric(base * (1 - rate / 100), original) }
        if let g = advancedCaptures(#"^original price before a (\d+(?:\.\d+)?)% discount if sale price is (\d+(?:\.\d+)?)$"#, text), let rate = advancedDecimal(g[0]), let sale = advancedDecimal(g[1]), rate != 100 { return advancedNumeric(sale / (1 - rate / 100), original) }
        if let g = advancedCaptures(#"^(?:add (\d+(?:\.\d+)?)% markup to (\d+(?:\.\d+)?)|(\d+(?:\.\d+)?) with a (\d+(?:\.\d+)?)% markup)$"#, text) {
            let rate = advancedDecimal(g[0].isEmpty ? g[3] : g[0]), base = advancedDecimal(g[1].isEmpty ? g[2] : g[1]); if let rate, let base { return advancedNumeric(base * (1 + rate / 100), original) }
        }
        if let g = advancedCaptures(#"^price with (\d+(?:\.\d+)?)% gross margin on a cost of (\d+(?:\.\d+)?)$"#, text), let margin = advancedDecimal(g[0]), let cost = advancedDecimal(g[1]), margin != 100 { return advancedNumeric(cost / (1 - margin / 100), original) }
        if let g = advancedCaptures(#"^profit margin if cost is (\d+(?:\.\d+)?) and price is (\d+(?:\.\d+)?)$"#, text), let cost = advancedDecimal(g[0]), let price = advancedDecimal(g[1]), price != 0 { return advancedNumeric((price - cost) / price * 100, original, suffix: "%") }
        if let g = advancedCaptures(#"^markup percentage from (\d+(?:\.\d+)?) to (\d+(?:\.\d+)?)$"#, text), let cost = advancedDecimal(g[0]), let price = advancedDecimal(g[1]), cost != 0 { return advancedNumeric((price - cost) / cost * 100, original, suffix: "%") }
        return nil
    }

    private static func ratioAndProportion(_ original: String, _ text: String) -> Result? {
        if let g = advancedCaptures(#"^(?:simplify\s+)?(\d+):(\d+)$"#, text), let a = Int(g[0]), let b = Int(g[1]), b != 0 { let divisor = advancedGCD(a, b); return advancedText("\(a / divisor):\(b / divisor)", original) }
        if let g = advancedCaptures(#"^(?:ratio of\s+)?(\d+)\s+to\s+(\d+)(?:\s+ratio)?$"#, text), let a = Int(g[0]), let b = Int(g[1]), b != 0 { let divisor = advancedGCD(a, b); return advancedText("\(a / divisor):\(b / divisor)", original) }
        if let g = advancedCaptures(#"^split (\d+(?:\.\d+)?) in a (\d+):(\d+) ratio$"#, text), let total = advancedDecimal(g[0]), let a = advancedDecimal(g[1]), let b = advancedDecimal(g[2]), a + b != 0 { return advancedText("\(plain(total * a / (a + b))) and \(plain(total * b / (a + b)))", original) }
        if let g = advancedCaptures(#"^if (\d+(?:\.\d+)?) costs (\d+(?:\.\d+)?), how much do (\d+(?:\.\d+)?) cost$"#, text), let quantity = advancedDecimal(g[0]), let cost = advancedDecimal(g[1]), let target = advancedDecimal(g[2]), quantity != 0 { return advancedNumeric(cost / quantity * target, original) }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?) is to (\d+(?:\.\d+)?) as (\d+(?:\.\d+)?) is to what$"#, text), let a = advancedDecimal(g[0]), let b = advancedDecimal(g[1]), let c = advancedDecimal(g[2]), a != 0 { return advancedNumeric(b * c / a, original) }
        if let g = advancedCaptures(#"^(?:solve\s+)?(\d+(?:\.\d+)?)(?:/|:)(\d+(?:\.\d+)?)\s*=\s*(\d+(?:\.\d+)?)(?:/|:)x$"#, text), let a = advancedDecimal(g[0]), let b = advancedDecimal(g[1]), let c = advancedDecimal(g[2]), a != 0 { return advancedNumeric(b * c / a, original) }
        return nil
    }

    private static func algebra(_ original: String, _ text: String) -> Result? {
        if let result = linearEquation(original, text) { return result }
        if let result = quadraticEquation(original, text) { return result }
        if let result = twoEquationSystem(original, text) { return result }
        return nil
    }

    private static func linearEquation(_ original: String, _ text: String) -> Result? {
        let cleaned = text.replacingOccurrences(of: "solve ", with: "")
        if let g = advancedCaptures(#"^x\s*([+-])\s*(\d+(?:\.\d+)?)\s*=\s*(\d+(?:\.\d+)?)$"#, cleaned), let c = advancedDecimal(g[1]), let rhs = advancedDecimal(g[2]) { return advancedNumeric(g[0] == "+" ? rhs - c : rhs + c, original) }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?)x(?:\s*([+-])\s*(\d+(?:\.\d+)?))?\s*=\s*(\d+(?:\.\d+)?)$"#, cleaned), let coefficient = advancedDecimal(g[0]), coefficient != 0, let rhs = advancedDecimal(g[3]) {
            let constant = advancedDecimal(g[2].isEmpty ? "0" : g[2]) ?? 0
            return advancedNumeric((rhs - (g[1] == "-" ? -constant : constant)) / coefficient, original)
        }
        if let g = advancedCaptures(#"^(\d+(?:\.\d+)?)\(x\s*([+-])\s*(\d+(?:\.\d+)?)\)\s*=\s*(\d+(?:\.\d+)?)$"#, cleaned), let coefficient = advancedDecimal(g[0]), coefficient != 0, let constant = advancedDecimal(g[2]), let rhs = advancedDecimal(g[3]) { let inside = rhs / coefficient; return advancedNumeric(g[1] == "+" ? inside - constant : inside + constant, original) }
        return nil
    }

    private static func quadraticEquation(_ original: String, _ text: String) -> Result? {
        var cleaned = text.replacingOccurrences(of: "solve ", with: "").replacingOccurrences(of: "roots of ", with: "").replacingOccurrences(of: "quadratic ", with: "")
        if !cleaned.contains("=") { cleaned += " = 0" }
        guard let g = advancedCaptures(#"^(?:(\d+(?:\.\d+)?)?)x\^2(?:\s*([+-])\s*(\d+(?:\.\d+)?)x)?(?:\s*([+-])\s*(\d+(?:\.\d+)?))?\s*=\s*0$"#, cleaned) else { return nil }
        let a = Double(g[0].isEmpty ? "1" : g[0]) ?? 1
        let b = (Double(g[2].isEmpty ? "0" : g[2]) ?? 0) * (g[1] == "-" ? -1 : 1)
        let c = (Double(g[4].isEmpty ? "0" : g[4]) ?? 0) * (g[3] == "-" ? -1 : 1)
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0, a != 0 else { return nil }
        let root = Foundation.sqrt(discriminant), x1 = (-b + root) / (2 * a), x2 = (-b - root) / (2 * a)
        return advancedText(x1 == x2 ? plain(Decimal(x1)) : "\(plain(Decimal(x1))), \(plain(Decimal(x2)))", original)
    }

    private static func twoEquationSystem(_ original: String, _ text: String) -> Result? {
        let cleaned = text.replacingOccurrences(of: "solve ", with: "").replacingOccurrences(of: " and ", with: ", ")
        guard let g = advancedCaptures(#"^x \+ y = ([-+]?\d+(?:\.\d+)?),\s*(\d*)x - y = ([-+]?\d+(?:\.\d+)?)$"#, cleaned), let sum = advancedDecimal(g[0]), let coefficient = advancedDecimal(g[1].isEmpty ? "1" : g[1]), let rhs = advancedDecimal(g[2]), coefficient + 1 != 0 else { return nil }
        let x = (sum + rhs) / (coefficient + 1), y = sum - x
        return advancedText("x = \(plain(x)), y = \(plain(y))", original)
    }

    private static func primes(_ original: String, _ text: String) -> Result? {
        if let g = advancedCaptures(#"^is (\d+) prime$"#, text), let value = Int(g[0]) { return advancedText(isPrime(value) ? "true" : "false", original) }
        if let g = advancedCaptures(#"^next prime after (\d+)$"#, text), var value = Int(g[0]) { repeat { value += 1 } while !isPrime(value); return advancedNumeric(Decimal(value), original) }
        if let g = advancedCaptures(#"^(?:prime factors of|factorize) (\d+)$"#, text), var value = Int(g[0]), value > 1 { var factors: [Int] = []; var candidate = 2; while candidate * candidate <= value { while value.isMultiple(of: candidate) { factors.append(candidate); value /= candidate }; candidate += 1 }; if value > 1 { factors.append(value) }; return advancedText(factors.map(String.init).joined(separator: " × "), original) }
        if let g = advancedCaptures(#"^list primes below (\d+)$"#, text), let limit = Int(g[0]) { return advancedText((2..<limit).filter(isPrime).map(String.init).joined(separator: ", "), original) }
        return nil
    }

    private static func random(_ original: String, _ text: String) -> Result? {
        let note = ["Nondeterministic result generated on demand."]
        if text == "random number" || text == "random decimal between 0 and 1" { return advancedNumeric(Decimal(Double.random(in: 0..<1)), original, notes: note) }
        if let g = advancedCaptures(#"^random number from (\d+) to (\d+)$"#, text), let lower = Int(g[0]), let upper = Int(g[1]), lower <= upper { return advancedNumeric(Decimal(Int.random(in: lower...upper)), original, notes: note) }
        if let g = advancedCaptures(#"^random integer between (\d+) and (\d+)$"#, text), let lower = Int(g[0]), let upper = Int(g[1]), lower <= upper { return advancedNumeric(Decimal(Int.random(in: lower...upper)), original, notes: note) }
        if text == "roll a die" { return advancedNumeric(Decimal(Int.random(in: 1...6)), original, notes: note) }
        if text == "roll 2d6" { return advancedNumeric(Decimal(Int.random(in: 1...6) + Int.random(in: 1...6)), original, notes: note) }
        if text == "flip a coin" { return advancedText(Bool.random() ? "heads" : "tails", original, notes: note) }
        return nil
    }

    private static func roundToIncrement(_ value: Decimal, _ increment: Decimal) -> Decimal { roundDecimalPlaces(value / increment, 0) * increment }
    private static func roundDecimalPlaces(_ value: Decimal, _ places: Int) -> Decimal { var input = value, output = Decimal(); NSDecimalRound(&output, &input, places, .plain); return output }
    private static func roundSignificant(_ value: Double, _ figures: Int) -> Double { guard value != 0 else { return 0 }; let scale = Foundation.pow(10, Double(figures - 1) - Foundation.floor(Foundation.log10(abs(value)))); return (value * scale).rounded() / scale }
    private static func advancedGCD(_ lhs: Int, _ rhs: Int) -> Int { var a = abs(lhs), b = abs(rhs); while b != 0 { (a, b) = (b, a % b) }; return max(a, 1) }
    private static func isPrime(_ value: Int) -> Bool { guard value >= 2 else { return false }; if value == 2 { return true }; if value.isMultiple(of: 2) { return false }; var divisor = 3; while divisor * divisor <= value { if value.isMultiple(of: divisor) { return false }; divisor += 2 }; return true }
    private static func advancedDecimal(_ text: String) -> Decimal? { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) }
    private static func plain(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private static func advancedNumeric(_ value: Decimal, _ expression: String, suffix: String = "", notes: [String] = []) -> Result { Result(kind: .arithmetic, primaryValue: .decimal(value), formattedPrimaryValue: plain(value) + suffix, metadata: .init(notes: notes), displayExpression: expression) }
    private static func advancedText(_ value: String, _ expression: String, notes: [String] = []) -> Result { Result(kind: .arithmetic, primaryValue: .text(value), formattedPrimaryValue: value, metadata: .init(notes: notes), displayExpression: expression) }
    private static func advancedCaptures(_ pattern: String, _ text: String) -> [String]? { guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }; return (1..<match.numberOfRanges).map { index in guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return "" }; return String(text[range]) } }
}
