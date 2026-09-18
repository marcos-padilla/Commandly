import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct DisplayResolutionCoordinatorTests {
    @Test func openingAndSelectingAreInertUntilApplyAndCloseRestores() async throws {
        let harness = ResolutionHarness()
        #expect(await harness.driver.snapshotCount == 0)
        #expect(harness.window.presentations == 0 && harness.ticker.callback == nil)
        try await harness.showAndSelect()
        #expect(await harness.driver.changes.isEmpty)
        harness.model.apply()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.phase == .preview && harness.model.remainingSeconds == 15)
        harness.model.requestClose()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.hasPendingChange == false && harness.window.closes == 1)
        #expect(await harness.driver.hardware.display(ResolutionTestData.identity)?.current == ResolutionTestData.original)
    }

    @Test func timeoutRevertsOnceAndOpeningAgainDoesNotExtendTheDeadline() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        harness.clock.advance(seconds: 10)
        harness.model.show()
        #expect(harness.model.remainingSeconds == 5)
        harness.clock.advance(seconds: 5)
        harness.ticker.fire(); harness.model.tick()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.hasPendingChange == false)
        #expect(await harness.driver.changes.count == 2)
    }

    @Test func closeAndTimeoutDuringInFlightApplyWaitForItsRollback() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        await harness.driver.suspendNextChange()
        harness.model.apply()
        await harness.driver.waitForPausedChange()
        harness.model.requestClose()
        harness.clock.advance(seconds: 20); harness.ticker.fire()
        #expect(harness.window.closes == 0)
        await harness.driver.resumeChange()
        await harness.model.waitForWorkForTesting()
        #expect(harness.window.closes == 1 && harness.model.hasPendingChange == false)
        let changes = await harness.driver.changes
        #expect(changes.count == 2 && changes.last?.mode == ResolutionTestData.original)
    }

    @Test func failedRevertKeepsRecoveryVisibleAndRetryFinishesTheClose() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        await harness.driver.failNext(.revertFailed)
        harness.model.requestClose(); await harness.model.waitForWorkForTesting()
        #expect(harness.model.phase == .recovery && harness.model.hasPendingChange)
        #expect(harness.window.closes == 0 && harness.ticker.callback == nil)
        harness.model.revert(); await harness.model.waitForWorkForTesting()
        #expect(harness.model.hasPendingChange == false && harness.window.closes == 1)
    }

    @Test func quitWaitsForRestorationAndFailedRestorationRequiresExplicitFallback() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        await harness.driver.failNext(.revertFailed)
        var replies: [Bool] = []
        harness.model.requestCloseForTermination { replies.append($0) }
        #expect(replies.isEmpty)
        await harness.model.waitForWorkForTesting()
        #expect(replies == [false] && harness.model.phase == .recovery)
        harness.model.quitWithoutExactRestore()
        #expect(harness.quitRequests == 1)
        harness.model.requestCloseForTermination { replies.append($0) }
        #expect(replies == [false, true])
        #expect(harness.model.hasPendingChange && harness.model.requiresTerminationReview == false)
        harness.model.cancelPendingTermination()
        #expect(harness.model.requiresTerminationReview)
        #expect(harness.environment.callback != nil)
        harness.model.requestCloseForTermination { replies.append($0) }
        await harness.model.waitForWorkForTesting()
        #expect(replies == [false, true, true] && harness.model.hasPendingChange == false)
    }

    @Test func canceledQuitDuringApplyRepliesOnceAndStillCompletesRestoration() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        await harness.driver.suspendNextChange()
        harness.model.apply()
        await harness.driver.waitForPausedChange()
        var replies: [Bool] = []
        harness.model.requestCloseForTermination { replies.append($0) }
        #expect(replies.isEmpty && harness.model.requiresTerminationReview)
        harness.model.cancelPendingTermination()
        #expect(replies == [false])
        await harness.driver.resumeChange()
        await harness.model.waitForWorkForTesting()
        #expect(replies == [false] && harness.model.hasPendingChange == false)
        #expect(harness.window.closes == 0 && harness.environment.callback != nil)
        #expect(await harness.driver.hardware.display(ResolutionTestData.identity)?.current == ResolutionTestData.original)
    }

    @Test func topologyNotificationPreservesAnOutsideModeChoice() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        await harness.driver.setHardware(ResolutionTestData.hardware(current: ResolutionTestData.fastRefresh))
        harness.environment.callback?()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.hasPendingChange == false)
        #expect(harness.model.statusMessage?.contains("newer choice was preserved") == true)
        #expect(await harness.driver.changes.count == 1)
    }

    @Test func keepAtTheExactDeadlineCannotPromoteToLoginSession() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        harness.clock.advance(seconds: 15)
        harness.model.keep(); await harness.model.waitForWorkForTesting()
        let changes = await harness.driver.changes
        #expect(changes.count == 2 && changes.allSatisfy { $0.scope == .appLifetime })
    }

    @Test func aCloseAfterExplicitKeepWaitsForThatAcceptedDecision() async throws {
        let harness = ResolutionHarness()
        try await harness.showAndSelect()
        harness.model.apply(); await harness.model.waitForWorkForTesting()
        await harness.driver.suspendNextChange()
        harness.model.keep()
        await harness.driver.waitForPausedChange()
        harness.model.requestClose()
        #expect(harness.window.closes == 0)
        await harness.driver.resumeChange()
        await harness.model.waitForWorkForTesting()
        #expect(harness.window.closes == 1 && harness.model.hasPendingChange == false)
        let changes = await harness.driver.changes
        #expect(changes.count == 2 && changes.last?.scope == .loginSession)
    }
}

@MainActor
private final class ResolutionHarness {
    let driver = ResolutionTestDriver()
    let clock = ResolutionTestClock()
    let ticker = ResolutionTestTicker()
    let environment = ResolutionTestEnvironment()
    let window = ResolutionTestWindow()
    var quitRequests = 0
    lazy var model = DisplayResolutionCoordinator(controller: DisplayResolutionService(driver: driver, clock: clock),
        clock: clock, ticker: ticker, environment: environment, window: window, openSettings: {},
        onRequestQuit: { [weak self] in self?.quitRequests += 1 })
    func showAndSelect() async throws {
        model.show(); await model.waitForWorkForTesting()
        let catalog = try #require(model.catalog)
        let selection = try #require(ResolutionTestData.selection(catalog))
        model.selectDisplay(selection.displayID); model.selectMode(selection.modeID)
    }
}
