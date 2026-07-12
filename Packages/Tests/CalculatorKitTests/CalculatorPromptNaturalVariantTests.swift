import Foundation
import Testing
@testable import CalculatorKit

@Suite("Prompt catalog natural-language variant coverage", .serialized)
struct CalculatorPromptNaturalVariantTests {
    private let service = CalculatorService()
    private var context: CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)) ?? .distantPast
        return CalculatorEvaluationContext(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: .gmt, now: now)
    }

    @Test("Question, command, casing, spacing, and Unicode variants", arguments: [
        ("how much is 300 plus 15 percent", 345.0),
        ("what is the square root of 144", 12.0),
        ("how many days until December 25", 163.0),
        ("add 15% to 300", 345.0), ("subtract 20% from 80", 64.0),
        ("find the square root of 144", 12.0), ("Sin(PI / 2)", 1.0),
        ("SQRT(144)", 12.0), ("2 +2", 4.0), ("2+ 2", 4.0),
        ("2    +    2", 4.0), ("sqrt ( 144 )", 12.0),
        ("2 × 5", 10.0), ("20 ÷ 4", 5.0), ("10 − 3", 7.0),
        ("√81", 9.0), ("π × 2", 2 * Double.pi),
    ] as [(String, Double)])
    func variants(expression: String, expected: Double) async {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome else { Issue.record("Expected success for \(expression), got \(outcome)"); return }
        let actual: Double
        switch result.primaryValue {
        case .decimal(let value): actual = NSDecimalNumber(decimal: value).doubleValue
        default: Issue.record("Unexpected value for \(expression): \(result.primaryValue)"); return
        }
        #expect(abs(actual - expected) <= 1e-9)
    }

    @Test("Imperative time-zone form")
    func showTimeZone() async {
        let outcome = await service.evaluate("show 5pm New York time in Tokyo", context: context)
        guard case .success = outcome else { Issue.record("Expected time-zone success, got \(outcome)"); return }
        let clockOutcome = await service.evaluate("what time is 3 hours after 5pm", context: context)
        guard case .success = clockOutcome else { Issue.record("Expected question-form clock success, got \(clockOutcome)"); return }
    }
}
