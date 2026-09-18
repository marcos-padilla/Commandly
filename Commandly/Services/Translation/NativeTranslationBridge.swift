import Foundation
import Infrastructure
import Observation

nonisolated enum NativeTranslationWork: Sendable, Equatable {
    case translate(TextTranslationRequest)
    case prepare(sourceLanguageID: String, targetLanguageID: String)
}
nonisolated struct NativeTranslationOperation: Sendable, Equatable, Identifiable {
    let id: UUID
    let work: NativeTranslationWork
}
nonisolated enum NativeTranslationOutcome: Sendable, Equatable {
    case translated(TextTranslationResult)
    case prepared
}

/// Connects an explicit model request to a view-bound native translationTask.
/// Owns request values and one continuation, never a TranslationSession or its cancellation handle.
@MainActor
@Observable
final class NativeTranslationBridge: TextTranslating {
    private(set) var operation: NativeTranslationOperation?
    @ObservationIgnored private var continuation: CheckedContinuation<NativeTranslationOutcome, Error>?
    @ObservationIgnored private var claimedID: UUID?
    @ObservationIgnored private var operationWaiters: [(UUID?, CheckedContinuation<NativeTranslationOperation, Never>)] = []

    func translate(_ request: TextTranslationRequest) async throws -> TextTranslationResult {
        let result = try await perform(.translate(request))
        guard case .translated(let translation) = result else { throw TextTranslationError.invalidResult }
        return translation
    }

    func prepare(sourceLanguageID: String, targetLanguageID: String) async throws {
        let result = try await perform(.prepare(sourceLanguageID: sourceLanguageID, targetLanguageID: targetLanguageID))
        guard case .prepared = result else { throw TextTranslationError.invalidResult }
    }

    /// A SwiftUI host may be updated more than once; only one callback can claim a request.
    func claim(_ id: UUID) -> Bool {
        guard operation?.id == id, continuation != nil, claimedID == nil else { return false }
        claimedID = id
        return true
    }

    func finish(_ id: UUID, with result: Result<NativeTranslationOutcome, Error>) {
        guard operation?.id == id, claimedID == id else { return }
        let pending = continuation
        continuation = nil
        operation = nil
        claimedID = nil
        pending?.resume(with: result)
    }

    func cancel() {
        let pending = continuation
        continuation = nil
        operation = nil
        claimedID = nil
        pending?.resume(throwing: CancellationError())
    }

    func waitForOperationForTesting(after previousID: UUID? = nil) async -> NativeTranslationOperation {
        if let operation, operation.id != previousID { return operation }
        return await withCheckedContinuation { operationWaiters.append((previousID, $0)) }
    }

    /// Cancellation from a retiring SwiftUI action cannot cancel a newer request.
    func cancel(operationID: UUID) {
        guard operation?.id == operationID else { return }
        cancel()
    }

    private func perform(_ work: NativeTranslationWork) async throws -> NativeTranslationOutcome {
        try Task.checkCancellation()
        cancel()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending in
                continuation = pending
                let value = NativeTranslationOperation(id: id, work: work)
                operation = value
                for (previousID, waiter) in operationWaiters where previousID != value.id { waiter.resume(returning: value) }
                operationWaiters.removeAll { $0.0 != value.id }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(operationID: id)
            }
        }
    }
}
