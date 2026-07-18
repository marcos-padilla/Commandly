import AppCore
import CommandKit
import Foundation
import Infrastructure

/// App-layer failures from dispatching a resolved shared command.
///
/// Cases intentionally exclude command arguments, bundle identifiers, paths, and underlying
/// infrastructure error text so they are safe to surface in diagnostics.
enum SharedCommandExecutorError: Error, Equatable, Sendable {
    case invalidInstalledApplicationReference
    case applicationOpenFailed
    case registeredApplicationUnavailable(CommandID)
}

/// Typed failures from the complete resolve → execute → history pipeline.
enum SharedCommandExecutionCoordinatorError: Error, Equatable, Sendable {
    case registry(CommandRegistryError)
    case unavailable(commandID: CommandID, reason: CommandUnavailableReason)
    case executor(SharedCommandExecutorError)
    case resolutionFailed(CommandID)
    case executionFailed(CommandID)

    /// Sanitized feedback shared by launcher search, hotkeys, and Command Wheel.
    var userFacingMessage: String {
        switch self {
        case .registry(.commandNotFound), .unavailable:
            return "Command is unavailable."
        case .registry:
            return "Command arguments are invalid."
        case .executor(.invalidInstalledApplicationReference):
            return "That application reference is invalid."
        case .executor(.applicationOpenFailed):
            return "Couldn’t open that application."
        case .executor(.registeredApplicationUnavailable):
            return "Application is not registered."
        case .resolutionFailed:
            return "Command couldn’t be resolved."
        case .executionFailed:
            return "Command couldn’t be completed."
        }
    }
}

/// Shared entry point used by launcher search, application hotkeys, and Command Wheel references.
nonisolated protocol SharedCommandExecutionCoordinating: Sendable {
    @discardableResult
    func execute(
        reference: CommandReference,
        context: CommandInvocationContext
    ) async throws -> CommandResult
}

/// Main-actor boundary that presents a registered launcher application without teaching the
/// executor about concrete feature views or sessions.
@MainActor
protocol RegisteredLauncherApplicationPresenting: AnyObject, Sendable {
    /// Returns `nil` when no registered application can present `commandID`.
    func presentRegisteredApplication(commandID: CommandID) -> CommandResult?
}

/// Late-bound presentation bridge used to break the runtime/coordinator/view-model ownership cycle.
@MainActor
final class RegisteredLauncherApplicationPresentationHandler:
    RegisteredLauncherApplicationPresenting
{
    private var handler: ((CommandID) -> CommandResult?)?

    func install(handler: @escaping (CommandID) -> CommandResult?) {
        self.handler = handler
    }

    func presentRegisteredApplication(commandID: CommandID) -> CommandResult? {
        handler?(commandID)
    }
}

/// Updates the existing installed-application search ranking after a successful shared execution.
@MainActor
protocol InstalledApplicationUsageRecording: AnyObject, Sendable {
    func recordSuccessfulOpen(bundleIdentifier: String, at timestamp: Date)
}

/// Preserves existing installed-app ranking while every invocation surface uses one executor.
@MainActor
final class ApplicationPreferencesInstalledApplicationUsageRecorder:
    InstalledApplicationUsageRecording
{
    private let preferencesStore: any ApplicationPreferencesStoring

    init(preferencesStore: any ApplicationPreferencesStoring) {
        self.preferencesStore = preferencesStore
    }

    func recordSuccessfulOpen(bundleIdentifier: String, at timestamp: Date) {
        var preferences = preferencesStore.load()
        var ranking = preferences.ranking(for: bundleIdentifier)
        ranking.openCount += 1
        ranking.lastOpenedAt = timestamp
        preferences.ranking[bundleIdentifier] = ranking
        preferencesStore.save(preferences)
    }
}

/// Concrete shared executor for immediate engine actions and registered application presentation.
struct SharedCommandExecutor: CommandExecuting {
    private let applicationOpener: any ApplicationOpening
    private let registeredApplicationPresenter: any RegisteredLauncherApplicationPresenting
    private let installedApplicationUsageRecorder: any InstalledApplicationUsageRecording

    init(
        applicationOpener: any ApplicationOpening,
        registeredApplicationPresenter: any RegisteredLauncherApplicationPresenting,
        installedApplicationUsageRecorder: any InstalledApplicationUsageRecording
    ) {
        self.applicationOpener = applicationOpener
        self.registeredApplicationPresenter = registeredApplicationPresenter
        self.installedApplicationUsageRecorder = installedApplicationUsageRecorder
    }

