import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator memory, ambiguity, and error coverage", .serialized)
struct CalculatorMemoryAndErrorCoverageTests {
    private let service = CalculatorService()

    private func context(
        locale: Locale = Locale(identifier: "en_US"),
        previousAnswer: Decimal? = nil,
        previousValue: CalculatorValue? = nil,
        variables: [String: CalculatorVariable] = [:]
    ) -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return CalculatorEvaluationContext(
            locale: locale,
            calendar: calendar,
            timeZone: .gmt,
            now: now,
            previousAnswer: previousAnswer,
            previousValue: previousValue,
            variables: variables
        )
    }

    private func success(_ expression: String, context: CalculatorEvaluationContext) async throws -> CalculatorResult {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome else {
            Issue.record("Expected success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected success")
        }
        return result
    }

    private func decimal(_ expression: String, context: CalculatorEvaluationContext) async throws -> Decimal {
        let result = try await success(expression, context: context)
        guard case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected decimal for \(expression)")
            throw CalculatorUserFacingError(message: "Expected decimal")
        }
        return value
    }

    @Test("Previous answer aliases and typed unit reuse")
    func previousResults() async throws {
        let numeric = context(previousAnswer: 10, previousValue: .decimal(10))
        #expect(try await decimal("ans", context: numeric) == 10)
        #expect(try await decimal("answer", context: numeric) == 10)
        #expect(try await decimal("previous", context: numeric) == 10)
        #expect(try await decimal("last result", context: numeric) == 10)
        #expect(try await decimal("ans * 2", context: numeric) == 20)
        #expect(try await decimal("previous + 15%", context: numeric) == Decimal(string: "11.5"))

        let measurement = CalculatorMeasurementValue(value: 5, unitIdentifier: "foot", unitSymbol: "ft", dimension: .length)
        let converted = try await success("convert ans to meters", context: context(previousValue: .measurement(measurement)))
        guard case .measurement(let value) = converted.primaryValue else {
            Issue.record("Expected prior measurement conversion")
            return
        }
        #expect(abs(value.value - 1.524) < 0.000_001)
    }

    @Test("Assignments return typed session metadata")
    func assignments() async throws {
        let x = try await success("x = 25", context: context())
        #expect(x.metadata.assignedVariableName == "x")
        #expect(x.metadata.assignedVariable == CalculatorVariable(value: 25))
        #expect(try await decimal("x * 4", context: context(variables: ["x": .init(value: 25)])) == 100)

        let tax = try await success("tax = 7%", context: context())
        #expect(tax.metadata.assignedVariable == CalculatorVariable(value: Decimal(string: "0.07") ?? 0, isPercentage: true))
        #expect(try await decimal("100 + tax", context: context(variables: ["tax": .init(value: Decimal(string: "0.07") ?? 0, isPercentage: true)])) == 107)

        let subtotal = try await success("save 84.50 as subtotal", context: context())
        #expect(subtotal.metadata.assignedVariableName == "subtotal")
        #expect(try await decimal("subtotal + 15% tip", context: context(variables: ["subtotal": .init(value: Decimal(string: "84.5") ?? 0)])) == Decimal(string: "97.175"))

        let rate = try await success("set hourly rate to 25", context: context())
        #expect(rate.metadata.assignedVariableName == "hourly rate")
        #expect(try await decimal("hourly rate * 40", context: context(variables: ["hourly rate": .init(value: 25)])) == 1_000)
        #expect(try await decimal("pi * radius^2", context: context(variables: ["radius": .init(value: 5)])) > 78.53)
        let radius = try await success("radius = 5", context: context())
        #expect(radius.metadata.assignedVariableName == "radius")
    }

    @Test("Incomplete input remains incomplete", arguments: [
        "sqrt(", "20% of", "100 USD in", "3 days from", "5pm New York in",
        "interest paid in first year", "principal paid after 24 payments",
    ])
    func incomplete(expression: String) async {
        let outcome = await service.evaluate(expression, context: context())
        #expect(outcome == .incomplete, "Expected incomplete for \(expression), got \(outcome)")
    }

    @Test("Live arithmetic and conversion prefixes return predicted previews", arguments: ["2 +", "10 *", "5 feet to"])
    func predictedPrefix(expression: String) async {
        let outcome = await service.evaluate(expression, context: context())
        guard case .success(let result) = outcome else { Issue.record("Expected preview for \(expression), got \(outcome)"); return }
        #expect(result.suggestion != nil)
    }

    @Test("Invalid arithmetic and domains fail", arguments: [
        "2 ++ * 3", "10 / / 2", "2 + )", "sqrt()",
        "10 / 0", "0 / 0", "5 mod 0", "sqrt(-1)", "ln(0)", "ln(-5)", "asin(2)", "factorial(-3)",
    ])
    func invalidArithmetic(expression: String) async {
        let outcome = await service.evaluate(expression, context: context())
        guard case .failure = outcome else {
            Issue.record("Expected failure for \(expression), got \(outcome)")
            return
        }
    }

    @Test("Missing closing delimiter is previewed")
    func missingDelimiterPreview() async {
        let outcome = await service.evaluate("((2 + 3)", context: context())
        guard case .success(let result) = outcome else { Issue.record("Expected inferred delimiter preview"); return }
        #expect(result.formattedPrimaryValue == "5")
        #expect(result.suggestion?.completedInput == "((2 + 3))")
    }

    @Test("Unit, currency, and zone ambiguity is not guessed")
    func ambiguities() async {
        for expression in ["5 meters in kilograms", "100 Celsius in miles", "10 seconds to dollars", "5 m", "10 oz", "1 gal", "5 ton", "20 C", "100 pesos in dollars", "100 kr to USD", "5pm CST in London", "10am IST in New York", "8pm BST in Tokyo"] {
            let outcome = await service.evaluate(expression, context: context())
            guard case .failure = outcome else {
                Issue.record("Expected ambiguity/failure for \(expression), got \(outcome)")
                continue
            }
        }
        let dollar = await service.evaluate("$100 in euros", context: context(locale: Locale(identifier: "en_001")))
        guard case .failure = dollar else { Issue.record("Expected locale-neutral dollar ambiguity"); return }
    }

    @Test("Locale-visible standalone dates and invalid dates")
    func dates() async throws {
        let us = try await success("03/04/2026", context: context(locale: Locale(identifier: "en_US")))
        let gb = try await success("03/04/2026", context: context(locale: Locale(identifier: "en_GB")))
        #expect(us.formattedPrimaryValue.contains("March 4"))
        #expect(gb.formattedPrimaryValue.contains("3 April"))
        let partial = try await success("01/02", context: context(locale: Locale(identifier: "en_US")))
        #expect(partial.metadata.notes.contains { $0.contains("en_US") })
        _ = try await success("next Friday", context: context())
        _ = try await success("July 1", context: context())

        for expression in ["February 30", "April 31", "February 29, 2025", "13/40/2026"] {
            let outcome = await service.evaluate(expression, context: context())
            guard case .failure = outcome else {
                Issue.record("Expected invalid-date failure for \(expression), got \(outcome)")
                continue
            }
        }
    }

    @Test("Symbolic operations report unsupported")
    func unsupported() async {
        for expression in ["integrate x^2", "differentiate sin(x)", "solve a complex symbolic system"] {
            let outcome = await service.evaluate(expression, context: context())
            guard case .failure(let error) = outcome else {
                Issue.record("Expected unsupported failure for \(expression), got \(outcome)")
                continue
            }
            #expect(error.message.contains("not supported"))
        }
    }
}
