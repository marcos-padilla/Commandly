import Foundation
import Testing
@testable import CalculatorKit

@Suite("Prompt catalog core expression coverage", .serialized)
struct CalculatorPromptCoreCoverageTests {
    private let service = CalculatorService()

    private var context: CalculatorEvaluationContext {
        CalculatorEvaluationContext(locale: Locale(identifier: "en_US"), angleMode: .radians)
    }

    @Test("Catalog arithmetic, grouping, decimals, powers, roots, and constants", arguments: [
        ("4 + 6 * 3 - 2", 20.0), ("100 / 5 + 3 * 4", 32.0),
        ("((2 + 3) * 4) / 2", 10.0), ("10 / (2 + 3)", 2.0),
        ("(10 - 2) * (4 + 1)", 40.0), ("((10 + 5) * (8 - 3)) / 5", 15.0),
        ("-5", -5.0), ("+5", 5.0), ("-(5^2)", -25.0), ("abs(5 - 12)", 7.0),
        ("0.5 + 0.25", 0.75), ("10.75 * 3", 32.25),
        ("0.0001 + 0.0002", 0.0003), ("1.23456789 / 3", 0.41152263),
        ("1,000 + 250", 1_250.0), ("10,000 * 2", 20_000.0),
        ("2^(3^2)", 512.0),
        ("4^0.5", 2.0), ("27^(1/3)", 3.0), ("1/2", 0.5),
        ("5 divided by 8", 0.625), ("1 1/2 + 2 1/4", 3.75),
        ("3 and 3/4", 3.75), ("two and one half", 2.5), ("5 2/3 * 3", 17.0),
        ("pi", Double.pi), ("π", Double.pi), ("2 * pi", 2 * Double.pi),
        ("2π", 2 * Double.pi), ("pi^2", Double.pi * Double.pi),
        ("e", M_E), ("e^2", M_E * M_E), ("tau", 2 * Double.pi),
        ("τ", 2 * Double.pi), ("phi", (1 + sqrt(5)) / 2),
        ("golden ratio", (1 + sqrt(5)) / 2), ("sqrt2", sqrt(2)),
        ("ln2", log(2)), ("ln10", log(10)), ("6.022e23", 6.022e23),
        ("1.602176634e-19", 1.602176634e-19),
    ] as [(String, Double)])
    func coreNumericExpression(expression: String, expected: Double) async throws {
        let actual = try await decimalValue(expression)
        let tolerance = max(abs(expected) * 1e-12, 1e-12)
        #expect(abs(actual - expected) <= tolerance, "\(expression) produced \(actual), expected \(expected)")
    }

    @Test("Catalog rounding, scientific, aggregation, and combinatorics", arguments: [
        ("round 125 to the nearest 10", 130.0),
        ("round 1249 to the nearest hundred", 1_200.0),
        ("10.456 rounded to 2 digits", 10.46),
        ("round 12345 to 3 significant figures", 12_300.0),
        ("12345 to 3 sig figs", 12_300.0),
        ("0.00123456 to 3 significant digits", 0.00123),
        ("sin(0)", 0.0), ("cos(0)", 1.0), ("tan(45 degrees)", 1.0),
        ("cos(180 deg)", -1.0), ("tan(1 rad)", tan(1)),
        ("asin(1)", asin(1)), ("acos(0)", acos(0)), ("atan(1)", atan(1)),
        ("atan2(10, 5)", atan2(10, 5)), ("sinh(1)", sinh(1)),
        ("cosh(1)", cosh(1)), ("tanh(1)", tanh(1)), ("asinh(1)", asinh(1)),
        ("acosh(2)", acosh(2)), ("atanh(0.5)", atanh(0.5)),
        ("ln(10)", log(10)), ("log(100)", log(100)),
        ("log2(1024)", 10.0), ("log(8, 2)", 3.0),
        ("natural log of 10", log(10)), ("exp(1)", M_E), ("e^5", pow(M_E, 5)),
        ("10^6", 1_000_000.0), ("pow(2, 10)", 1_024.0),
        ("2 raised to the tenth power", 1_024.0),
        ("standard deviation of 1, 2, 3", sqrt(2.0 / 3.0)),
        ("stddev(1, 2, 3)", sqrt(2.0 / 3.0)),
        ("C(10, 3)", 120.0), ("P(10, 3)", 720.0),
    ] as [(String, Double)])
    func scientificAndRounding(expression: String, expected: Double) async throws {
        let actual = try await decimalValue(expression)
        #expect(abs(actual - expected) <= max(abs(expected) * 1e-10, 1e-10), "\(expression) produced \(actual)")
    }

    @Test("Catalog comparisons", arguments: [
        ("is 10 greater than 5", "true"), ("10 > 5", "true"),
        ("10 >= 10", "true"), ("5 < 8", "true"), ("5 <= 5", "true"),
        ("10 == 10", "true"), ("10 != 5", "true"),
    ])
    func comparisons(expression: String, expected: String) async throws {
        #expect(try await textValue(expression) == expected)
    }

