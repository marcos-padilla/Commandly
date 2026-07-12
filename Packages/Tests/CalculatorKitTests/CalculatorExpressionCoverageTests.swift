import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator expression coverage", .serialized)
struct CalculatorExpressionCoverageTests {
    private let service = CalculatorService()

    private func context(locale: String = "en_US") -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return CalculatorEvaluationContext(
            locale: Locale(identifier: locale),
            calendar: calendar,
            timeZone: .gmt,
            now: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }

    private func value(_ expression: String, locale: String = "en_US") async throws -> Decimal {
        let outcome = await service.evaluate(expression, context: context(locale: locale))
        guard case .success(let result) = outcome, case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected decimal success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected decimal success")
        }
        return value
    }

    @Test("Arithmetic aliases, precedence, grouping, and unary operators", arguments: [
        ("2 + 2", Decimal(4)), ("10 - 4", Decimal(6)), ("6 * 8", Decimal(48)),
        ("20 / 5", Decimal(4)), ("20 ÷ 5", Decimal(4)), ("6 × 8", Decimal(48)),
        ("7 x 9", Decimal(63)), ("10 plus 5", Decimal(15)), ("20 minus 8", Decimal(12)),
        ("4 times 7", Decimal(28)), ("30 divided by 6", Decimal(5)), ("30 over 6", Decimal(5)),
        ("2 + 3 * 4", Decimal(14)), ("2 * 3 + 4", Decimal(10)), ("10 - 8 / 2", Decimal(6)),
        ("(2 + 3) * 4", Decimal(20)), ("2 * (5 + 6)", Decimal(22)),
        ("open parenthesis 2 plus 3 close parenthesis times 4", Decimal(20)),
        ("-5 + 10", Decimal(5)), ("10 + -5", Decimal(5)), ("10 - -5", Decimal(15)),
        ("-10 * -2", Decimal(20)), ("-(5 + 3)", Decimal(-8)), ("-(-10)", Decimal(10)),
        ("--5", Decimal(5)), ("-5^2", Decimal(-25)), ("(-5)^2", Decimal(25)),
    ])
    func arithmetic(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Written English numbers", arguments: [
        ("ten plus ten", Decimal(20)),
        ("twenty-one plus nine", Decimal(30)),
        ("one hundred plus twenty five", Decimal(125)),
        ("one hundred and five times two", Decimal(210)),
        ("two thousand plus thirty", Decimal(2_030)),
        ("one million divided by four", Decimal(250_000)),
        ("three point five plus one point two five", Decimal(string: "4.75")!),
        ("negative five plus ten", Decimal(5)),
        ("sqrt(one hundred forty four)", Decimal(12)),
        ("fifty percent of two hundred", Decimal(100)),
    ])
    func writtenNumbers(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Decimal, grouping, and locale forms", arguments: [
        (".5 + .25", "en_US", Decimal(string: "0.75")!),
        ("5. + 2", "en_US", Decimal(7)),
        ("1,000,000 / 4", "en_US", Decimal(250_000)),
        ("1 000 + 500", "en_US", Decimal(1_500)),
        ("1'000 + 500", "en_US", Decimal(1_500)),
        ("1,5 + 2,5", "de_DE", Decimal(4)),
        ("1.250,50 + 200,25", "de_DE", Decimal(string: "1450.75")!),
        ("1,250.50 + 200.25", "en_US", Decimal(string: "1450.75")!),
    ])
    func localizedNumbers(expression: String, locale: String, expected: Decimal) async throws {
        #expect(try await value(expression, locale: locale) == expected)
    }

    @Test("Powers, roots, constants, and scientific notation", arguments: [
        ("2^8", Decimal(256)), ("2 ** 8", Decimal(256)), ("2 to the power of 8", Decimal(256)),
        ("2 raised to 8", Decimal(256)), ("10 squared", Decimal(100)), ("5 cubed", Decimal(125)),
        ("2^3^2", Decimal(512)), ("(2^3)^2", Decimal(64)), ("10^-2", Decimal(string: "0.01")!),
        ("sqrt(144)", Decimal(12)), ("square root of 144", Decimal(12)), ("√144", Decimal(12)),
        ("√(25 + 11)", Decimal(6)), ("cbrt(27)", Decimal(3)), ("cube root of 27", Decimal(3)),
        ("nthroot(32, 5)", Decimal(2)), ("root(81, 4)", Decimal(3)),
        ("1e3", Decimal(1_000)), ("1E3", Decimal(1_000)), ("2.5e6", Decimal(2_500_000)),
        ("3e-4", Decimal(string: "0.0003")!), ("1.2 × 10^5", Decimal(120_000)),
        ("10²", Decimal(100)), ("10³", Decimal(1_000)),
    ])
    func scientificForms(expression: String, expected: Decimal) async throws {
        let actual = try await value(expression)
        let difference = actual > expected ? actual - expected : expected - actual
        #expect(difference < Decimal(string: "0.0000000001")!)
    }

    @Test("Modulo, absolute values, factorials, fractions, and mixed numbers", arguments: [
        ("10 % 3", Decimal(1)), ("10 mod 3", Decimal(1)), ("10 modulo 3", Decimal(1)),
        ("abs(-25)", Decimal(25)), ("absolute value of -25", Decimal(25)), ("|-25|", Decimal(25)),
        ("5!", Decimal(120)), ("10!", Decimal(3_628_800)), ("factorial(5)", Decimal(120)),
        ("factorial of 6", Decimal(720)), ("(3 + 2)!", Decimal(120)),
        ("3/4 + 1/4", Decimal(1)), ("one half", Decimal(string: "0.5")!),
        ("three quarters", Decimal(string: "0.75")!), ("two thirds", Decimal(2) / Decimal(3)),
        ("1 and 1/2", Decimal(string: "1.5")!), ("2 1/4", Decimal(string: "2.25")!),
        ("three and a half", Decimal(string: "3.5")!), ("½ + ¼", Decimal(string: "0.75")!),
    ])
    func discreteAndFractionForms(expression: String, expected: Decimal) async throws {
        let actual = try await value(expression)
        #expect(actual == expected, "Expected \(expected), got \(actual)")
    }

    @Test("Rounding and aggregate functions", arguments: [
        ("round(10.456)", Decimal(10)), ("round(10.456, 2)", Decimal(string: "10.46")!),
        ("floor(10.9)", Decimal(10)), ("ceil(10.1)", Decimal(11)), ("truncate(10.999)", Decimal(10)),
        ("min(5, 3, 8)", Decimal(3)), ("max(5, 3, 8)", Decimal(8)), ("clamp(15, 0, 10)", Decimal(10)),
        ("sum(1, 2, 3, 4)", Decimal(10)), ("average(10, 20, 30)", Decimal(20)),
        ("mean(10, 20, 30)", Decimal(20)), ("median(1, 5, 9)", Decimal(5)),
        ("mode(1, 2, 2, 3)", Decimal(2)), ("product(2, 3, 4)", Decimal(24)),
        ("range(1, 10)", Decimal(9)), ("variance(1, 2, 3)", Decimal(2) / Decimal(3)),
        ("gcd(24, 36)", Decimal(12)), ("lcm(12, 18)", Decimal(36)),
        ("nCr(10, 3)", Decimal(120)), ("nPr(10, 3)", Decimal(720)),
    ])
    func functions(expression: String, expected: Decimal) async throws {
        let actual = try await value(expression)
        let difference = actual > expected ? actual - expected : expected - actual
        #expect(difference < Decimal(string: "0.000000001")!)
    }

    @Test("Percentage semantics and command prefixes", arguments: [
        ("20%", Decimal(string: "0.2")!), ("20% of 350", Decimal(70)),
        ("350 * 20%", Decimal(70)), ("350 + 15%", Decimal(string: "402.5")!),
        ("350 - 15%", Decimal(string: "297.5")!), ("what is 25 times 8", Decimal(200)),
        ("calculate 25 * 8", Decimal(200)), ("calc 2+2", Decimal(4)),
        ("increase 350 by 15%", Decimal(string: "402.5")!),
        ("add 15 percent to 350", Decimal(string: "402.5")!),
        ("decrease 350 by 15%", Decimal(string: "297.5")!),
        ("subtract 15 percent from 350", Decimal(string: "297.5")!),
        ("percentage change from 80 to 100", Decimal(25)),
        ("percent decrease from 100 to 80", Decimal(-20)),
        ("25 is what percent of 100", Decimal(25)),
        ("what percent of 100 is 25", Decimal(25)),
    ])
    func percentagesAndPrefixes(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Natural scientific and discrete function phrases", arguments: [
        ("fifth root of 32", Decimal(2)), ("remainder of 10 divided by 3", Decimal(1)),
        ("17 remainder 5", Decimal(2)), ("minimum of 5, 3 and 8", Decimal(3)),
        ("maximum of 10, 20 and 15", Decimal(20)), ("natural log of 1", Decimal(0)),
        ("log base 2 of 1024", Decimal(10)), ("base 10 log of 1000", Decimal(3)),
        ("10 choose 3", Decimal(120)), ("10 permutations of 3", Decimal(720)),
        ("greatest common divisor of 24 and 36", Decimal(12)),
        ("least common multiple of 12 and 18", Decimal(36)),
        ("round 10.456 to 2 decimal places", Decimal(string: "10.46")!),
    ])
    func naturalFunctions(expression: String, expected: Decimal) async throws {
        let actual = try await value(expression)
        let difference = actual > expected ? actual - expected : expected - actual
        #expect(difference < Decimal(string: "0.000000001")!)
    }

    @Test("Unary minus applies after factorial")
    func unaryMinusFactorial() async throws {
        #expect(try await value("-5!") == -120)
    }

    @Test("Invalid domains and unsafe factorials fail", arguments: ["5.5!", "100000!", "sqrt(-1)", "ln(0)", "asin(2)"])
    func invalidDomains(expression: String) async {
        let outcome = await service.evaluate(expression, context: context())
        guard case .failure = outcome else {
            Issue.record("Expected failure for \(expression), got \(outcome)")
            return
        }
    }
}
