import AIKit
import Foundation
@testable import Commandly

nonisolated enum QuickAITestFixtures {
    static let first = QuickAISelection(providerID: "openai", providerName: "OpenAI", modelID: "fixture-a",
        modelName: "Fixture A", connectionRevision: "revision-a", supportsStreaming: true)
    static let second = QuickAISelection(providerID: "groq", providerName: "Groq", modelID: "fixture-b",
        modelName: "Fixture B", connectionRevision: "revision-b", supportsStreaming: true)
    static let third = QuickAISelection(providerID: "openai", providerName: "OpenAI", modelID: "fixture-c",
        modelName: "Fixture C", connectionRevision: "revision-a", supportsStreaming: true)
    static let catalog = QuickAICatalog(selections: [first, second], preferredID: first.id)
}

actor ControlledQuickAIService {
    nonisolated struct Request: Sendable {
        let messages: [AIMessage]
        let selection: QuickAISelection
    }
    private var value: QuickAICatalog
    private(set) var requests: [Request] = []
    private(set) var catalogReadCount = 0
    private(set) var modelRequests: [QuickAISelection] = []
    private var modelCompletions: [Int: CheckedContinuation<[QuickAISelection], any Error>] = [:]
    private var modelWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var callbacks: [Int: @Sendable (String) async throws -> Void] = [:]
    private var completions: [Int: CheckedContinuation<AICompletionResponse, any Error>] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    init(catalog: QuickAICatalog = QuickAITestFixtures.catalog) { value = catalog }
    func catalog() async throws -> QuickAICatalog { catalogReadCount += 1; return value }
    func refreshModels(for selection: QuickAISelection) async throws -> [QuickAISelection] {
        let index = modelRequests.count
        modelRequests.append(selection)
        return try await withCheckedThrowingContinuation { continuation in
            modelCompletions[index] = continuation
            let ready = modelWaiters.filter { $0.count <= modelRequests.count }
            modelWaiters.removeAll { $0.count <= modelRequests.count }
            for waiter in ready { waiter.continuation.resume() }
        }
    }
    func waitForModelRequests(_ count: Int) async {
        guard modelRequests.count < count else { return }
        await withCheckedContinuation { modelWaiters.append((count, $0)) }
    }
    func finishModels(_ choices: [QuickAISelection], request: Int = 0) {
        modelCompletions.removeValue(forKey: request)?.resume(returning: choices)
    }
    func failModels(_ error: any Error, request: Int = 0) {
        modelCompletions.removeValue(forKey: request)?.resume(throwing: error)
    }
    func replaceCatalog(_ value: QuickAICatalog) { self.value = value }
    func respond(messages: [AIMessage], selection: QuickAISelection,
                 onTextDelta: @escaping @Sendable (String) async throws -> Void) async throws -> AICompletionResponse {
        let index = requests.count
        requests.append(Request(messages: messages, selection: selection))
        callbacks[index] = onTextDelta
        return try await withCheckedThrowingContinuation { continuation in
            completions[index] = continuation
            let ready = waiters.filter { $0.count <= requests.count }
            waiters.removeAll { $0.count <= requests.count }
            for waiter in ready { waiter.continuation.resume() }
        }
    }
    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func emit(_ text: String, request: Int = 0) async throws { try await callbacks[request]?(text) }
    func finish(_ text: String, request: Int = 0, reason: AIFinishReason = .completed) {
        completions.removeValue(forKey: request)?.resume(returning: .init(id: nil, message: .assistant(text), finishReason: reason))
        callbacks.removeValue(forKey: request)
    }
    func fail(_ error: any Error, request: Int = 0) {
        completions.removeValue(forKey: request)?.resume(throwing: error)
        callbacks.removeValue(forKey: request)
    }
}

// Keep protocol isolation inference separate from the actor declaration in Xcode batch builds.
extension ControlledQuickAIService: QuickAIServicing {}
