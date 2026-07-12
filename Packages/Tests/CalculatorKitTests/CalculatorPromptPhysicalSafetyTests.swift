import Foundation
import Testing
@testable import CalculatorKit

@Suite("Prompt catalog physical-safety coverage", .serialized)
struct CalculatorPromptPhysicalSafetyTests {
    private let service = CalculatorService()
    private let context = CalculatorEvaluationContext(locale: Locale(identifier: "en_US"))

    @Test("Standalone luminous flux is parsed without inventing a lux conversion")
    func luminousFlux() async {
        let outcome = await service.evaluate("1000 lumens", context: context)
        guard case .success(let result) = outcome else { Issue.record("Expected luminous-flux quantity, got \(outcome)"); return }
        #expect(result.formattedPrimaryValue == "1000 lm")
        #expect(result.metadata.notes.contains { $0.contains("not converted") })
    }
}
