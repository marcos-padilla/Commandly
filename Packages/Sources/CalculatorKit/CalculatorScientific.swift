import Foundation

/// Scientific functions and constants.
///
/// Transcendental functions evaluate in `Double` with explicit domain checks.
/// Results are converted back to `Decimal` at the boundary when finite.
enum CalculatorScientific {
    static let functionNames: Set<String> = [
        "sqrt", "cbrt", "abs",
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
        "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
        "log", "log10", "log2", "ln", "exp",
        "floor", "ceil", "round", "truncate", "trunc",
        "min", "max", "sum", "average", "mean", "median", "mode", "product", "range",
        "variance", "stddev", "clamp", "pow", "hypot", "nthroot", "root",
        "factorial", "gcd", "lcm", "ncr", "npr", "c", "p",
        "deg", "rad", "sind", "cosd", "tand",
    ]

    static func constantValue(_ name: String) -> Double? {
        switch name.lowercased() {
        case "pi": return Double.pi
        case "e": return M_E
        case "tau": return 2 * Double.pi
        case "phi": return (1 + Foundation.sqrt(5)) / 2
        case "sqrt2": return Foundation.sqrt(2)
        case "ln2": return Foundation.log(2)
        case "ln10": return Foundation.log(10)
        default: return nil
        }
    }

    static func evaluateDecimal(
        name: String,
        arguments: [Expression],
        context: CalculatorEvaluationContext,
        evaluate: (Expression) throws -> Decimal
    ) throws -> Decimal {
        let lowered = name.lowercased()
        guard functionNames.contains(lowered) else {
            throw CalculatorError.unknownFunction(name)
        }

        // Aggregations stay in Decimal where practical.
        if ["min", "max", "sum", "average", "mean", "median", "mode", "product", "range", "variance", "stddev"].contains(lowered) {
            guard !arguments.isEmpty else {
                throw CalculatorError.invalidFunctionArity(name: lowered, expected: "at least 1 argument")
            }
            let values = try arguments.map(evaluate)
            switch lowered {
            case "min": return values.min() ?? .zero
            case "max": return values.max() ?? .zero
            case "sum": return values.reduce(0, +)
            case "average", "mean": return values.reduce(0, +) / Decimal(values.count)
            case "median":
                let sorted = values.sorted()
                let middle = sorted.count / 2
                return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            case "mode":
                let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
                guard let highest = counts.values.max(),
                      counts.values.filter({ $0 == highest }).count == 1,
                      let winner = counts.first(where: { $0.value == highest })?.key
                else { throw CalculatorError.invalidDomain(function: "mode") }
                return winner
            case "product": return values.reduce(1, *)
            case "range":
                guard let minimum = values.min(), let maximum = values.max() else { return 0 }
                return maximum - minimum
            case "variance", "stddev":
                let mean = values.reduce(0, +) / Decimal(values.count)
                let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Decimal(values.count)
                if lowered == "variance" { return variance }
                guard let double = DecimalMath.toDouble(variance), let result = DecimalMath.fromDouble(Foundation.sqrt(double)) else {
                    throw CalculatorError.overflow
                }
                return result
            default: break
            }
        }

        if lowered == "abs" {
            try expectArity(lowered, arguments, 1)
            let value = try evaluate(arguments[0])
            return value < 0 ? -value : value
        }

        if lowered == "floor" || lowered == "ceil" {
            try expectArity(lowered, arguments, 1)
            let value = try evaluate(arguments[0])
            var result = Decimal()
            var input = value
            NSDecimalRound(&result, &input, 0, lowered == "floor" ? .down : .up)
            return result
        }

        if lowered == "truncate" || lowered == "trunc" {
            try expectArity(lowered, arguments, 1)
            var value = try evaluate(arguments[0])
            var result = Decimal()
            NSDecimalRound(&result, &value, 0, value < 0 ? .up : .down)
            return result
        }

        if lowered == "factorial" {
            try expectArity(lowered, arguments, 1)
            let value = try evaluate(arguments[0])
            return try integerFactorial(value)
        }

        if lowered == "clamp" {
            try expectArity(lowered, arguments, 3)
            let value = try evaluate(arguments[0])
            let lower = try evaluate(arguments[1])
            let upper = try evaluate(arguments[2])
            guard lower <= upper else { throw CalculatorError.invalidDomain(function: "clamp") }
            return min(max(value, lower), upper)
        }

        if ["gcd", "lcm", "ncr", "npr", "c", "p"].contains(lowered) {
            try expectArity(lowered, arguments, 2)
            let lhs = try exactNonnegativeInteger(evaluate(arguments[0]), function: lowered)
            let rhs = try exactNonnegativeInteger(evaluate(arguments[1]), function: lowered)
            switch lowered {
            case "gcd": return Decimal(greatestCommonDivisor(lhs, rhs))
            case "lcm":
                guard lhs != 0, rhs != 0 else { return 0 }
                return Decimal(lhs / greatestCommonDivisor(lhs, rhs) * rhs)
            case "ncr", "c":
                guard rhs <= lhs else { throw CalculatorError.invalidDomain(function: lowered) }
                let k = min(rhs, lhs - rhs)
                if k == 0 { return 1 }
                return (1...k).reduce(Decimal(1)) { result, index in
                    result * Decimal(lhs - k + index) / Decimal(index)
                }
            default:
                guard rhs <= lhs else { throw CalculatorError.invalidDomain(function: lowered) }
                if rhs == 0 { return 1 }
                return (0..<rhs).reduce(Decimal(1)) { $0 * Decimal(lhs - $1) }
            }
        }

        if lowered == "round" {
            if arguments.count == 1 {
                let value = try evaluate(arguments[0])
                var result = Decimal()
                var input = value
                NSDecimalRound(&result, &input, 0, .plain)
                return result
            }
            if arguments.count == 2 {
                let value = try evaluate(arguments[0])
                let placesDecimal = try evaluate(arguments[1])
                var placesRounded = Decimal()
                var placesInput = placesDecimal
                NSDecimalRound(&placesRounded, &placesInput, 0, .plain)
                let places = NSDecimalNumber(decimal: placesRounded).intValue
                guard places >= 0, places <= 12 else {
                    throw CalculatorError.invalidDomain(function: "round")
                }
                var result = Decimal()
                var input = value
                NSDecimalRound(&result, &input, places, .plain)
                return result
            }
            throw CalculatorError.invalidFunctionArity(name: "round", expected: "1 or 2 arguments")
        }

        if lowered == "log", arguments.count == 2 {
            let value = try evaluate(arguments[0])
            let base = try evaluate(arguments[1])
            guard let valueDouble = DecimalMath.toDouble(value),
                  let baseDouble = DecimalMath.toDouble(base),
                  valueDouble > 0, baseDouble > 0, baseDouble != 1,
                  let result = DecimalMath.fromDouble(Foundation.log(valueDouble) / Foundation.log(baseDouble))
            else {
                throw CalculatorError.invalidDomain(function: "log")
            }
            return result
        }

        // Remaining functions use Double.
        let doubles = try arguments.map { expr -> Double in
            let decimal = try evaluate(expr)
            guard let double = DecimalMath.toDouble(decimal) else {
                throw CalculatorError.overflow
            }
            return double
        }

        let result = try evaluateDouble(name: lowered, arguments: doubles, angleMode: context.angleMode)
        guard let decimal = DecimalMath.fromDouble(result) else {
            throw CalculatorError.overflow
        }
        return decimal
    }

