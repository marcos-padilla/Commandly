import Foundation

/// Serializes catalog refresh publication while coalescing requests that arrive during a pass.
///
/// A pass covers the complete injected operation, including snapshot evaluation and publication.
/// Requests made while that pass is suspended wait for exactly one newer pass, so an older
/// snapshot can never publish after a newer snapshot from this coordinator. Successful callers
/// remain suspended until publication catches up with every request admitted during their wait.
actor CoalescingCatalogRefreshCoordinator {
    typealias Operation = @Sendable () async throws -> Void

    private struct ActivePass {
        let targetGeneration: UInt64
        let task: Task<Void, any Error>
    }

    private let operation: Operation
    private var requestedGeneration: UInt64 = 0
    private var publishedGeneration: UInt64 = 0
    private var activePass: ActivePass?

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    /// Number of refresh requests admitted by the actor.
    ///
    /// This read-only value lets concurrency tests establish request ordering without sleeps.
    var requestedRefreshCount: UInt64 {
        requestedGeneration
    }

    func refresh() async throws {
        try Task.checkCancellation()
        requestedGeneration += 1
        let requiredGeneration = requestedGeneration

        while publishedGeneration < requestedGeneration {
            let pass = activePass ?? startPass(targetGeneration: requestedGeneration)

            do {
                try await pass.task.value
            } catch {
                finish(pass)
                if requiredGeneration <= pass.targetGeneration {
                    throw error
                }
                try Task.checkCancellation()
                continue
            }

            if activePass?.targetGeneration == pass.targetGeneration {
                activePass = nil
                publishedGeneration = max(publishedGeneration, pass.targetGeneration)
            }
            try Task.checkCancellation()
        }
    }

    private func startPass(targetGeneration: UInt64) -> ActivePass {
        let operation = operation
        let pass = ActivePass(
            targetGeneration: targetGeneration,
            task: Task {
                try await operation()
            }
        )
        activePass = pass
        return pass
    }

    private func finish(_ pass: ActivePass) {
        if activePass?.targetGeneration == pass.targetGeneration {
            activePass = nil
        }
    }

    isolated deinit {
        activePass?.task.cancel()
    }
}
