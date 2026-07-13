import CalculatorKit
import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct CalculatorHistoryApplicationTests {
    @Test @MainActor func sessionRecordsOnlyExplicitSuccessfulResultsWithBoundedHistory() async throws {
        let firstID = UUID()
        let secondID = UUID()
        var ids = [firstID, secondID]
        let store = CalculatorSessionStore(
            maxHistoryCount: 1,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) },
            uuidProvider: { ids.removeFirst() }
        )
        let calculator = CalculatorService()
        let first = try #require(
            await successfulResult(
                calculator.evaluate("2 + 2", context: store.makeContext())
            )
        )

        store.recordSuccess(first)
        store.recordSuccess(first)

        #expect(store.history.count == 1)
        #expect(store.history.first?.id == firstID)
        #expect(store.history.first?.formattedValue == "4")

        let second = try #require(
            await successfulResult(
                calculator.evaluate("6 * 7", context: store.makeContext())
            )
        )
        store.recordSuccess(second)

        #expect(store.history.count == 1)
        #expect(store.history.first?.id == secondID)
        #expect(store.history.first?.formattedValue == "42")
    }

    @Test @MainActor func historyModelFiltersCopiesDeletesAndClears() async throws {
        let pasteboard = InMemoryPasteboard()
        let store = CalculatorSessionStore()
        let calculator = CalculatorService()
        let result = try #require(
            await successfulResult(
                calculator.evaluate("12 * 12", context: store.makeContext())
            )
        )
        store.recordSuccess(result)
        let model = CalculatorHistoryViewModel(
            sessionStore: store,
            pasteboard: pasteboard,
            onGoBack: {}
        )

        model.query = "144"
        #expect(model.filteredEntries.count == 1)
        model.perform(BuiltInCommandActionID.copy)
        await model.flushCopyForTesting()
        #expect(pasteboard.currentValue == "144")

        model.perform(CalculatorHistoryActionID.copyExpression)
        await model.flushCopyForTesting()
        #expect(pasteboard.currentValue?.contains("12") == true)

        model.perform(BuiltInCommandActionID.delete)
        #expect(store.history.isEmpty)
        #expect(model.selectedEntry == nil)

        store.recordSuccess(result)
        model.perform(BuiltInCommandActionID.clearHistory)
        #expect(store.history.isEmpty)
    }

    @Test @MainActor func builtInRegistryLaunchesCalculationHistoryWithoutRootBranch() throws {
        let store = CalculatorSessionStore()
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            calculatorSessionStore: store
        )
        let viewModel = LauncherViewModel(
            applicationRegistry: registry,
            calculatorSession: store,
            placeholderItems: []
        )

        viewModel.launch(CalculatorHistoryApplication.id)

        #expect(viewModel.route == .application(CalculatorHistoryApplication.id))
        #expect(
            viewModel.activeApplicationModel(as: CalculatorHistoryViewModel.self) != nil
        )
    }

    private func successfulResult(
        _ outcome: CalculatorEvaluationOutcome
    ) -> CalculatorResult? {
        guard case .success(let result) = outcome else { return nil }
        return result
    }
}