    /// Direct Double evaluation for tests / scientific path clarity.
    static func evaluateDouble(
        name: String,
        arguments: [Double],
        angleMode: CalculatorAngleMode
    ) throws -> Double {
        let lowered = name.lowercased()

        func one(_ body: (Double) throws -> Double) throws -> Double {
            try expectArityCount(lowered, arguments, 1)
            return try body(arguments[0])
        }

        func two(_ body: (Double, Double) throws -> Double) throws -> Double {
            try expectArityCount(lowered, arguments, 2)
            return try body(arguments[0], arguments[1])
        }

        let value: Double
        switch lowered {
        case "sqrt":
            value = try one {
                guard $0 >= 0 else { throw CalculatorError.invalidDomain(function: "sqrt") }
                return Foundation.sqrt($0)
            }
        case "cbrt":
            value = try one { Foundation.cbrt($0) }
        case "sin":
            value = try one { Foundation.sin(toRadians($0, mode: angleMode)) }
        case "cos":
            value = try one { Foundation.cos(toRadians($0, mode: angleMode)) }
        case "tan":
            value = try one {
                let radians = toRadians($0, mode: angleMode)
                let result = Foundation.tan(radians)
                guard result.isFinite else { throw CalculatorError.invalidDomain(function: "tan") }
                return result
            }
        case "sind":
            value = try one { Foundation.sin($0 * Double.pi / 180) }
        case "cosd":
            value = try one { Foundation.cos($0 * Double.pi / 180) }
        case "tand":
            value = try one { Foundation.tan($0 * Double.pi / 180) }
        case "asin":
            value = try one {
                guard $0 >= -1, $0 <= 1 else { throw CalculatorError.invalidDomain(function: "asin") }
                return fromRadians(Foundation.asin($0), mode: angleMode)
            }
        case "acos":
            value = try one {
                guard $0 >= -1, $0 <= 1 else { throw CalculatorError.invalidDomain(function: "acos") }
                return fromRadians(Foundation.acos($0), mode: angleMode)
            }
        case "atan":
            value = try one { fromRadians(Foundation.atan($0), mode: angleMode) }
        case "atan2":
            value = try two { fromRadians(Foundation.atan2($0, $1), mode: angleMode) }
        case "sinh":
            value = try one { Foundation.sinh($0) }
        case "cosh":
            value = try one { Foundation.cosh($0) }
        case "tanh":
            value = try one { Foundation.tanh($0) }
        case "asinh":
            value = try one { Foundation.asinh($0) }
        case "acosh":
            value = try one {
                guard $0 >= 1 else { throw CalculatorError.invalidDomain(function: "acosh") }
                return Foundation.acosh($0)
            }
        case "atanh":
            value = try one {
                guard $0 > -1, $0 < 1 else { throw CalculatorError.invalidDomain(function: "atanh") }
                return Foundation.atanh($0)
            }
        case "log", "ln":
            value = try one {
                guard $0 > 0 else { throw CalculatorError.invalidDomain(function: lowered) }
                return Foundation.log($0)
            }
        case "log10":
            value = try one {
                guard $0 > 0 else { throw CalculatorError.invalidDomain(function: "log10") }
                return Foundation.log10($0)
            }
        case "log2":
            value = try one {
                guard $0 > 0 else { throw CalculatorError.invalidDomain(function: "log2") }
                return Foundation.log2($0)
            }
        case "exp":
            value = try one { Foundation.exp($0) }
        case "pow":
            value = try two {
                let result = Foundation.pow($0, $1)
                guard result.isFinite else { throw CalculatorError.overflow }
                return result
            }
        case "hypot":
            value = try two { Foundation.hypot($0, $1) }
        case "nthroot", "root":
            value = try two { radicand, degree in
                guard degree != 0 else { throw CalculatorError.invalidDomain(function: lowered) }
                if radicand < 0 {
                    let rounded = degree.rounded()
                    guard rounded == degree, Int(rounded).isMultiple(of: 2) == false else {
                        throw CalculatorError.invalidDomain(function: lowered)
                    }
                    return -Foundation.pow(-radicand, 1 / degree)
                }
                return Foundation.pow(radicand, 1 / degree)
            }
        case "deg":
            value = try one { $0 * 180 / Double.pi }
        case "rad":
            value = try one { $0 * Double.pi / 180 }
        default:
            throw CalculatorError.unknownFunction(name)
        }

        guard value.isFinite else {
            throw CalculatorError.overflow
        }
        return value
    }

