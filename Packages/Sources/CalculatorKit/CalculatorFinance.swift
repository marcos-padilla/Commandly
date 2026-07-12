import Foundation

/// Deterministic personal-finance and business formulas.
///
/// This evaluator does not fetch market data and does not infer taxes, fees,
/// insurance, legal overtime rules, or investment returns. Every configurable
/// assumption comes from `CalculatorEvaluationContext` and is recorded in
/// result metadata.
enum CalculatorFinance {
    struct Result: Sendable, Equatable {
        let value: Decimal
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(_ text: String, context: CalculatorEvaluationContext) throws -> Result {
        let input = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let values = numbers(#"^simple interest on (\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return simpleInterest(principal: values[0], annualRate: values[1], years: values[2], input: input)
        }
        if let values = numbers(#"^(\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% simple interest for (\d+(?:\.\d+)?) months?$"#, input, count: 3) {
            return simpleInterest(principal: values[0], annualRate: values[1], years: values[2] / 12, input: input)
        }

        if let values = numbers(#"^(\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% compounded monthly for (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return compoundValue(principal: values[0], annualRate: values[1], years: values[2], periodsPerYear: 12, input: input)
        }
        if let values = numbers(#"^compound (\d+(?:\.\d+)?) annually at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return compoundValue(principal: values[0], annualRate: values[1], years: values[2], periodsPerYear: 1, input: input)
        }
        if let values = numbers(#"^future value of (\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return compoundValue(principal: values[0], annualRate: values[1], years: values[2], periodsPerYear: 1, input: input)
        }

        if let values = numbers(#"^present value of (\d+(?:\.\d+)?) in (\d+(?:\.\d+)?) years? at (\d+(?:\.\d+)?)\s*%$"#, input, count: 3) {
            let future = values[0]
            let years = values[1]
            let rate = values[2]
            guard rate > -100 else { throw CalculatorError.invalidDomain(function: "present value") }
            let present = future / Foundation.pow(1 + rate / 100, years)
            return decimalResult(present, input: input, base: future, percentage: rate, notes: ["Discounted annually for \(plain(years)) years"])
        }
        if let values = numbers(#"^pv of (\d+(?:\.\d+)?) monthly for (\d+(?:\.\d+)?) years? at (\d+(?:\.\d+)?)\s*%$"#, input, count: 3) {
            let payment = values[0]
            let months = values[1] * 12
            let monthlyRate = values[2] / 100 / 12
            let present = monthlyRate == 0
                ? payment * months
                : payment * (1 - Foundation.pow(1 + monthlyRate, -months)) / monthlyRate
            return decimalResult(present, input: input, base: payment, percentage: values[2], notes: ["Ordinary monthly annuity; \(plain(months)) payments"])
        }

        if let values = numbers(#"^monthly payment on (\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return try loanPayment(principal: values[0], annualRate: values[1], months: values[2] * 12, input: input)
        }
        if let values = numbers(#"^car payment for (\d+(?:\.\d+)?) at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) months?$"#, input, count: 3) {
            return try loanPayment(principal: values[0], annualRate: values[1], months: values[2], input: input)
        }
        if let values = numbers(#"^mortgage payment on (\d+(?:\.\d+)?) with (\d+(?:\.\d+)?)\s*% down at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 4) {
            let principal = values[0] * (1 - values[1] / 100)
            let result = try loanPayment(principal: principal, annualRate: values[2], months: values[3] * 12, input: input)
            var metadata = result.metadata
            metadata.notes.append("Purchase price \(plain(values[0])); down payment \(plain(values[0] - principal))")
            return Result(value: result.value, metadata: metadata, displayExpression: result.displayExpression)
        }
        if let values = numbers(#"^remaining balance after (\d+(?:\.\d+)?) years? on a (\d+(?:\.\d+)?) loan at (\d+(?:\.\d+)?)\s*% for (\d+(?:\.\d+)?) years?$"#, input, count: 4) {
            return remainingBalance(elapsedMonths: values[0] * 12, principal: values[1], annualRate: values[2], totalMonths: values[3] * 12, input: input)
        }

        if let values = numbers(#"^(\d+(?:\.\d+)?)\s*% down on (\d+(?:\.\d+)?)$"#, input, count: 2) {
            let down = values[1] * values[0] / 100
            return decimalResult(down, input: input, base: values[1], percentage: values[0], total: values[1] - down, notes: ["Loan amount \(plain(values[1] - down))"])
        }
        if let values = numbers(#"^(\d+(?:\.\d+)?) with (\d+(?:\.\d+)?)\s*% down$"#, input, count: 2) {
            let down = values[0] * values[1] / 100
            return decimalResult(down, input: input, base: values[0], percentage: values[1], total: values[0] - down, notes: ["Loan amount \(plain(values[0] - down))"])
        }
        if let values = numbers(#"^loan amount after (\d+(?:\.\d+)?)\s*% down on (\d+(?:\.\d+)?)$"#, input, count: 2) {
            let down = values[1] * values[0] / 100
            return decimalResult(values[1] - down, input: input, base: values[1], percentage: values[0], notes: ["Down payment \(plain(down))"])
        }

        if let values = numbers(#"^how much to save monthly to reach (\d+(?:\.\d+)?) in (\d+(?:\.\d+)?) years?$"#, input, count: 2) {
            let months = values[1] * 12
            guard months > 0 else { throw CalculatorError.invalidDomain(function: "savings goal") }
            return decimalResult(values[0] / months, input: input, total: values[0], notes: ["No investment return assumed; \(plain(months)) monthly deposits"])
        }
        if let values = numbers(#"^monthly savings needed for (\d+(?:\.\d+)?) in (\d+(?:\.\d+)?) years? at (\d+(?:\.\d+)?)\s*%$"#, input, count: 3) {
            let months = values[1] * 12
            let monthlyRate = values[2] / 100 / 12
            guard months > 0 else { throw CalculatorError.invalidDomain(function: "savings goal") }
            let contribution = monthlyRate == 0
                ? values[0] / months
                : values[0] * monthlyRate / (Foundation.pow(1 + monthlyRate, months) - 1)
            return decimalResult(contribution, input: input, percentage: values[2], total: values[0], notes: ["End-of-month deposits; monthly compounding"])
        }

        if let values = numbers(#"^return from (\d+(?:\.\d+)?) growing to (\d+(?:\.\d+)?)$"#, input, count: 2) {
            guard values[0] != 0 else { throw CalculatorError.divisionByZero }
            return decimalResult((values[1] - values[0]) / values[0] * 100, input: input, base: values[0], total: values[1], notes: ["Total return percentage"])
        }
        if let values = numbers(#"^(?:annualized return|cagr) from (\d+(?:\.\d+)?) to (\d+(?:\.\d+)?) (?:over|in|/) (\d+(?:\.\d+)?) years?$"#, input, count: 3) {
            return try annualizedReturn(start: values[0], end: values[1], years: values[2], input: input)
        }

        if let values = numbers(#"^profit if revenue is (\d+(?:\.\d+)?) and cost is (\d+(?:\.\d+)?)$"#, input, count: 2) {
            return decimalResult(values[0] - values[1], input: input, base: values[0], total: values[1], notes: ["Revenue minus cost"])
        }
        if let values = numbers(#"^profit margin on revenue (\d+(?:\.\d+)?) and profit (\d+(?:\.\d+)?)$"#, input, count: 2) {
            guard values[0] != 0 else { throw CalculatorError.divisionByZero }
            return decimalResult(values[1] / values[0] * 100, input: input, base: values[0], total: values[1], notes: ["Profit ÷ revenue × 100"])
        }
        if let values = numbers(#"^loss (?:percentage|%) from (\d+(?:\.\d+)?) to (\d+(?:\.\d+)?)$"#, input, count: 2) {
            guard values[0] != 0 else { throw CalculatorError.divisionByZero }
            return decimalResult((values[0] - values[1]) / values[0] * 100, input: input, base: values[0], total: values[1], notes: ["Loss percentage"])
        }

        if let values = numbers(#"^break even units if fixed cost is (\d+(?:\.\d+)?),? price is (\d+(?:\.\d+)?) and variable cost is (\d+(?:\.\d+)?)$"#, input, count: 3) {
            let contribution = values[1] - values[2]
            guard contribution > 0 else { throw CalculatorError.invalidDomain(function: "break even") }
            return decimalResult(Foundation.ceil(values[0] / contribution), input: input, base: values[0], notes: ["Whole units rounded up; contribution margin per unit \(plain(contribution))"])
        }
        if let values = numbers(#"^break even revenue with fixed cost (\d+(?:\.\d+)?) and margin (\d+(?:\.\d+)?)\s*%$"#, input, count: 2) {
            guard values[1] > 0 else { throw CalculatorError.invalidDomain(function: "break even") }
            return decimalResult(values[0] / (values[1] / 100), input: input, base: values[0], percentage: values[1], notes: ["Fixed cost ÷ contribution-margin ratio"])
        }

        if let result = try payConversion(input, context: context) { return result }
        if let result = try overtime(input, context: context) { return result }

        throw CalculatorError.unsupportedOperation
    }

