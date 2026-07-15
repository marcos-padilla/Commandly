import AIKit
import Foundation
import Testing
@testable import Commandly

struct InMemoryAIProviderRuntimeServiceTests {
    @Test func queuedOutcomesAreConsumedInOrderAndRequestsAreRecorded() async throws {
        let selection = makeSelection()
        let response = AICompletionResponse(
            id: "response-1",
            message: .assistant("Finished"),
            finishReason: .completed
        )
        let service = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            outcomes: [.success(response), .failure(.scriptedFailure)]
        )
        let firstRequest = AICompletionRequest(
            modelID: selection.modelID,
            messages: [.user("First request")]
        )
        let secondRequest = AICompletionRequest(
            modelID: selection.modelID,
            messages: [.user("Second request")]
        )

        #expect(try await service.activeSelection() == selection)
        #expect(try await service.complete(
            firstRequest,
            providerID: selection.providerID,
            connectionRevision: selection.connectionRevision
        ) == response)
        await #expect(throws: AIProviderRuntimeTestError.scriptedFailure) {
            try await service.complete(
                secondRequest,
                providerID: selection.providerID,
                connectionRevision: selection.connectionRevision
            )
        }
        #expect(await service.recordedRequests() == [firstRequest, secondRequest])
    }

    @Test func missingSelectionAndExhaustedQueueUseSanitizedTypedErrors() async throws {
        let request = AICompletionRequest(
            modelID: "model-a",
            messages: [.user("Private Finder request")]
        )
        let noSelection = InMemoryAIProviderRuntimeService()

        #expect(try await noSelection.activeSelection() == nil)
        await #expect(throws: AIProviderRuntimeError.noActiveConnection) {
            try await noSelection.complete(
                request,
                providerID: "missing",
                connectionRevision: "missing"
            )
        }
        #expect(await noSelection.recordedRequests() == [request])

        let exhausted = InMemoryAIProviderRuntimeService(activeSelection: makeSelection())
        await #expect(throws: AIProviderRuntimeTestError.responseQueueExhausted) {
            try await exhausted.complete(
                request,
                providerID: "test-provider",
                connectionRevision: "test-connection-revision"
            )
        }
        #expect(
            AIProviderRuntimeTestError.responseQueueExhausted.localizedDescription
                .contains("Private Finder request") == false
        )
    }

    @Test func modelAndToolCapabilityChecksMirrorTheProductionRuntime() async throws {
        let selection = makeSelection(supportsTools: false)
        let response = AICompletionResponse(
            id: nil,
            message: .assistant("Unused"),
            finishReason: .completed
        )
        let service = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [response]
        )

        await #expect(throws: AIProviderRuntimeError.modelMismatch) {
            try await service.complete(
                AICompletionRequest(modelID: "other-model", messages: [.user("Hello")]),
                providerID: selection.providerID,
                connectionRevision: selection.connectionRevision
            )
        }
        await #expect(throws: AIProviderRuntimeError.toolsUnsupported) {
            try await service.complete(
                AICompletionRequest(
                    modelID: selection.modelID,
                    messages: [.user("Hello")],
                    tools: [makeTool()]
                ),
                providerID: selection.providerID,
                connectionRevision: selection.connectionRevision
            )
        }

        let accepted = try await service.complete(
            AICompletionRequest(modelID: selection.modelID, messages: [.user("Hello")]),
            providerID: selection.providerID,
            connectionRevision: selection.connectionRevision
        )
        #expect(accepted == response)
        #expect(await service.recordedRequests().count == 3)
    }

    private func makeSelection(
        supportsTools: Bool = true
    ) -> AIActiveProviderSelection {
        AIActiveProviderSelection(
            providerID: "test-provider",
            providerName: "Test Provider",
            modelID: "model-a",
            modelName: "Model A",
            supportsTools: supportsTools,
            connectionRevision: "test-connection-revision"
        )
    }

    private func makeTool() -> AIToolDefinition {
        AIToolDefinition(
            name: "finder_list",
            description: "List a folder.",
            inputSchema: .closedObject(properties: [:]),
            effect: .readOnly,
            confirmation: .never
        )
    }
}
