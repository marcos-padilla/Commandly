import CalculatorKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct LauncherConfirmationTests {
    @Test func immediateActionsWaitForTheirQueryInsteadOfUsingThePreviousApplication() async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener()
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "Old Fixture"
        await model.flushSearchForTesting()
        await calculator.block("New Fixture")
        model.query = "New Fixture"
        await calculator.waitUntilStarted("New Fixture")
        model.presentApplicationActionsForSelection()
        model.presentApplicationActionsForSelection()
        #expect(model.showsApplicationActionsPanel == false)
        await calculator.release("New Fixture")
        await model.waitForConfirmationForTesting()
        #expect(model.applicationActionsTargetBundleID == "com.example.new-fixture")
        #expect(await opener.opened.isEmpty)
        model.resetAfterDismiss()
    }

    @Test func escapeCancelsPendingActionsWithoutOpeningAnOldOrNewPanel() async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener()
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "Old Fixture"
        await model.flushSearchForTesting()
        await calculator.block("New Fixture")
        model.query = "New Fixture"
        await calculator.waitUntilStarted("New Fixture")
        model.presentApplicationActionsForSelection()
        #expect(model.handleEscape())
        await calculator.release("New Fixture")
        await model.waitForConfirmationForTesting()
        await model.flushSearchForTesting()
        #expect(model.showsApplicationActionsPanel == false)
        #expect(model.showsRegisteredCommandActionsPanel == false)
        #expect(await opener.opened.isEmpty)
        model.resetAfterDismiss()
    }

    @Test func immediateReturnWaitsForItsQueryAndCoalescesRepeatedPresses() async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener()
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "Old Fixture"
        await model.flushSearchForTesting()
        #expect(model.selectedItem?.title == "Old Fixture")

        await calculator.block("New Fixture")
        model.query = "New Fixture"
        await calculator.waitUntilStarted("New Fixture")
        model.confirmSelection()
        model.confirmSelection()
        #expect(await opener.opened.isEmpty)
        #expect(model.route == .root)
        await calculator.release("New Fixture")
        await model.waitForConfirmationForTesting()
        #expect(await opener.opened == ["com.example.new-fixture"])
        model.resetAfterDismiss()
    }

    enum Cancellation: CaseIterable, Sendable {
        case queryEdit, escape, routeChange, reset, selectionMovement
    }

    @Test(arguments: Cancellation.allCases)
    func pendingReturnIsCancelledByFurtherUserIntent(_ reason: Cancellation) async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener()
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "Old Fixture"
        await model.flushSearchForTesting()
        await calculator.block("New Fixture")
        model.query = "New Fixture"
        await calculator.waitUntilStarted("New Fixture")
        model.confirmSelection()
        switch reason {
        case .queryEdit:
            // Returning to identical text still represents a different search request.
            model.query = "Old Fixture"
            model.query = "New Fixture"
            await calculator.waitUntilStarted("New Fixture", count: 2)
        case .escape:
            #expect(model.handleEscape())
        case .routeChange:
            model.route = .uninstallReview(bundleIdentifier: "com.example.fixture")
        case .reset:
            model.resetAfterDismiss()
        case .selectionMovement:
            model.moveSelection(offset: 1)
        }
        await calculator.release("New Fixture")
        await model.waitForConfirmationForTesting()
        await model.flushSearchForTesting()
        #expect(await opener.opened.isEmpty)
        model.resetAfterDismiss()
    }

    @Test func repeatedReturnWhileOpeningDoesNotDuplicateTheSideEffect() async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener(suspendsOpening: true)
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "New Fixture"
        await model.flushSearchForTesting()
        model.confirmSelection()
        await opener.waitUntilStarted()
        model.confirmSelection()
        #expect(await opener.opened == ["com.example.new-fixture"])
        await opener.release()
        await model.waitForConfirmationForTesting()
        #expect(await opener.opened == ["com.example.new-fixture"])
        model.resetAfterDismiss()
    }

    @Test func emptyCurrentResultsNeverExecuteThePreviousSelection() async {
        let calculator = ConfirmationGateCalculator()
        let opener = ConfirmationRecordingOpener()
        let model = makeModel(calculator: calculator, opener: opener)
        model.query = "Old Fixture"
        await model.flushSearchForTesting()
        await calculator.block("zz-no-fixture-result-zz")
        model.query = "zz-no-fixture-result-zz"
        await calculator.waitUntilStarted("zz-no-fixture-result-zz")
        model.confirmSelection()
        await calculator.release("zz-no-fixture-result-zz")
        await model.waitForConfirmationForTesting()
        #expect(model.rootItems.isEmpty)
        #expect(await opener.opened.isEmpty)
        model.resetAfterDismiss()
    }

    private func makeModel(
        calculator: ConfirmationGateCalculator,
        opener: ConfirmationRecordingOpener
    ) -> LauncherViewModel {
        LauncherViewModel(
            applicationOpener: opener,
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [
                InstalledApplication(bundleIdentifier: "com.example.old-fixture", name: "Old Fixture", path: "/Old.app"),
                InstalledApplication(bundleIdentifier: "com.example.new-fixture", name: "New Fixture", path: "/New.app")
            ]),
            pasteboard: InMemoryPasteboard(),
            calculator: calculator,
            placeholderItems: []
        )
    }
}

/// A deliberately cancellation-insensitive dependency proves that late search results cannot
/// execute a cancelled submission. Tests explicitly release every blocked evaluation.
private actor ConfirmationGateCalculator: CalculatorEvaluating {
    private var blocked: Set<String> = []
    private var starts: [String: Int] = [:]
    private var evaluations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var observers: [(String, Int, CheckedContinuation<Void, Never>)] = []

    func block(_ input: String) { blocked.insert(input) }

    func evaluate(_ input: String, context: CalculatorEvaluationContext) async -> CalculatorEvaluationOutcome {
        guard blocked.contains(input) else { return .notCalculator }
        starts[input, default: 0] += 1
        let ready = observers.filter { $0.0 == input && $0.1 <= starts[input, default: 0] }
        observers.removeAll { $0.0 == input && $0.1 <= starts[input, default: 0] }
        ready.forEach { $0.2.resume() }
        await withCheckedContinuation { evaluations[input, default: []].append($0) }
        return .notCalculator
    }

    func waitUntilStarted(_ input: String, count: Int = 1) async {
        if starts[input, default: 0] >= count { return }
        await withCheckedContinuation { observers.append((input, count, $0)) }
    }

    func release(_ input: String) {
        blocked.remove(input)
        let pending = evaluations.removeValue(forKey: input) ?? []
        pending.forEach { $0.resume() }
    }
}

private actor ConfirmationRecordingOpener: ApplicationOpening {
    private(set) var opened: [String] = []
    private let suspendsOpening: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    init(suspendsOpening: Bool = false) { self.suspendsOpening = suspendsOpening }

    func openApplication(bundleIdentifier: String) async throws {
        opened.append(bundleIdentifier)
        observer?.resume()
        observer = nil
        if suspendsOpening { await withCheckedContinuation { waiter = $0 } }
    }

    func waitUntilStarted() async {
        if opened.isEmpty == false { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}