    private static func simpleInterest(principal: Double, annualRate: Double, years: Double, input: String) -> Result {
        let interest = principal * annualRate / 100 * years
        return decimalResult(principal + interest, input: input, base: principal, percentage: annualRate, percentageAmount: interest, total: principal + interest, notes: ["Simple interest \(plain(interest))"])
    }

    private static func compoundValue(principal: Double, annualRate: Double, years: Double, periodsPerYear: Double, input: String) -> Result {
        let value = principal * Foundation.pow(1 + annualRate / 100 / periodsPerYear, periodsPerYear * years)
        return decimalResult(value, input: input, base: principal, percentage: annualRate, total: value, notes: ["Compounded \(periodsPerYear == 12 ? "monthly" : "annually")"])
    }

    private static func loanPayment(principal: Double, annualRate: Double, months: Double, input: String) throws -> Result {
        guard principal >= 0, months > 0 else { throw CalculatorError.invalidDomain(function: "loan payment") }
        let monthlyRate = annualRate / 100 / 12
        let payment = monthlyRate == 0
            ? principal / months
            : principal * monthlyRate / (1 - Foundation.pow(1 + monthlyRate, -months))
        let totalPaid = payment * months
        return decimalResult(payment, input: input, base: principal, percentage: annualRate, total: totalPaid, notes: [
            "\(plain(months)) monthly payments",
            "Total interest \(plain(totalPaid - principal)); total paid \(plain(totalPaid))",
            "Excludes taxes, insurance, HOA, and fees",
        ])
    }

