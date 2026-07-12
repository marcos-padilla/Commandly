import Foundation
import Testing
@testable import CalculatorKit

@Suite("CalculatorKit", .serialized)
struct CalculatorKitTests {
    private let service = CalculatorService()
    private let fixedNow = Date(timeIntervalSince1970: 1_735_689_600) // 2024-12-31 12:00:00 UTC-ish

    private func context(
        angleMode: CalculatorAngleMode = .radians,
        previousAnswer: Decimal? = nil,
        provider: (any ExchangeRateProviding)? = nil
    ) -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return CalculatorEvaluationContext(
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: TimeZone(identifier: "UTC") ?? .gmt,
            now: fixedNow,
            angleMode: angleMode,
            previousAnswer: previousAnswer,
            exchangeRateProvider: provider
        )
    }

    private func successValue(_ outcome: CalculatorEvaluationOutcome) throws -> CalculatorResult {
        guard case .success(let result) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            throw CalculatorUserFacingError(message: "not success")
        }
        return result
    }

    private func decimal(from outcome: CalculatorEvaluationOutcome) throws -> Decimal {
        let result = try successValue(outcome)
        guard case .decimal(let value) = result.primaryValue else {
            Issue.record("Expected decimal primary value")
            throw CalculatorUserFacingError(message: "not decimal")
        }
        return value
    }

    // MARK: - Classification negatives

    @Test("Non-calculator phrases")
    func nonCalculatorPhrases() async {
        let samples = [
            "Photoshop 2026",
            "Open invoice 1234",
            "Customer 100 Main Street",
            "Command 2",
            "File version 3",
            "Safari",
        ]
        for sample in samples {
            let outcome = await service.evaluate(sample, context: context())
            #expect(outcome == .notCalculator, "Expected notCalculator for \(sample)")
        }
    }

    // MARK: - Lexer / parser / arithmetic

    @Test("Basic arithmetic and precedence")
    func arithmeticPrecedence() async throws {
        #expect(try decimal(from: await service.evaluate("2 + 2", context: context())) == 4)
        #expect(try decimal(from: await service.evaluate("15 * 4 + 10", context: context())) == 70)
        #expect(try decimal(from: await service.evaluate("(25 + 5) * 3", context: context())) == 90)
        #expect(try decimal(from: await service.evaluate("2 + 3 * 4", context: context())) == 14)
        #expect(try decimal(from: await service.evaluate("1,250 / 5", context: context())) == 250)
    }

    @Test("-5^2 is -(5^2) = -25")
    func unaryMinusVsPower() async throws {
        // Documented: unary applies outside exponentiation.
        #expect(try decimal(from: await service.evaluate("-5^2", context: context())) == -25)
        #expect(try decimal(from: await service.evaluate("(-5)^2", context: context())) == 25)
    }

    @Test("2^3^2 is right-associative = 512")
    func rightAssociativePower() async throws {
        #expect(try decimal(from: await service.evaluate("2^3^2", context: context())) == 512)
        #expect(try decimal(from: await service.evaluate("2^10", context: context())) == 1024)
    }

    @Test("Implicit multiplication")
    func implicitMultiplication() async throws {
        #expect(try decimal(from: await service.evaluate("2(3 + 4)", context: context())) == 14)
        let threePi = try decimal(from: await service.evaluate("3pi", context: context()))
        #expect(threePi > 9.4 && threePi < 9.5)
        #expect(try decimal(from: await service.evaluate("2sqrt(9)", context: context())) == 6)
    }

    @Test("Decimal precision 0.1 + 0.2")
    func decimalPrecision() async throws {
        #expect(try decimal(from: await service.evaluate("0.1 + 0.2", context: context())) == Decimal(string: "0.3"))
    }

    @Test("Division by zero")
    func divisionByZero() async {
        let outcome = await service.evaluate("2 / 0", context: context())
        guard case .failure(let error) = outcome else {
            Issue.record("Expected failure")
            return
        }
        #expect(error.message.contains("zero"))
    }

    // MARK: - Scientific

    @Test("Scientific functions")
    func scientificFunctions() async throws {
        #expect(try decimal(from: await service.evaluate("sqrt(144)", context: context())) == 12)
        #expect(try decimal(from: await service.evaluate("cbrt(27)", context: context())) == 3)
        #expect(try decimal(from: await service.evaluate("abs(-7)", context: context())) == 7)
        #expect(try decimal(from: await service.evaluate("log10(1000)", context: context())) == 3)
        #expect(try decimal(from: await service.evaluate("max(1, 5, 3)", context: context())) == 5)
        #expect(try decimal(from: await service.evaluate("min(1, 5, 3)", context: context())) == 1)
        #expect(try decimal(from: await service.evaluate("round(10.456, 2)", context: context())) == Decimal(string: "10.46"))

        let sinPiOver2 = try decimal(from: await service.evaluate("sin(pi / 2)", context: context(angleMode: .radians)))
        #expect(sinPiOver2 > 0.999 && sinPiOver2 < 1.001)

        let sin90 = try decimal(from: await service.evaluate("sin(90)", context: context(angleMode: .degrees)))
        #expect(sin90 > 0.999 && sin90 < 1.001)
    }

    @Test("Invalid scientific domain")
    func scientificDomain() async {
        let outcome = await service.evaluate("sqrt(-1)", context: context())
        guard case .failure = outcome else {
            Issue.record("Expected domain failure")
            return
        }
    }

    // MARK: - Percentages

    @Test("Percentage semantics")
    func percentages() async throws {
        #expect(try decimal(from: await service.evaluate("20% of 350", context: context())) == 70)
        #expect(try decimal(from: await service.evaluate("350 * 20%", context: context())) == 70)
        #expect(try decimal(from: await service.evaluate("350 + 15%", context: context())) == Decimal(string: "402.5"))
        #expect(try decimal(from: await service.evaluate("350 - 15%", context: context())) == Decimal(string: "297.5"))

        let tip = try successValue(await service.evaluate("15% tip on 84.50", context: context()))
        #expect(try decimal(from: .success(tip)) == Decimal(string: "12.675"))
        #expect(tip.metadata.total == Decimal(string: "97.175"))
        #expect(tip.metadata.baseAmount == Decimal(string: "84.5") || tip.metadata.baseAmount == Decimal(string: "84.50"))

        let tax = try successValue(await service.evaluate("8.5% tax on 120", context: context()))
        #expect(tax.metadata.percentageAmount == Decimal(string: "10.2"))
        #expect(tax.metadata.total == Decimal(string: "130.2"))

        let discount = try successValue(await service.evaluate("20% discount from 75", context: context()))
        #expect(discount.metadata.percentageAmount == 15)
        #expect(discount.metadata.total == 60)
    }

    // MARK: - Units

    @Test("Unit conversions")
    func units() async throws {
        let feet = try successValue(await service.evaluate("5 feet in meters", context: context()))
        guard case .measurement(let m) = feet.primaryValue else {
            Issue.record("Expected measurement")
            return
        }
        #expect(m.value > 1.52 && m.value < 1.53)
        #expect(m.dimension == .length)

        let temp = try successValue(await service.evaluate("32 fahrenheit in celsius", context: context()))
        guard case .measurement(let t) = temp.primaryValue else {
            Issue.record("Expected measurement")
            return
        }
        #expect(abs(t.value) < 0.01)

        let duration = try successValue(await service.evaluate("2 hours 30 minutes in minutes", context: context()))
        guard case .measurement(let d) = duration.primaryValue else {
            Issue.record("Expected measurement")
            return
        }
        #expect(d.value == 150)
    }

    // MARK: - Currency (fake provider only)

    @Test("Currency conversion with fake provider")
    func currency() async throws {
        let provider = InMemoryExchangeRateProvider(rates: [
            "USD->EUR": Decimal(string: "0.92") ?? 0,
        ])
        let outcome = await service.evaluate("100 USD in EUR", context: context(provider: provider))
        let result = try successValue(outcome)
        guard case .currency(let value) = result.primaryValue else {
            Issue.record("Expected currency")
            return
        }
        #expect(value.code.rawValue == "EUR")
        #expect(value.amount == Decimal(string: "92"))
        #expect(result.metadata.exchangeRate == Decimal(string: "0.92"))
    }

    @Test("Currency provider failure does not fabricate")
    func currencyFailure() async {
        let provider = InMemoryExchangeRateProvider(rates: [:])
        let outcome = await service.evaluate("100 USD in EUR", context: context(provider: provider))
        guard case .failure(let error) = outcome else {
            Issue.record("Expected failure without fabricated rate")
            return
        }
        #expect(error.message.lowercased().contains("exchange") || error.message.lowercased().contains("unavailable"))
    }

    @Test("Ambiguous currency symbol")
    func ambiguousCurrencySymbol() async {
        let provider = InMemoryExchangeRateProvider(rates: ["USD->EUR": 1])
        let outcome = await service.evaluate("$100 in EUR", context: context(provider: provider))
        guard case .failure = outcome else {
            Issue.record("Expected ambiguous symbol failure")
            return
        }
    }

    // MARK: - Dates

    @Test("Date calculations with fixed now")
    func dates() async throws {
        let fromNow = try successValue(await service.evaluate("3 days from now", context: context()))
        guard case .date(let date) = fromNow.primaryValue else {
            Issue.record("Expected date")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fixedNow), to: calendar.startOfDay(for: date)).day
        #expect(days == 3)

        let until = try successValue(await service.evaluate("days until December 25", context: context()))
        guard case .decimal(let count) = until.primaryValue else {
            Issue.record("Expected day count")
            return
        }
        // Fixed now is 2024-12-31; yearless Dec 25 resolves to 2025-12-25.
        #expect(count > 350 && count < 370)
    }

    // MARK: - Time zones

    @Test("Time zone conversion")
    func timeZones() async throws {
        let outcome = await service.evaluate("5pm New York in Tokyo", context: context())
        let result = try successValue(outcome)
        guard case .timeZoneInstant(let value) = result.primaryValue else {
            Issue.record("Expected time zone instant")
            return
        }
        #expect(value.timeZoneIdentifier == "Asia/Tokyo")
        #expect(value.sourceTimeZoneIdentifier == "America/New_York")
    }

    @Test("Ambiguous time zone abbreviation fails clearly")
    func ambiguousTimeZone() async {
        let outcome = await service.evaluate("5pm CST in Tokyo", context: context())
        guard case .failure(let error) = outcome else {
            Issue.record("Expected ambiguous TZ failure")
            return
        }
        #expect(error.message.lowercased().contains("ambiguous"))
    }

    // MARK: - Incomplete / ans

    @Test("Incomplete expressions")
    func incomplete() async {
        for sample in ["2 +", "sqrt(", "100 USD in", "5 feet to", "3 days from"] {
            let outcome = await service.evaluate(sample, context: context())
            #expect(outcome == .incomplete, "Expected incomplete for \(sample)")
        }
    }

    @Test("Previous answer alias")
    func previousAnswer() async throws {
        let ctx = context(previousAnswer: 10)
        #expect(try decimal(from: await service.evaluate("ans * 2", context: ctx)) == 20)
        #expect(try decimal(from: await service.evaluate("answer + 5", context: ctx)) == 15)
    }

    // MARK: - Cancellation

    @Test("Cancellation is respected")
    func cancellation() async {
        let provider = HangingExchangeRateProvider()
        let task = Task {
            await service.evaluate("100 USD in EUR", context: context(provider: provider))
        }
        task.cancel()
        let outcome = await task.value
        // Cancelled currency fetch should surface as failure or incomplete — not success.
        if case .success = outcome {
            Issue.record("Cancelled evaluation must not succeed")
        }
    }

    // MARK: - Performance

    @Test("2+2 evaluates quickly")
    func performance() async throws {
        let start = ContinuousClock.now
        _ = try decimal(from: await service.evaluate("2+2", context: context()))
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(50))
    }

    // MARK: - Lexer details

    @Test("Lexer unicode operators via normalizer")
    func unicodeOperators() async throws {
        #expect(try decimal(from: await service.evaluate("6 × 7", context: context())) == 42)
        #expect(try decimal(from: await service.evaluate("10 ÷ 2", context: context())) == 5)
        #expect(try decimal(from: await service.evaluate("8 − 3", context: context())) == 5)
    }

    @Test("Natural language aliases")
    func naturalLanguage() async throws {
        #expect(try decimal(from: await service.evaluate("2 plus 2", context: context())) == 4)
        #expect(try decimal(from: await service.evaluate("10 times 3", context: context())) == 30)
        #expect(try decimal(from: await service.evaluate("20 percent of 350", context: context())) == 70)
    }
}

// MARK: - Test doubles

private struct HangingExchangeRateProvider: ExchangeRateProviding {
    func rate(from: CurrencyCode, to: CurrencyCode) async throws -> ExchangeRate {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        try Task.checkCancellation()
        return ExchangeRate(base: from, quote: to, rate: 1, timestamp: Date())
    }
}
