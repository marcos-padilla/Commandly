import AppCore
import CommandKit
import Testing
@testable import Commandly

struct SharedCommandExecutionCatalogRefreshTests {
    @Test
    func requestsDuringAnAwaitPublishOneNewerGenerationBeforeAnySuccess() async throws {
        let commandID = CommandID(rawValue: "test.catalog-refresh-order")
        let oldSnapshot = commandCatalogSnapshot(
            commandID: commandID,
            title: "Old Catalog"
        )
        let newSnapshot = commandCatalogSnapshot(
            commandID: commandID,
            title: "New Catalog"
        )
        let source = ControlledCommandCatalogSnapshotSource()
        let registry = CommandRegistry()
        let refreshCoordinator = CoalescingCatalogRefreshCoordinator {
            let snapshot = try await source.snapshot()
            try await registry.replaceCatalog(
                with: snapshot.manifests,
                availability: snapshot.availability
            )
        }
        let completionProbe = CatalogRefreshCompletionProbe()

        let firstRefresh = Task {
            try await refreshCoordinator.refresh()
            await completionProbe.recordFirstSuccess()
        }
        await source.waitUntilCallCount(1)

        let secondRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        let thirdRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        await waitUntilRefreshRequestCount(3, coordinator: refreshCoordinator)

        #expect(await source.callCount == 1)
        await source.succeed(pass: 1, with: oldSnapshot)
        await source.waitUntilCallCount(2)

        #expect(await source.callCount == 2)
        #expect(await registry.catalogSnapshot() == oldSnapshot)
        #expect(await completionProbe.didRecordFirstSuccess == false)

        await source.succeed(pass: 2, with: newSnapshot)
        try await firstRefresh.value
        try await secondRefresh.value
        try await thirdRefresh.value

        #expect(await source.callCount == 2)
        #expect(await registry.catalogSnapshot() == newSnapshot)
        #expect(await completionProbe.didRecordFirstSuccess)
    }

    @Test
    func failedPassRejectsIncludedCallersButPreservesANewerRequest() async throws {
        let commandID = CommandID(rawValue: "test.catalog-refresh-recovery")
        let recoveredSnapshot = commandCatalogSnapshot(
            commandID: commandID,
            title: "Recovered Catalog"
        )
        let source = ControlledCommandCatalogSnapshotSource()
        let registry = CommandRegistry()
        let refreshCoordinator = CoalescingCatalogRefreshCoordinator {
            let snapshot = try await source.snapshot()
            try await registry.replaceCatalog(
                with: snapshot.manifests,
                availability: snapshot.availability
            )
        }

        let failedRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        await source.waitUntilCallCount(1)

        let recoveryRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        await waitUntilRefreshRequestCount(2, coordinator: refreshCoordinator)
        #expect(await source.callCount == 1)

        await source.fail(pass: 1)
        await #expect(throws: CatalogRefreshTestError.self) {
            try await failedRefresh.value
        }
        await source.waitUntilCallCount(2)

        #expect(await source.callCount == 2)
        await source.succeed(pass: 2, with: recoveredSnapshot)
        try await recoveryRefresh.value

        #expect(await source.callCount == 2)
        #expect(await registry.catalogSnapshot() == recoveredSnapshot)
    }

    @Test
    func callerIncludedInAnOlderSuccessObservesANewerPassFailure() async throws {
        let oldSnapshot = commandCatalogSnapshot(
            commandID: CommandID(rawValue: "test.catalog-refresh-late-failure"),
            title: "Old Catalog"
        )
        let source = ControlledCommandCatalogSnapshotSource()
        let refreshCoordinator = CoalescingCatalogRefreshCoordinator {
            _ = try await source.snapshot()
        }

        let firstRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        await source.waitUntilCallCount(1)

        let newerRefresh = Task {
            try await refreshCoordinator.refresh()
        }
        await waitUntilRefreshRequestCount(2, coordinator: refreshCoordinator)

        await source.succeed(pass: 1, with: oldSnapshot)
        await source.waitUntilCallCount(2)
        await source.fail(pass: 2)

        await #expect(throws: CatalogRefreshTestError.self) {
            try await firstRefresh.value
        }
        await #expect(throws: CatalogRefreshTestError.self) {
            try await newerRefresh.value
        }
        #expect(await source.callCount == 2)
    }
}

private enum CatalogRefreshTestError: Error {
    case failed
}

private func commandCatalogSnapshot(
    commandID: CommandID,
    title: String
) -> CommandCatalogSnapshot {
    CommandCatalogSnapshot(
        manifests: [
            CommandManifest(
                id: commandID,
                title: title,
                systemImage: "arrow.triangle.2.circlepath",
                category: .productivity,
                mode: .action
            )
        ]
    )
}

private func waitUntilRefreshRequestCount(
    _ expectedCount: UInt64,
    coordinator: CoalescingCatalogRefreshCoordinator
) async {
    while await coordinator.requestedRefreshCount < expectedCount {
        await Task.yield()
    }
}

private actor CatalogRefreshCompletionProbe {
    private(set) var didRecordFirstSuccess = false

    func recordFirstSuccess() {
        didRecordFirstSuccess = true
    }
}

private actor ControlledCommandCatalogSnapshotSource {
    private struct CallCountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private(set) var callCount = 0
    private var pendingPasses: [
        Int: CheckedContinuation<CommandCatalogSnapshot, any Error>
    ] = [:]
    private var callCountWaiters: [CallCountWaiter] = []

    func snapshot() async throws -> CommandCatalogSnapshot {
        callCount += 1
        let pass = callCount
        resumeSatisfiedCallCountWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pendingPasses[pass] = continuation
        }
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        if callCount >= expectedCount { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append(
                CallCountWaiter(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
        }
    }

    func succeed(pass: Int, with snapshot: CommandCatalogSnapshot) {
        pendingPasses.removeValue(forKey: pass)?.resume(returning: snapshot)
    }

    func fail(pass: Int) {
        pendingPasses.removeValue(forKey: pass)?.resume(
            throwing: CatalogRefreshTestError.failed
        )
    }

    private func resumeSatisfiedCallCountWaiters() {
        var remaining: [CallCountWaiter] = []
        for waiter in callCountWaiters {
            if callCount >= waiter.expectedCount {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callCountWaiters = remaining
    }
}