    private static func toRadians(_ value: Double, mode: CalculatorAngleMode) -> Double {
        switch mode {
        case .radians: return value
        case .degrees: return value * Double.pi / 180
        }
    }

    private static func fromRadians(_ value: Double, mode: CalculatorAngleMode) -> Double {
        switch mode {
        case .radians: return value
        case .degrees: return value * 180 / Double.pi
        }
    }

    private static func expectArity(_ name: String, _ args: [Expression], _ count: Int) throws {
        guard args.count == count else {
            throw CalculatorError.invalidFunctionArity(name: name, expected: "\(count) argument\(count == 1 ? "" : "s")")
        }
    }

    private static func expectArityCount(_ name: String, _ args: [Double], _ count: Int) throws {
        guard args.count == count else {
            throw CalculatorError.invalidFunctionArity(name: name, expected: "\(count) argument\(count == 1 ? "" : "s")")
        }
    }

    private static func exactNonnegativeInteger(_ value: Decimal, function: String) throws -> Int {
        let number = NSDecimalNumber(decimal: value)
        let integer = number.intValue
        guard value >= 0, Decimal(integer) == value else { throw CalculatorError.invalidDomain(function: function) }
        return integer
    }

    private static func integerFactorial(_ value: Decimal) throws -> Decimal {
        let integer = try exactNonnegativeInteger(value, function: "factorial")
        guard integer <= 32 else { throw CalculatorError.invalidDomain(function: "factorial") }
        if integer < 2 { return 1 }
        return (2...integer).reduce(Decimal(1)) { $0 * Decimal($1) }
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }
}