    @Test("Catalog percentage, tax, discount, markup, and reverse percentage", arguments: [
        ("350 times 20 percent", 70.0), ("15% of 84.50", 12.675),
        ("350 plus 15%", 402.5), ("reduce 350 by 15%", 297.5),
        ("percent increase from 80 to 100", 25.0),
        ("80 to 100 percent change", 25.0),
        ("what percentage increase is 80 to 100", 25.0),
        ("25 out of 100 as a percentage", 25.0),
        ("45 is what percentage of 60", 75.0),
        ("120 is 20% more than what", 100.0), ("80 is 20% less than what", 100.0),
        ("what number plus 15% equals 230", 200.0),
        ("what original amount becomes 115 after a 15% increase", 100.0),
        ("20 percent tip on 100", 20.0), ("tip 18% on 65", 11.7),
        ("84.50 plus 15% tip", 97.175),
        ("split 84.50 plus 15% tip between 4 people", 24.29375),
        ("7% tax on 100", 7.0), ("add 8.5% sales tax to 120", 130.2),
        ("120 plus 8.5 percent tax", 130.2), ("remove 7% tax from 107", 100.0),
        ("price before 7% tax if total is 107", 100.0),
        ("20% discount on 75", 15.0), ("75 minus 20%", 60.0),
        ("take 20 percent off 75", 60.0), ("price after 15% discount on 120", 102.0),
        ("original price before a 25% discount if sale price is 90", 120.0),
        ("add 30% markup to 100", 130.0), ("100 with a 30% markup", 130.0),
        ("price with 40% gross margin on a cost of 60", 100.0),
        ("profit margin if cost is 70 and price is 100", 30.0),
        ("markup percentage from 70 to 100", 42.857142857142854),
    ])
    func percentageBusiness(expression: String, expected: Double) async throws {
        let actual = try await decimalValue(expression)
        #expect(abs(actual - expected) <= 1e-9, "\(expression) produced \(actual)")
    }

    @Test("Catalog ratios, proportions, and elementary algebra", arguments: [
        ("if 3 costs 12, how much do 5 cost", 20.0),
        ("3 is to 12 as 5 is to what", 20.0), ("3/12 = 5/x", 20.0),
        ("solve 3:12 = 5:x", 20.0), ("x + 5 = 10", 5.0),
        ("2x = 20", 10.0), ("2x + 4 = 16", 6.0),
        ("3(x + 2) = 21", 5.0), ("solve x + 10 = 25", 15.0),
        ("solve 5x - 3 = 22", 5.0),
    ])
    func proportionsAndLinearAlgebra(expression: String, expected: Double) async throws {
        #expect(abs(try await decimalValue(expression) - expected) <= 1e-10)
    }

    @Test("Catalog ratio, roots, systems, and prime text results", arguments: [
        ("10:2", "5:1"), ("10 to 2 ratio", "5:1"),
        ("simplify 100:25", "4:1"), ("ratio of 50 to 20", "5:2"),
        ("split 100 in a 3:2 ratio", "60 and 40"),
        ("x^2 - 5x + 6 = 0", "3, 2"),
        ("solve x^2 + 4x + 4 = 0", "-2"), ("roots of x^2 - 9", "3, -3"),
        ("quadratic 2x^2 + 3x - 2", "0.5, -2"),
        ("x + y = 10, x - y = 2", "x = 6, y = 4"),
        ("solve x + y = 5 and 2x - y = 4", "x = 3, y = 2"),
        ("is 97 prime", "true"), ("prime factors of 360", "2 × 2 × 2 × 3 × 3 × 5"),
        ("factorize 360", "2 × 2 × 2 × 3 × 3 × 5"),
    ])
    func structuredText(expression: String, expected: String) async throws {
        #expect(try await textValue(expression) == expected)
    }

    @Test("Catalog next-prime and random commands")
    func primeAndRandom() async throws {
        #expect(try await decimalValue("next prime after 100") == 101)
        #expect(try await textValue("list primes below 100").hasSuffix("97"))
        for expression in ["random number", "random number from 1 to 100", "random integer between 10 and 50", "random decimal between 0 and 1", "roll a die", "roll 2d6"] {
            let outcome = await service.evaluate(expression, context: context)
            guard case .success(let result) = outcome else { Issue.record("Expected success for \(expression), got \(outcome)"); continue }
            #expect(result.metadata.notes.contains(where: { $0.contains("Nondeterministic") }))
        }
        let coin = try await textValue("flip a coin")
        #expect(coin == "heads" || coin == "tails")
    }

    @Test("Adjacent bare numbers are not silently multiplied")
    func bareAdjacentNumbers() async {
        let outcome = await service.evaluate("2 3", context: context)
        if case .success = outcome { Issue.record("2 3 must not be treated as multiplication") }
    }

    @Test("Catalog period grouping uses the selected locale")
    func periodGroupingLocale() async throws {
        let german = CalculatorEvaluationContext(locale: Locale(identifier: "de_DE"))
        let outcome = await service.evaluate("1.000.000 + 250.000", context: german)
        guard case .success(let result) = outcome, case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected German grouped-number success, got \(outcome)")
            return
        }
        #expect(value == 1_250_000)
    }

    @Test("Missing tax base remains incomplete")
    func incompleteTax() async {
        #expect(await service.evaluate("price after 6% tax", context: context) == .incomplete)
    }

    private func decimalValue(_ expression: String) async throws -> Double {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome else {
            Issue.record("Expected success for \(expression), got \(outcome)")
            throw PromptCoverageError.failed(expression)
        }
        switch result.primaryValue {
        case .decimal(let value): return NSDecimalNumber(decimal: value).doubleValue
        case .double(let value): return value
        default:
            Issue.record("Expected numeric value for \(expression), got \(result.primaryValue)")
            throw PromptCoverageError.failed(expression)
        }
    }

    private func textValue(_ expression: String) async throws -> String {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome, case .text(let value) = result.primaryValue else {
            Issue.record("Expected text success for \(expression), got \(outcome)")
            throw PromptCoverageError.failed(expression)
        }
        return value
    }

    private enum PromptCoverageError: Error { case failed(String) }
}
