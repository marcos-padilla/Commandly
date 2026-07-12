import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator currency coverage", .serialized)
struct CalculatorCurrencyCoverageTests {
    private let service = CalculatorService()
    private let provider = InMemoryExchangeRateProvider(rates: [
        "USD->EUR": Decimal(string: "0.92") ?? 0,
        "GBP->USD": Decimal(string: "1.25") ?? 0,
        "USD->CAD": Decimal(string: "1.35") ?? 0,
        "EUR->USD": Decimal(string: "1.10") ?? 0,
        "USD->JPY": 150,
        "CAD->MXN": 12,
    ])

    private func context(locale: String = "en_US") -> CalculatorEvaluationContext {
        CalculatorEvaluationContext(
            locale: Locale(identifier: locale),
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt,
            now: Date(timeIntervalSince1970: 1_735_689_600),
            exchangeRateProvider: provider
        )
    }

    private func currency(_ expression: String, locale: String = "en_US") async throws -> CalculatorCurrencyValue {
        let outcome = await service.evaluate(expression, context: context(locale: locale))
        guard case .success(let result) = outcome,
              case .currency(let value) = result.primaryValue
        else {
            Issue.record("Expected currency success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected currency success")
        }
        #expect(result.kind == .currencyConversion)
        return value
    }

    @Test("Currency names, symbols, compact forms, and casing", arguments: [
        ("100 USD in EUR", "en_US", "EUR", Decimal(92)),
        ("50 GBP to USD", "en_US", "USD", Decimal(string: "62.5")!),
        ("$100 in CAD", "en_US", "CAD", Decimal(135)),
        ("€50 to USD", "en_US", "USD", Decimal(55)),
        ("100 dollars in yen", "en_US", "JPY", Decimal(15_000)),
        ("100 US dollars to Japanese yen", "en_US", "JPY", Decimal(15_000)),
        ("250 CAD in MXN", "en_US", "MXN", Decimal(3_000)),
        ("100 usd to eur", "en_US", "EUR", Decimal(92)),
        ("100 USD TO EUR", "en_US", "EUR", Decimal(92)),
        ("100USD in EUR", "en_US", "EUR", Decimal(92)),
        ("100 usd eur", "en_US", "EUR", Decimal(92)),
        ("convert 100 USD to EUR", "en_US", "EUR", Decimal(92)),
        ("$100 in USD", "en_CA", "USD", Decimal(string: "74.074074074074074074074074074074074074")!),
    ])
    func forms(expression: String, locale: String, code: String, expected: Decimal) async throws {
        let actual = try await currency(expression, locale: locale)
        #expect(actual.code.rawValue == code)
        let difference = actual.amount > expected ? actual.amount - expected : expected - actual.amount
        #expect(difference < Decimal(string: "0.000000001")!)
    }

    @Test("Multiple-currency arithmetic", arguments: [
        ("100 USD + 50 EUR in USD", "USD", Decimal(155)),
        ("50 EUR + 20 GBP in USD", "USD", Decimal(80)),
    ])
    func arithmetic(expression: String, code: String, expected: Decimal) async throws {
        let actual = try await currency(expression)
        #expect(actual.code.rawValue == code)
        #expect(actual.amount == expected)
    }

    @Test("Division by a named exchange rate uses an explicit quote direction")
    func rateDivision() async throws {
        let actual = try await currency("100 USD divided by the EUR exchange rate")
        #expect(actual.code.rawValue == "EUR")
        let expected = Decimal(100) / (Decimal(string: "1.10") ?? 1)
        let difference = actual.amount > expected ? actual.amount - expected : expected - actual.amount
        #expect(difference < Decimal(string: "0.000000001")!)
    }

    @Test("Multiple-currency result records rate timestamp and source currencies")
    func arithmeticMetadata() async throws {
        let outcome = await service.evaluate("50 EUR + 20 GBP in USD", context: context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected multiple-currency success")
            return
        }
        #expect(result.metadata.fromCurrency == "EUR+GBP")
        #expect(result.metadata.toCurrency == "USD")
        #expect(result.metadata.rateTimestamp != nil)
        #expect(result.metadata.notes.contains { $0.contains("EUR/USD") && $0.contains("GBP/USD") })
    }

    @Test("Material currency ambiguity is not guessed", arguments: [
        ("$100 in EUR", "en_001"),
        ("100 pesos in USD", "en_US"),
        ("100 kr to USD", "en_US"),
    ])
    func ambiguity(expression: String, locale: String) async {
        let outcome = await service.evaluate(expression, context: context(locale: locale))
        guard case .failure(let error) = outcome else {
            Issue.record("Expected ambiguity failure for \(expression), got \(outcome)")
            return
        }
        #expect(error.message.lowercased().contains("ambiguous"))
    }
}