    func execute(
        _ command: ResolvedCommand,
        context: CommandInvocationContext
    ) async throws -> CommandResult {
        try Task.checkCancellation()

        if command.reference.commandID == BuiltInCommandID.openInstalledApplication {
            return try await openInstalledApplication(command, context: context)
        }

        guard let result = await registeredApplicationPresenter.presentRegisteredApplication(
            commandID: command.reference.commandID
        ) else {
            throw SharedCommandExecutorError.registeredApplicationUnavailable(
                command.reference.commandID
            )
        }
        return result
    }

    private func openInstalledApplication(
        _ command: ResolvedCommand,
        context: CommandInvocationContext
    ) async throws -> CommandResult {
        guard case .string(let bundleIdentifier)? = command.reference.arguments[
            BuiltInCommandArgumentName.bundleIdentifier
        ],
        bundleIdentifier.isEmpty == false,
        bundleIdentifier == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SharedCommandExecutorError.invalidInstalledApplicationReference
        }

        do {
            try await applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SharedCommandExecutorError.applicationOpenFailed
        }

        await installedApplicationUsageRecorder.recordSuccessfulOpen(
            bundleIdentifier: bundleIdentifier,
            at: context.timestamp
        )
        return .success(message: nil)
    }
}

/// Actor that resolves one persisted reference, validates availability, executes it once, and
/// records only privacy-safe completion metadata.
actor SharedCommandExecutionCoordinator: SharedCommandExecutionCoordinating {
    typealias CatalogSynchronizer = @Sendable () async throws -> Void

    private let resolver: any CommandResolving
    private let executor: any CommandExecuting
    private let usageHistory: any CommandUsageHistoryStoring
    private let dateProvider: any DateProviding
    private let catalogRefreshCoordinator: CoalescingCatalogRefreshCoordinator?

    init(
        resolver: any CommandResolving,
        executor: any CommandExecuting,
        usageHistory: any CommandUsageHistoryStoring,
        dateProvider: any DateProviding = SystemDateProvider(),
        catalogSynchronizer: CatalogSynchronizer? = nil
    ) {
        self.resolver = resolver
        self.executor = executor
        self.usageHistory = usageHistory
        self.dateProvider = dateProvider
        self.catalogRefreshCoordinator = catalogSynchronizer.map {
            CoalescingCatalogRefreshCoordinator(operation: $0)
        }
    }

    /// Serializes and coalesces catalog refreshes when a runtime catalog source was supplied.
    func refreshCatalog() async throws {
        try await catalogRefreshCoordinator?.refresh()
    }

    @discardableResult
    func execute(
        reference: CommandReference,
        context: CommandInvocationContext
    ) async throws -> CommandResult {
        var didResolve = false
        do {
            try Task.checkCancellation()
            try await refreshCatalog()
            let resolved = try await resolver.resolve(reference: reference)
            didResolve = true
            if case .unavailable(let reason) = resolved.availability {
                throw SharedCommandExecutionCoordinatorError.unavailable(
                    commandID: reference.commandID,
                    reason: reason
                )
            }
            let result = try await executor.execute(resolved, context: context)
            await record(
                commandID: reference.commandID,
                source: context.source,
                outcome: result.executionOutcome
            )
            return result
        } catch is CancellationError {
            await record(
                commandID: reference.commandID,
                source: context.source,
                outcome: .cancelled
            )
            throw CancellationError()
        } catch let error as SharedCommandExecutionCoordinatorError {
            await recordFailure(for: reference, context: context)
            throw error
        } catch let error as CommandRegistryError {
            await recordFailure(for: reference, context: context)
            throw SharedCommandExecutionCoordinatorError.registry(error)
        } catch let error as SharedCommandExecutorError {
            await recordFailure(for: reference, context: context)
            throw SharedCommandExecutionCoordinatorError.executor(error)
        } catch {
            await recordFailure(for: reference, context: context)
            if didResolve {
                throw SharedCommandExecutionCoordinatorError.executionFailed(reference.commandID)
            }
            throw SharedCommandExecutionCoordinatorError.resolutionFailed(reference.commandID)
        }
    }

    private func recordFailure(
        for reference: CommandReference,
        context: CommandInvocationContext
    ) async {
        await record(commandID: reference.commandID, source: context.source, outcome: .failed)
    }

    private func record(
        commandID: CommandID,
        source: CommandInvocationSource,
        outcome: CommandExecutionOutcome
    ) async {
        await usageHistory.record(
            CommandExecutionRecord(
                commandID: commandID,
                source: source,
                outcome: outcome,
                timestamp: dateProvider.now()
            )
        )
    }

}
