import Foundation
import Infrastructure

/// Helper-local testable mutation port. No raw AX object or arbitrary attribute crosses this boundary.
public protocol CompanionWindowLayoutMutationPort: Sendable {
    func validateMutation(_ id: UUID) async throws
    func resizeMutation(_ id: UUID) async throws -> CompanionWindowMutationState
    func positionMutation(_ id: UUID) async throws -> CompanionWindowMutationState
    func readbackMutation(_ id: UUID) async throws -> Bool
}

/// Stops after an uncertain resize, never retries, and preserves mutations already attempted on cancellation.
public enum CompanionWindowLayoutMutation {
    public static func run(id: UUID, port: any CompanionWindowLayoutMutationPort) async throws -> CompanionWindowLayoutReceipt {
        try await port.validateMutation(id)
        let resize = try await port.resizeMutation(id)
        var position = CompanionWindowMutationState.notAttempted
        if resize == .accepted {
            do {
                try await port.validateMutation(id)
                position = try await port.positionMutation(id)
            } catch {
                return .init(resizeState: resize, positionState: .notAttempted)
            }
        }
        guard resize != .refused else { return .init(resizeState: resize, positionState: position) }
        do {
            let matches = try await port.readbackMutation(id)
            return .init(resizeState: resize, positionState: position, readbackMatches: matches, readbackAvailable: true)
        } catch {
            return .init(resizeState: resize, positionState: position)
        }
    }
}
