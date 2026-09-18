import AIKit
import Foundation
import Testing
@testable import Commandly

@MainActor
struct QuickAIModelPickerTests {
    @Test func openingDoesNotDiscoverAndExplicitRefreshPreservesDraftAndSelectedModel() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        #expect(await service.modelRequests.isEmpty)
        model.draft = "Keep this draft"
        model.refreshModels()
        await service.waitForModelRequests(1)
        #expect(model.isRefreshingModels)
        #expect(model.canSend == false)
        #expect(await service.modelRequests.first == QuickAITestFixtures.first)
        await service.finishModels([QuickAITestFixtures.first, QuickAITestFixtures.third])
        await model.waitForModelRefreshForTesting()
        #expect(model.selections.contains(QuickAITestFixtures.third))
        #expect(model.selections.contains(QuickAITestFixtures.second))
        #expect(model.selection == QuickAITestFixtures.first)
        #expect(model.draft == "Keep this draft")
        #expect(model.canSend)
        #expect(await service.requests.isEmpty)
        model.stop()
    }

    @Test func choosingAnotherDiscoveredModelConfirmsAndStartsWithoutPreviousContext() async throws {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Original question"
        model.send()
        await service.waitForRequests(1)
        await service.finish("Original answer")
        await model.waitForResponseForTesting()
        model.draft = "Existing draft"
        model.refreshModels()
        await service.waitForModelRequests(1)
        await service.finishModels([QuickAITestFixtures.first, QuickAITestFixtures.third])
        await model.waitForModelRefreshForTesting()
        #expect(model.entries.count == 2)
        model.requestSelection(QuickAITestFixtures.third.id)
        #expect(model.pendingSelection == QuickAITestFixtures.third)
        #expect(model.selection == QuickAITestFixtures.first)
        model.cancelSelectionChange()
        #expect(model.draft == "Existing draft")
        #expect(model.entries.count == 2)
        model.requestSelection(QuickAITestFixtures.third.id)
        model.confirmSelectionChange()
        #expect(model.draft.isEmpty)
        #expect(model.entries.isEmpty)
        model.draft = "New model question"
        model.send()
        await service.waitForRequests(2)
        let request = try #require(await service.requests.last)
        #expect(request.selection == QuickAITestFixtures.third)
        #expect(Array(request.messages.dropFirst()) == [.user("New model question")])
        await service.finish("New model answer", request: 1)
        await model.waitForResponseForTesting()
        model.stop()
    }

    @Test func failedAndEmptyDiscoveryPreserveTranscriptDraftAndExistingChoices() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Question"
        model.send()
        await service.waitForRequests(1)
        await service.finish("Answer")
        await model.waitForResponseForTesting()
        let original = model.entries
        model.draft = "Follow up later"
        model.refreshModels()
        await service.waitForModelRequests(1)
        await service.failModels(AIConnectionServiceError.rateLimited)
        await model.waitForModelRefreshForTesting()
        #expect(model.modelRefreshFailed)
        #expect(model.modelRefreshMessage?.contains("quota") == true)
        #expect(model.statusMessage == nil)
        #expect(model.entries == original)
        #expect(model.draft == "Follow up later")
        #expect(model.canSend)
        model.refreshModels()
        await service.waitForModelRequests(2)
        await service.finishModels([], request: 1)
        await model.waitForModelRefreshForTesting()
        #expect(model.modelRefreshMessage?.contains("No compatible") == true)
        #expect(model.selections == QuickAITestFixtures.catalog.selections)
        #expect(model.entries == original)
        model.stop()
    }

    @Test func cancelAndTeardownIgnoreLateDiscoveryResults() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Keep me"
        model.refreshModels()
        await service.waitForModelRequests(1)
        #expect(model.handleEscape())
        #expect(model.isRefreshingModels == false)
        await service.finishModels([QuickAITestFixtures.third])
        await model.waitForModelRefreshForTesting()
        #expect(model.selection == QuickAITestFixtures.first)
        #expect(model.selections.contains(QuickAITestFixtures.third) == false)
        #expect(model.draft == "Keep me")
        model.refreshModels()
        await service.waitForModelRequests(2)
        model.stop()
        await service.finishModels([QuickAITestFixtures.third], request: 1)
        await model.waitForModelRefreshForTesting()
        #expect(model.selection == nil)
        #expect(model.selections.isEmpty)
        #expect(model.modelRefreshMessage == nil)
    }

    @Test func refreshedCatalogRemovingCurrentModelRequiresExplicitSwitch() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Private draft"
        model.refreshModels()
        await service.waitForModelRequests(1)
        await service.finishModels([QuickAITestFixtures.third])
        await model.waitForModelRefreshForTesting()
        #expect(model.selection == QuickAITestFixtures.first)
        #expect(model.isSelectedModelAvailable == false)
        #expect(model.canSend == false)
        #expect(model.modelRefreshMessage?.contains("no longer lists") == true)
        model.requestSelection(QuickAITestFixtures.third.id)
        #expect(model.pendingSelection == QuickAITestFixtures.third)
        model.confirmSelectionChange()
        #expect(model.selection == QuickAITestFixtures.third)
        #expect(model.isSelectedModelAvailable)
        #expect(model.draft.isEmpty)
        model.stop()
    }

    @Test func changingSavedRevisionDropsDiscoveredChoicesAndDiscoveryFailurePreservesContent() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Keep this"
        model.refreshModels()
        await service.waitForModelRequests(1)
        await service.failModels(AIProviderRuntimeError.connectionMismatch)
        await model.waitForModelRefreshForTesting()
        #expect(model.needsReset)
        #expect(model.draft == "Keep this")
        #expect(model.canSend == false)
        model.reset()
        model.refreshModels()
        await service.waitForModelRequests(2)
        await service.finishModels([QuickAITestFixtures.first, QuickAITestFixtures.third], request: 1)
        await model.waitForModelRefreshForTesting()
        let changed = QuickAISelection(providerID: "openai", providerName: "OpenAI", modelID: "new-saved",
            modelName: "New saved", connectionRevision: "new-revision", supportsStreaming: true)
        await service.replaceCatalog(.init(selections: [changed], preferredID: changed.id))
        model.reloadChoices()
        await model.waitForLoadingForTesting()
        #expect(model.selections == [changed])
        #expect(model.selection == changed)
        model.stop()
    }

    @Test func reloadingRemovedProviderDoesNotMovePrivateDraftToAnotherProvider() async {
        let service = ControlledQuickAIService()
        let model = await readyModel(service)
        model.draft = "Draft intended for the first provider"
        await service.replaceCatalog(.init(selections: [QuickAITestFixtures.second], preferredID: QuickAITestFixtures.second.id))
        model.reloadChoices()
        await model.waitForLoadingForTesting()
        #expect(model.selection == nil)
        #expect(model.needsReset)
        #expect(model.draft == "Draft intended for the first provider")
        #expect(model.canSend == false)
        model.requestSelection(QuickAITestFixtures.second.id)
        #expect(model.pendingSelection == QuickAITestFixtures.second)
        model.confirmSelectionChange()
        #expect(model.selection == QuickAITestFixtures.second)
        #expect(model.draft.isEmpty)
        #expect(await service.requests.isEmpty)
        model.stop()
    }

    private func readyModel(_ service: ControlledQuickAIService) async -> QuickAIViewModel {
        let model = QuickAIViewModel(service: service, onGoBack: {}, onOpenSettings: {})
        model.start()
        await model.waitForLoadingForTesting()
        return model
    }
}
