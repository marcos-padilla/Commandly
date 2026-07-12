import Foundation

/// Scientific functions and constants.
///
/// Transcendental functions evaluate in `Double` with explicit domain checks.
/// Results are converted back to `Decimal` at the boundary when finite.
enum CalculatorScientific {
    static let functionNames: Set<String> = [
        "sqrt", "cbrt", "abs",
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
        "sinh", "cosh", "tanh",
        "log", "log10", "log2", "ln", "exp",
        "floor", "ceil", "round",
        "min", "max", "pow", "hypot",
        "deg", "rad",
    ]

    static func constantValue(_ name: String) -> Double? {
        switch name.lowercased() {
        case "pi": return Double.pi
        case "e": return M_E
        case "tau": return 2 * Double.pi
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

        // min / max stay in Decimal.
        if lowered == "min" || lowered == "max" {
            guard !arguments.isEmpty else {
                throw CalculatorError.invalidFunctionArity(name: lowered, expected: "at least 1 argument")
            }
            let values = try arguments.map(evaluate)
            if lowered == "min" {
                return values.min() ?? .zero
            }
            return values.max() ?? .zero
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
}
