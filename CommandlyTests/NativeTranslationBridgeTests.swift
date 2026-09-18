import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("View-bound native translation bridge", .timeLimit(.minutes(1)))
@MainActor
struct NativeTranslationBridgeTests {
    @Test
    func callbackClaimsOnlyOnceAndReturnsExactReviewedResult() async throws {
        let bridge = NativeTranslationBridge()
        let request = try TextTranslationRequest(text: "hello", sourceLanguageID: nil, targetLanguageID: "es")
        let task = Task { try await bridge.translate(request) }
        let operation = await bridge.waitForOperationForTesting()
        #expect(operation.work == .translate(request))
        #expect(bridge.claim(operation.id))
        #expect(!bridge.claim(operation.id))
        let result = try TranslationTestValue.result()
        bridge.finish(operation.id, with: .success(.translated(result)))
        bridge.finish(operation.id, with: .failure(TextTranslationError.translationFailed))
        #expect(try await task.value == result)
        #expect(bridge.operation == nil)
    }

    @Test
    func explicitPreparationHasNoTextTranslationAndChecksOutcomeKind() async throws {
        let bridge = NativeTranslationBridge()
        let task = Task { try await bridge.prepare(sourceLanguageID: "en", targetLanguageID: "es") }
        let operation = await bridge.waitForOperationForTesting()
        #expect(operation.work == .prepare(sourceLanguageID: "en", targetLanguageID: "es"))
        #expect(bridge.claim(operation.id))
        bridge.finish(operation.id, with: .success(.prepared))
        try await task.value
        let request = try TextTranslationRequest(text: "hello", sourceLanguageID: nil, targetLanguageID: "es")
        let wrongKind = Task { try await bridge.translate(request) }
        let next = await bridge.waitForOperationForTesting()
        #expect(bridge.claim(next.id))
        bridge.finish(next.id, with: .success(.prepared))
        await #expect(throws: TextTranslationError.invalidResult) { try await wrongKind.value }
    }

    @Test
    func replacementCancelsPreviousRequestAndRejectsItsLateNativeCallback() async throws {
        let bridge = NativeTranslationBridge()
        let first = Task { try await bridge.translate(TranslationTestValue.request("first")) }
        let old = await bridge.waitForOperationForTesting()
        #expect(bridge.claim(old.id))
        let second = Task { try await bridge.translate(TranslationTestValue.request("second")) }
        // Wait for a different operation through an explicit observer, not a synchronization delay.
        let new = await bridge.waitForOperationForTesting(after: old.id)
        #expect(new.id != old.id && bridge.claim(new.id))
        bridge.finish(old.id, with: .success(.translated(try TranslationTestValue.result("stale"))))
        bridge.cancel(operationID: old.id)
        #expect(bridge.operation?.id == new.id)
        let result = try TranslationTestValue.result("current")
        bridge.finish(new.id, with: .success(.translated(result)))
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == result)
    }

    @Test
    func cancellationResumesPendingCallerAndLateCallbacksCannotReopenIt() async throws {
        let bridge = NativeTranslationBridge()
        let task = Task { try await bridge.translate(TranslationTestValue.request()) }
        let operation = await bridge.waitForOperationForTesting()
        #expect(bridge.claim(operation.id))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        bridge.finish(operation.id, with: .success(.translated(try TranslationTestValue.result())))
        #expect(bridge.operation == nil && !bridge.claim(operation.id))
    }

    @Test
    func alreadyCancelledCallerNeverCreatesNativeOperation() async throws {
        let bridge = NativeTranslationBridge()
        let task = Task { try await bridge.translate(TranslationTestValue.request()) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(bridge.operation == nil)
    }
}