    private static func remainingBalance(elapsedMonths: Double, principal: Double, annualRate: Double, totalMonths: Double, input: String) -> Result {
        let monthlyRate = annualRate / 100 / 12
        let balance: Double
        if monthlyRate == 0 {
            balance = principal * max(0, 1 - elapsedMonths / totalMonths)
        } else {
            let payment = principal * monthlyRate / (1 - Foundation.pow(1 + monthlyRate, -totalMonths))
            balance = principal * Foundation.pow(1 + monthlyRate, elapsedMonths)
                - payment * (Foundation.pow(1 + monthlyRate, elapsedMonths) - 1) / monthlyRate
        }
        return decimalResult(max(0, balance), input: input, base: principal, percentage: annualRate, notes: ["After \(plain(elapsedMonths)) monthly payments"])
    }

    private static func annualizedReturn(start: Double, end: Double, years: Double, input: String) throws -> Result {
        guard start > 0, end >= 0, years > 0 else { throw CalculatorError.invalidDomain(function: "annualized return") }
        let result = (Foundation.pow(end / start, 1 / years) - 1) * 100
        return decimalResult(result, input: input, base: start, total: end, notes: ["Compound annual growth rate"])
    }

    private static func payConversion(_ input: String, context: CalculatorEvaluationContext) throws -> Result? {
        let hours = try decimalToDouble(context.workHoursPerWeek)
        let weeks = try decimalToDouble(context.workWeeksPerYear)
        guard hours > 0, weeks > 0 else { throw CalculatorError.invalidDomain(function: "pay assumptions") }
        let assumptions = "Assumes \(plain(hours)) paid hours/week and \(plain(weeks)) paid weeks/year"

        if let value = oneNumber(#"^(\d+(?:\.\d+)?) per hour yearly$"#, input) {
            return decimalResult(value * hours * weeks, input: input, notes: [assumptions])
        }
        if let value = oneNumber(#"^(\d+(?:\.\d+)?) salary hourly$"#, input) {
            return decimalResult(value / (hours * weeks), input: input, notes: [assumptions])
        }
        if let value = oneNumber(#"^(\d+(?:\.\d+)?) per month yearly$"#, input) {
            return decimalResult(value * 12, input: input, notes: ["12 months/year"])
        }
        if let value = oneNumber(#"^(\d+(?:\.\d+)?) per week annually$"#, input) {
            return decimalResult(value * weeks, input: input, notes: ["Assumes \(plain(weeks)) paid weeks/year"])
        }
        if let value = oneNumber(#"^(\d+(?:\.\d+)?) annually monthly$"#, input) {
            return decimalResult(value / 12, input: input, notes: ["12 months/year"])
        }
        return nil
    }

