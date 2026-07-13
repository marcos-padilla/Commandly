import Foundation
import SearchKit
import CalculatorKit

struct CalculatorHistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let expression: String
    let formattedValue: String
    let createdAt: Date
}

/// Search provider that evaluates calculator queries via CalculatorKit.
struct CalculatorSearchProvider: SearchProviding, Sendable {
    let id = BuiltInSearchProviderID.calculator
    private let calculator: any CalculatorEvaluating
    private let contextFactory: @Sendable () -> CalculatorEvaluationContext

    /// Score used so calculator answers pin above normal command/app matches.
    static let pinScore: Double = 1.05

    init(
        calculator: any CalculatorEvaluating = CalculatorService(),
        contextFactory: @escaping @Sendable () -> CalculatorEvaluationContext = {
            CalculatorEvaluationContext()
        }
    ) {
        self.calculator = calculator
        self.contextFactory = contextFactory
    }

    func search(_ query: SearchQuery) async throws -> SearchResult {
        try Task.checkCancellation()
        guard query.isEmpty == false else {
            return SearchResult(query: query, items: [])
        }

        let outcome = await calculator.evaluate(query.text, context: contextFactory())
        try Task.checkCancellation()

        switch outcome {
        case .notCalculator, .incomplete:
            return SearchResult(query: query, items: [])
        case .failure(let error):
            // Only surface unmistakable calculator-intent failures as a result row.
            let item = SearchItem(
                id: "calculator-error",
                title: error.message,
                subtitle: query.text,
                providerID: id,
                score: Self.pinScore - 0.01
            )
            return SearchResult(query: query, items: [item])
        case .success(let result):
            let subtitle: String
            if result.displayExpression.isEmpty {
                subtitle = result.originalInput
            } else {
                subtitle = result.displayExpression
            }
            let item = SearchItem(
                id: result.id.rawValue,
                title: result.formattedPrimaryValue,
                subtitle: subtitle,
                providerID: id,
                score: Self.pinScore
            )
            return SearchResult(query: query, items: [item])
        }
    }
}

/// Session memory for `ans` / previous calculator answers.
@MainActor
final class CalculatorSessionStore {
    private(set) var previousAnswer: Decimal?
    private(set) var lastResult: CalculatorResult?
    private(set) var variables: [String: CalculatorVariable] = [:]
    private(set) var history: [CalculatorHistoryEntry] = []
    private(set) var angleMode: CalculatorAngleMode
    private let exchangeRateProvider: any ExchangeRateProviding
    private let maxHistoryCount: Int
    private let dateProvider: () -> Date
    private let uuidProvider: () -> UUID

    init(
        angleMode: CalculatorAngleMode = .radians,
        exchangeRateProvider: any ExchangeRateProviding = FrankfurterExchangeRateProvider(),
        maxHistoryCount: Int = 100,
        dateProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.angleMode = angleMode
        self.exchangeRateProvider = exchangeRateProvider
        self.maxHistoryCount = max(1, maxHistoryCount)
        self.dateProvider = dateProvider
        self.uuidProvider = uuidProvider
    }

    func makeContext() -> CalculatorEvaluationContext {
        CalculatorEvaluationContext(
            locale: .current,
            calendar: .current,
            timeZone: .current,
            now: Date(),
            angleMode: angleMode,
            previousAnswer: previousAnswer,
            previousValue: lastResult?.primaryValue,
            variables: variables,
            exchangeRateProvider: exchangeRateProvider
        )
    }

    func recordSuccess(_ result: CalculatorResult) {
        lastResult = result
        if case .decimal(let value) = result.primaryValue {
            previousAnswer = value
        }
        if let name = result.metadata.assignedVariableName,
           let variable = result.metadata.assignedVariable {
            variables[name] = variable
        }
        let expression = result.displayExpression.isEmpty
            ? result.originalInput
            : result.displayExpression
        if history.first?.expression != expression
            || history.first?.formattedValue != result.formattedPrimaryValue {
            history.insert(
                CalculatorHistoryEntry(
                    id: uuidProvider(),
                    expression: expression,
                    formattedValue: result.formattedPrimaryValue,
                    createdAt: dateProvider()
                ),
                at: 0
            )
            if history.count > maxHistoryCount {
                history.removeLast(history.count - maxHistoryCount)
            }
        }
    }

    func removeHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
    }

    func clearHistory() {
        history.removeAll()
    }

    func setAngleMode(_ mode: CalculatorAngleMode) {
        angleMode = mode
    }
}
