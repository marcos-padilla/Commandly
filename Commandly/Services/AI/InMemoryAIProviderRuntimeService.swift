import AIKit
import Foundation

/// Content-free failures emitted by the deterministic provider runtime.
nonisolated enum AIProviderRuntimeTestError: LocalizedError, Equatable, Sendable {
    case scriptedFailure
    case responseQueueExhausted

    var errorDescription: String? {
        switch self {
        case .scriptedFailure:
            return "The simulated AI provider request failed."
        case .responseQueueExhausted:
            return "The simulated AI provider has no response queued."
        }
    }
}

/// Deterministic provider runtime for Finder AI tests and previews.
///
/// The actor never reads credentials or touches the network. Each accepted completion consumes one
/// queued outcome, and every attempted completion is retained for assertions.
actor InMemoryAIProviderRuntimeService: AIProviderRuntimeServicing {
    typealias Outcome = Result<AICompletionResponse, AIProviderRuntimeTestError>

    private let selection: AIActiveProviderSelection?
    private var outcomes: [Outcome]
    private var requests: [AICompletionRequest] = []

    init(
        activeSelection: AIActiveProviderSelection? = nil,
        outcomes: [Outcome] = []
    ) {
        self.selection = activeSelection
        self.outcomes = outcomes
    }

    init(
        activeSelection: AIActiveProviderSelection? = nil,
        responses: [AICompletionResponse]
    ) {
        self.selection = activeSelection
        self.outcomes = responses.map(Outcome.success)
    }

    func activeSelection() async throws -> AIActiveProviderSelection? {
        try Task.checkCancellation()
        return selection
    }

    func complete(
        _ request: AICompletionRequest,
        providerID: String,
        connectionRevision: String
    ) async throws -> AICompletionResponse {
        try Task.checkCancellation()
        requests.append(request)

        guard let selection else {
            throw AIProviderRuntimeError.noActiveConnection
        }
        guard selection.providerID == providerID else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        guard selection.modelID == request.modelID else {
            throw AIProviderRuntimeError.modelMismatch
        }
        guard selection.connectionRevision == connectionRevision else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        if request.tools.isEmpty == false, selection.supportsTools == false {
            throw AIProviderRuntimeError.toolsUnsupported
        }
        guard outcomes.isEmpty == false else {
            throw AIProviderRuntimeTestError.responseQueueExhausted
        }

        switch outcomes.removeFirst() {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() async -> [AICompletionRequest] {
        requests
    }
}