    private static func overtime(_ input: String, context: CalculatorEvaluationContext) throws -> Result? {
        let multiplier = try decimalToDouble(context.overtimeMultiplier)
        guard multiplier >= 0 else { throw CalculatorError.invalidDomain(function: "overtime multiplier") }
        let note = "Uses configured overtime multiplier \(plain(multiplier))×; no legal rule inferred"
        if let values = numbers(#"^(\d+(?:\.\d+)?) hours at (\d+(?:\.\d+)?) \+ (\d+(?:\.\d+)?) hours overtime$"#, input, count: 3) {
            let total = values[0] * values[1] + values[2] * values[1] * multiplier
            return decimalResult(total, input: input, base: values[1], notes: [note])
        }
        if let values = numbers(#"^overtime pay for (\d+(?:\.\d+)?) hours at (\d+(?:\.\d+)?) per hour$"#, input, count: 2) {
            return decimalResult(values[0] * values[1] * multiplier, input: input, base: values[1], notes: [note])
        }
        return nil
    }

    private static func decimalResult(
        _ value: Double,
        input: String,
        base: Double? = nil,
        percentage: Double? = nil,
        percentageAmount: Double? = nil,
        total: Double? = nil,
        notes: [String]
    ) -> Result {
        var metadata = CalculatorResultMetadata(notes: notes)
        metadata.baseAmount = base.flatMap(DecimalMath.fromDouble)
        metadata.percentage = percentage.flatMap(DecimalMath.fromDouble)
        metadata.percentageAmount = percentageAmount.flatMap(DecimalMath.fromDouble)
        metadata.total = total.flatMap(DecimalMath.fromDouble)
        return Result(
            value: DecimalMath.fromDouble(value) ?? .nan,
            metadata: metadata,
            displayExpression: input
        )
    }

    private static func numbers(_ pattern: String, _ input: String, count: Int) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input)),
              match.numberOfRanges == count + 1
        else { return nil }
        var values: [Double] = []
        values.reserveCapacity(count)
        for index in 1...count {
            guard let range = Range(match.range(at: index), in: input), let value = Double(input[range]) else { return nil }
            values.append(value)
        }
        return values
    }

    private static func oneNumber(_ pattern: String, _ input: String) -> Double? {
        numbers(pattern, input, count: 1)?.first
    }

    private static func decimalToDouble(_ value: Decimal) throws -> Double {
        guard let result = DecimalMath.toDouble(value) else { throw CalculatorError.overflow }
        return result
    }

    private static func plain(_ value: Double) -> String {
        guard let decimal = DecimalMath.fromDouble(value) else { return String(value) }
        return NSDecimalNumber(decimal: decimal).stringValue
    }
}
