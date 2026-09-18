import AIKit
import Foundation
import Testing
@testable import Commandly

@MainActor
struct QuickAIViewModelTests {
    @Test func openingLoadsOnlyConfiguredChoicesAndOffersExistingSettings() async {
        let service = ControlledQuickAIService(catalog: .empty)
        var settingsOpened = false
        let model = QuickAIViewModel(service: service, onGoBack: {}, onOpenSettings: { settingsOpened = true })
        model.start()
        await model.waitForLoadingForTesting()
        #expect(await service.catalogReadCount == 1)
        #expect(await service.requests.isEmpty)
        #expect(model.selection == nil)
        #expect(model.canSend == false)
        model.perform(QuickAIActionID.settings)
        #expect(settingsOpened)
        model.stop()
    }

    @Test func incrementalReplyIsVisibleBeforeFinishAndFollowUpContainsCompletedContext() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "First question"
        model.send()
        await service.waitForRequests(1)
        try await service.emit("A partial")
        #expect(model.isResponding)
        #expect(model.entries.last?.text == "A partial")
        #expect(model.entries.last?.state == .streaming)
        await service.finish("A partial answer")
        await model.waitForResponseForTesting()
        #expect(model.entries.last?.state == .complete)
        model.draft = "Follow up"
        model.send()
        await service.waitForRequests(2)
        let request = try #require(await service.requests.last)
        #expect(Array(request.messages.dropFirst()) == [.user("First question"), .assistant("A partial answer"), .user("Follow up")])
        #expect(request.selection == QuickAITestFixtures.first)
        await service.finish("Follow-up answer", request: 1)
        await model.waitForResponseForTesting()
        model.stop()
    }

    @Test func cancellationRejectsLateChunksAndKeepsPartialOutputOutOfContext() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Canceled question"
        model.send()
        await service.waitForRequests(1)
        try await service.emit("Unfinished")
        #expect(model.handleEscape())
        #expect(model.entries.last?.state == .stopped)
        await #expect(throws: CancellationError.self) { try await service.emit(" stale text") }
        model.draft = "New question"
        model.send()
        await service.waitForRequests(2)
        let request = try #require(await service.requests.last)
        #expect(Array(request.messages.dropFirst()) == [.user("New question")])
        await service.finish("Late old answer", request: 0)
        await service.finish("New answer", request: 1)
        await model.waitForResponseForTesting()
        #expect(model.entries.last?.text == "New answer")
        #expect(model.entries.contains { $0.text == "Late old answer" } == false)
        model.stop()
    }

    @Test func retryReplacesFailedPairAndResubmitsOnlyItsOriginalMessage() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Please explain"
        model.send()
        await service.waitForRequests(1)
        try await service.emit("Partial")
        await service.fail(AIProviderError.networkUnavailable)
        await model.waitForResponseForTesting()
        #expect(model.canRetry)
        #expect(model.entries.last?.state == .failed)
        model.retry()
        await service.waitForRequests(2)
        #expect(model.entries.count == 2)
        #expect(await service.requests.last?.messages.last == .user("Please explain"))
        await service.finish("Complete explanation", request: 1)
        await model.waitForResponseForTesting()
        #expect(model.canRetry == false)
        model.stop()
    }

    @Test func changingProviderRequiresNewConversationAndDoesNotSendOldContext() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "First provider message"
        model.send()
        await service.waitForRequests(1)
        await service.finish("First provider answer")
        await model.waitForResponseForTesting()
        model.requestSelection(QuickAITestFixtures.second.id)
        #expect(model.pendingSelection == QuickAITestFixtures.second)
        #expect(model.selection == QuickAITestFixtures.first)
        #expect(model.canSend == false)
        model.confirmSelectionChange()
        #expect(model.entries.isEmpty)
        #expect(model.selection == QuickAITestFixtures.second)
        model.draft = "Second provider message"
        model.send()
        await service.waitForRequests(2)
        let request = try #require(await service.requests.last)
        #expect(Array(request.messages.dropFirst()) == [.user("Second provider message")])
        #expect(request.selection == QuickAITestFixtures.second)
        await service.finish("Second provider answer", request: 1)
        await model.waitForResponseForTesting()
        model.stop()
    }

    @Test func revisionChangeDiscardsProvisionalReplyAndRequiresReset() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Question"
        model.send()
        await service.waitForRequests(1)
        try await service.emit("Old account partial")
        await service.fail(AIProviderRuntimeError.connectionMismatch)
        await model.waitForResponseForTesting()
        #expect(model.entries.last?.text.isEmpty == true)
        #expect(model.needsReset)
        #expect(model.canRetry == false)
        model.draft = "Must not submit"
        model.send()
        #expect(await service.requests.count == 1)
        model.reset()
        #expect(model.needsReset == false)
        #expect(model.entries.isEmpty)
        model.stop()
    }

    @Test func resetAndSessionStopSuppressLateWorkAndClearPrivateContent() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Private question"
        model.send()
        await service.waitForRequests(1)
        model.reset()
        await #expect(throws: CancellationError.self) { try await service.emit("Late") }
        await service.finish("Late final")
        await model.waitForResponseForTesting()
        #expect(model.entries.isEmpty)
        #expect(model.draft.isEmpty)
        model.stop()
        #expect(model.selection == nil)
        #expect(model.selections.isEmpty)
    }

    @Test func oversizedPromptsAndUnsupportedStreamingDoNotSubmit() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = String(repeating: "x", count: 64 * 1_024 + 1)
        #expect(model.draftIsTooLarge)
        model.send()
        #expect(await service.requests.isEmpty)
        model.reset()
        let unsupported = QuickAISelection(providerID: "future", providerName: "Future", modelID: "model",
            modelName: "Model", connectionRevision: "version", supportsStreaming: false)
        await service.replaceCatalog(.init(selections: [unsupported], preferredID: unsupported.id))
        model.reloadChoices()
        await model.waitForLoadingForTesting()
        model.draft = "Question"
        #expect(model.canSend == false)
        #expect(model.composerHint.contains("unavailable"))
        model.stop()
    }

    @Test func lengthLimitedReplyIsLabeledAndRetainsItsActualText() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Long answer"
        model.send()
        await service.waitForRequests(1)
        await service.finish("Beginning of an answer", reason: .length)
        await model.waitForResponseForTesting()
        #expect(model.entries.last?.state == .limited)
        #expect(model.statusMessage?.contains("limit") == true)
        model.stop()
    }

    private func readyModel(_ service: ControlledQuickAIService) async -> QuickAIViewModel {
        let model = QuickAIViewModel(service: service, onGoBack: {}, onOpenSettings: {})
        model.start()
        await model.waitForLoadingForTesting()
        return model
    }
}
