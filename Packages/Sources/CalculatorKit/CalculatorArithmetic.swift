import Foundation

/// Decimal arithmetic evaluator for the expression AST.
enum CalculatorArithmetic {
    struct EvaluationOutput: Sendable, Equatable {
        let value: Decimal
        let kind: CalculatorResultKind
        let metadata: CalculatorResultMetadata
        let usedScientific: Bool
    }

    static func evaluate(
        _ expression: Expression,
        context: CalculatorEvaluationContext,
        phraseTag: String? = nil
    ) throws -> EvaluationOutput {
        var metadata = CalculatorResultMetadata()
        var usedScientific = false
        let value = try eval(
            expression,
            context: context,
            metadata: &metadata,
            usedScientific: &usedScientific,
            phraseTag: phraseTag
        )
        guard DecimalMath.isFinite(value) else {
            throw CalculatorError.overflow
        }
        let kind: CalculatorResultKind
        if metadata.percentage != nil {
            kind = .percentage
        } else if usedScientific {
            kind = .scientific
        } else {
            kind = .arithmetic
        }
        return EvaluationOutput(value: value, kind: kind, metadata: metadata, usedScientific: usedScientific)
    }

    private static func eval(
        _ expression: Expression,
        context: CalculatorEvaluationContext,
        metadata: inout CalculatorResultMetadata,
        usedScientific: inout Bool,
        phraseTag: String?
    ) throws -> Decimal {
        switch expression {
        case .number(let value):
            return value

        case .constant(let name):
            if let constant = CalculatorScientific.constantValue(name) {
                usedScientific = true
                guard let decimal = DecimalMath.fromDouble(constant) else {
                    throw CalculatorError.overflow
                }
                return decimal
            }
            throw CalculatorError.unknownConstant(name)

        case .answer:
            guard let previous = context.previousAnswer else {
                throw CalculatorError.missingPreviousAnswer
            }
            return previous

        case .unary(let op, let expr):
            let value = try eval(expr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            switch op {
            case .plus: return value
            case .minus: return -value
            }

        case .binary(let op, let lhs, let rhs):
            // 350 * 20% → 70
            if op == .multiply, case .postfixPercent(let percentExpr) = rhs {
                let base = try eval(lhs, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
                let percent = try eval(percentExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
                let amount = base * percent / DecimalMath.hundred
                metadata.baseAmount = base
                metadata.percentage = percent
                metadata.percentageAmount = amount
                metadata.total = amount
                return amount
            }
            // 20% * 350
            if op == .multiply, case .postfixPercent(let percentExpr) = lhs {
                let percent = try eval(percentExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
                let base = try eval(rhs, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
                let amount = base * percent / DecimalMath.hundred
                metadata.baseAmount = base
                metadata.percentage = percent
                metadata.percentageAmount = amount
                metadata.total = amount
                return amount
            }

            let left = try eval(lhs, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            let right = try eval(rhs, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            return try applyBinary(op, left, right)

        case .percentOf(let percentExpr, let baseExpr):
            let percent = try eval(percentExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            let base = try eval(baseExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            let amount = base * percent / DecimalMath.hundred
            metadata.baseAmount = base
            metadata.percentage = percent
            metadata.percentageAmount = amount

            switch phraseTag {
            case "tip", "tax":
                let total = base + amount
                metadata.total = total
                if phraseTag == "tip" {
                    metadata.notes.append("Tip \(formatPlain(amount)); total \(formatPlain(total))")
                } else {
                    metadata.notes.append("Tax \(formatPlain(amount)); total \(formatPlain(total))")
                }
                return amount
            case "discount":
                let total = base - amount
                metadata.total = total
                metadata.notes.append("Discount \(formatPlain(amount)); total \(formatPlain(total))")
                return amount
            default:
                metadata.total = amount
                return amount
            }

        case .postfixPercent(let expr):
            // Bare `20%` → 0.2
            let percent = try eval(expr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            metadata.percentage = percent
            return percent / DecimalMath.hundred

        case .percentAdjust(let op, let baseExpr, let percentExpr):
            let base = try eval(baseExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            let percent = try eval(percentExpr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
            let amount = base * percent / DecimalMath.hundred
            metadata.baseAmount = base
            metadata.percentage = percent
            metadata.percentageAmount = amount
            switch op {
            case .add:
                let total = base + amount
                metadata.total = total
                return total
            case .subtract:
                let total = base - amount
                metadata.total = total
                return total
            default:
                throw CalculatorError.unsupportedOperation
            }

        case .call(let name, let args):
            usedScientific = true
            return try CalculatorScientific.evaluateDecimal(
                name: name,
                arguments: args,
                context: context,
                evaluate: { expr in
                    try eval(expr, context: context, metadata: &metadata, usedScientific: &usedScientific, phraseTag: phraseTag)
                }
            )
        }
    }

    private static func applyBinary(_ op: BinaryOperator, _ left: Decimal, _ right: Decimal) throws -> Decimal {
        switch op {
        case .add:
            return left + right
        case .subtract:
            return left - right
        case .multiply:
            return left * right
        case .divide:
            if right == .zero { throw CalculatorError.divisionByZero }
            return left / right
        case .modulo:
            if right == .zero { throw CalculatorError.divisionByZero }
            let quotient = left / right
            let truncated = Decimal(NSDecimalNumber(decimal: quotient).intValue)
            return left - (truncated * right)
        case .power:
            return try power(left, right)
        }
    }

    /// Integer exponents stay in Decimal; fractional exponents cross to Double explicitly.
    private static func power(_ base: Decimal, _ exponent: Decimal) throws -> Decimal {
        var intExponent = Decimal()
        var rounded = exponent
        NSDecimalRound(&intExponent, &rounded, 0, .plain)
        if intExponent == exponent,
           let expInt = Int(exactly: NSDecimalNumber(decimal: intExponent)) {
            return try DecimalMath.pow(base, expInt)
        }

        guard let baseDouble = DecimalMath.toDouble(base),
              let expDouble = DecimalMath.toDouble(exponent)
        else {
            throw CalculatorError.overflow
        }
        if baseDouble < 0 {
            throw CalculatorError.invalidDomain(function: "pow")
        }
        let result = Foundation.pow(baseDouble, expDouble)
        guard result.isFinite, let decimal = DecimalMath.fromDouble(result) else {
            throw CalculatorError.overflow
        }
        return decimal
    }

    private static func formatPlain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
