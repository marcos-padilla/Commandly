import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator finance coverage", .serialized)
struct CalculatorFinanceCoverageTests {
    private let service = CalculatorService()

    private func context(
        hoursPerWeek: Decimal = 40,
        weeksPerYear: Decimal = 52,
        overtimeMultiplier: Decimal = Decimal(string: "1.5") ?? 1.5
    ) -> CalculatorEvaluationContext {
        CalculatorEvaluationContext(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt,
            now: Date(timeIntervalSince1970: 1_735_689_600),
            workHoursPerWeek: hoursPerWeek,
            workWeeksPerYear: weeksPerYear,
            overtimeMultiplier: overtimeMultiplier
        )
    }

    private func result(
        _ expression: String,
        context: CalculatorEvaluationContext? = nil
    ) async throws -> CalculatorResult {
        let outcome = await service.evaluate(expression, context: context ?? self.context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected finance success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected finance success")
        }
        #expect(result.kind == .financial)
        return result
    }

    private func value(_ expression: String) async throws -> Double {
        let result = try await result(expression)
        guard case .decimal(let decimal) = result.primaryValue,
              let value = DecimalMath.toDouble(decimal)
        else {
            Issue.record("Expected decimal finance result for \(expression)")
            throw CalculatorUserFacingError(message: "Expected decimal finance result")
        }
        return value
    }

    @Test("Corpus finance formulas", arguments: [
        ("simple interest on 1000 at 5% for 3 years", 1_150.0, 0.000_001),
        ("1000 at 5 percent simple interest for 24 months", 1_100.0, 0.000_001),
        ("1000 at 5% compounded monthly for 10 years", 1_647.009_497_69, 0.000_1),
        ("compound 5000 annually at 7% for 20 years", 19_348.422_312_43, 0.001),
        ("future value of 10000 at 6% for 5 years", 13_382.255_776, 0.001),
        ("present value of 10000 in 5 years at 6%", 7_472.581_728_66, 0.001),
        ("PV of 500 monthly for 10 years at 5%", 47_140.675_164, 0.001),
        ("monthly payment on 300000 at 6.5% for 30 years", 1_896.204_070_48, 0.001),
        ("car payment for 25000 at 7% for 60 months", 495.029_963_51, 0.001),
        ("mortgage payment on 450000 with 20% down at 6.25% for 30 years", 2_216.581_921_54, 0.001),
        ("20% down on 450000", 90_000.0, 0.000_001),
        ("450000 with 10% down", 45_000.0, 0.000_001),
        ("loan amount after 15% down on 300000", 255_000.0, 0.000_001),
        ("remaining balance after 5 years on a 300000 loan at 6% for 30 years", 279_163.070_468, 0.01),
        ("how much to save monthly to reach 10000 in 2 years", 416.666_666_67, 0.000_1),
        ("monthly savings needed for 50000 in 5 years at 4%", 754.159_436_1, 0.001),
        ("return from 10000 growing to 12500", 25.0, 0.000_001),
        ("annualized return from 10000 to 15000 over 3 years", 14.471_424_26, 0.000_1),
        ("CAGR from 1 million to 2 million over 5 years", 14.869_835_5, 0.000_1),
        ("profit if revenue is 10000 and cost is 7500", 2_500.0, 0.000_001),
        ("profit margin on revenue 10000 and profit 2500", 25.0, 0.000_001),
        ("loss percentage from 100 to 80", 20.0, 0.000_001),
        ("break even units if fixed cost is 10000, price is 50 and variable cost is 20", 334.0, 0.000_001),
        ("break even revenue with fixed cost 5000 and margin 40%", 12_500.0, 0.000_001),
        ("25 per hour yearly", 52_000.0, 0.000_001),
        ("60000 salary hourly", 28.846_153_85, 0.000_1),
        ("5000 per month yearly", 60_000.0, 0.000_001),
        ("1200 per week annually", 62_400.0, 0.000_001),
        ("75000 annually monthly", 6_250.0, 0.000_001),
        ("40 hours at 25 plus 10 hours overtime", 1_375.0, 0.000_001),
        ("overtime pay for 8 hours at 20 per hour", 240.0, 0.000_001),
    ])
    func formula(expression: String, expected: Double, tolerance: Double) async throws {
        let actual = try await value(expression)
        #expect(abs(actual - expected) <= tolerance, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Loan metadata states exclusions and totals")
    func loanMetadata() async throws {
        let result = try await result("monthly payment on 300000 at 6.5% for 30 years")
        #expect(result.metadata.baseAmount == 300_000)
        #expect(result.metadata.total != nil)
        #expect(result.metadata.notes.contains { $0.contains("Excludes taxes") })
        #expect(result.metadata.notes.contains { $0.contains("Total interest") })
    }

    @Test("Pay and overtime assumptions are configurable")
    func configurableWorkAssumptions() async throws {
        let custom = context(hoursPerWeek: 35, weeksPerYear: 48, overtimeMultiplier: 2)
        let salary = try await result("25 per hour yearly", context: custom)
        let overtime = try await result("overtime pay for 8 hours at 20 per hour", context: custom)
        #expect(salary.primaryValue == .decimal(42_000))
        #expect(overtime.primaryValue == .decimal(320))
        #expect(overtime.metadata.notes.contains { $0.contains("2×") })
    }

    @Test("Invalid financial domains fail", arguments: [
        "monthly payment on 300000 at 6.5% for 0 years",
        "present value of 10000 in 5 years at -100%",
        "break even revenue with fixed cost 5000 and margin 0%",
    ])
    func invalidDomain(expression: String) async {
        let outcome = await service.evaluate(expression, context: context())
        guard case .failure = outcome else {
            Issue.record("Expected financial failure for \(expression), got \(outcome)")
            return
        }
    }
}
