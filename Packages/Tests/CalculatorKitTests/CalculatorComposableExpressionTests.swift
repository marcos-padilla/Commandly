import Foundation
import Testing
@testable import CalculatorKit

@Suite("Composable calculator expressions", .serialized)
struct CalculatorComposableExpressionTests {
    private let service = CalculatorService()

    private func context(locale: String = "en_US") -> CalculatorEvaluationContext {
        CalculatorEvaluationContext(locale: Locale(identifier: locale))
    }

    private func value(_ expression: String, locale: String = "en_US") async throws -> Decimal {
        let outcome = await service.evaluate(expression, context: context(locale: locale))
        guard case .success(let result) = outcome,
              case .decimal(let value) = result.primaryValue
        else {
            Issue.record("Expected decimal success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected decimal success")
        }
        return value
    }

    @Test("Percent-of accepts complete expressions on both sides", arguments: [
        ("3% of (4 plus 5)", Decimal(string: "0.27") ?? .zero),
        ("(2 + 3)% of (10 * 4)", Decimal(2)),
        ("10 + 50% of (2 + 6)", Decimal(14)),
        ("2 * (25% of (6 + 2))", Decimal(4)),
        ("50 percent of (20 minus 4) plus 2", Decimal(10)),
    ])
    func composablePercentOf(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Alternative grouping delimiters normalize to parentheses", arguments: [
        ("[2 + {3 * (4 + 1)}]", Decimal(17)),
        ("（2 ＋ 3） × 4", Decimal(20)),
        ("open bracket 2 plus 3 close bracket times 4", Decimal(20)),
        ("left parenthesis 2 plus 3 right parenthesis times 4", Decimal(20)),
        ("left brace 2 plus 3 right brace times 4", Decimal(20)),
        ("2(3 + 4)(5 - 2)", Decimal(42)),
    ])
    func groupingVariants(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Natural unary functions compose with surrounding terms", arguments: [
        ("2 plus square root of 9", Decimal(5)),
        ("3 times absolute value of -4", Decimal(12)),
        ("1 plus factorial of 5", Decimal(121)),
        ("2 + sqrt (9 + 7)", Decimal(6)),
        ("10 minus natural log of 1", Decimal(10)),
    ])
    func composablePrefixFunctions(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Function lists accept comma, conjunction, and semicolon separators", arguments: [
        ("sum(1; 2; 3; 4)", Decimal(10)),
        ("sum(1, 2 and 3, 4)", Decimal(10)),
        ("max(2 + 3; 4 * 2; 7)", Decimal(8)),
        ("average(1; 2; 6)", Decimal(3)),
        ("sum of 1, 2, 3 and 4", Decimal(10)),
        ("sum of 1, 2, 3, and 4", Decimal(10)),
        ("product of 2, 3 and 4", Decimal(24)),
        ("product of two, three and four", Decimal(24)),
        ("average of (2 + 4), 8 and 10", Decimal(8)),
    ])
    func listSeparators(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Additional pasted operator and numeric separator forms", arguments: [
        ("1_000 + 2_500", Decimal(3_500)),
        ("10 ∕ 2", Decimal(5)),
        ("6 ∗ 7", Decimal(42)),
        ("20 ％ of 50", Decimal(10)),
        ("［2 ＋ 3］×｛4 － 1｝", Decimal(15)),
        ("2¹⁰", Decimal(1_024)),
        ("10⁻²", Decimal(string: "0.01") ?? .zero),
        ("⅝ + ⅜", Decimal(1)),
        ("1⅝ + ⅜", Decimal(2)),
    ])
    func pastedSyntax(expression: String, expected: Decimal) async throws {
        #expect(try await value(expression) == expected)
    }

    @Test("Semicolons disambiguate localized decimal and argument separators")
    func localizedListSeparators() async throws {
        #expect(try await value("sum(1,5; 2,5; 3)", locale: "de_DE") == 7)
        #expect(try await value("sum(1,200; 300)", locale: "en_US") == 1_500)
    }
}
