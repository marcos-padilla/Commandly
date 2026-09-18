import CommandKit
import Foundation
import ModuleKit
import AICommandBridge
import ModuleRuntime

/// Routes module command references through the application's existing shared executor.
///
/// This adapter is the **only** way the AI bridge reaches a command. It deliberately does not talk
/// to feature services, the launcher registry, or a module handler directly: everything goes
/// through ``SharedCommandExecutionCoordinating`` so resolution, availability gating, single
/// execution, and privacy-safe history behave exactly as they do for search, shortcuts, the
/// Command Wheel, and the menu bar.
@MainActor
final class SharedCommandModuleDispatcher: ModuleCommandDispatching {
    private let coordinator: any SharedCommandExecutionCoordinating
    private let host: ModuleHost

    /// Creates a dispatcher over the shared coordinator.
    init(coordinator: any SharedCommandExecutionCoordinating, host: ModuleHost) {
        self.coordinator = coordinator
        self.host = host
    }

    func dispatch(
        reference: CommandReference,
        grants: ModuleCallerGrants,
        context: CommandInvocationContext
    ) async -> ModuleCommandOutcome {
        guard let definition = host.commandDefinition(for: reference.commandID) else {
            return .unavailable(
                reason: .unsupported,
                message: "Command is unavailable."
            )
        }

        // Authorization is checked before any side effect, and the caller's grants — not the
        // arguments — decide whether the effect is permitted.
        guard grants.satisfy(definition.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to run that command."
            )
        }

        // A command that needs native UI cannot be completed for a non-interactive caller.
        if definition.policy.executionMode == .requiresUserInterface,
           grants.contains(.userInitiated) == false {
            return .interactionRequired(
                message: "That command needs Commandly’s window."
            )
        }

        // Re-check availability now rather than trusting an earlier preflight: enablement,
        // permissions, and connections can change while an approval is pending.
        let availability = host.availability(ofCommand: reference.commandID)
        if let reason = availability.unavailableReason {
            return .unavailable(reason: reason, message: "Command is unavailable.")
        }

        do {
            let result = try await coordinator.execute(reference: reference, context: context)
            switch result {
            case .success(let message):
                return .succeeded(message: message, output: .empty)
            case .failure(let message):
                return .failed(message: message)
            case .cancelled:
                return .cancelled
            }
        } catch is CancellationError {
            return .cancelled
        } catch let error as SharedCommandExecutionCoordinatorError {
            if case .unavailable(_, let reason) = error {
                return .unavailable(reason: reason, message: error.userFacingMessage)
            }
            return .failed(message: error.userFacingMessage)
        } catch {
            return .failed(message: "Command couldn’t be completed.")
        }
    }
}

/// Applies runtime AI eligibility on top of a command's build-time review decision.
///
/// A module being enabled is not an AI grant. A reviewed command is offered only while its module
/// is actually available: disabled, permission-blocked, disconnected, and failed modules withdraw
/// their tools.
@MainActor
final class ModuleHostAIEligibilityEvaluator: AICommandEligibilityEvaluating {
    private let host: ModuleHost

    /// Creates an evaluator over the module host.
    init(host: ModuleHost) {
        self.host = host
    }

    func isEligible(_ definition: ModuleCommandDefinition) -> Bool {
        guard definition.policy.aiExposure == .reviewed else { return false }
        // Interactive commands can never be completed by a model, so they are never offered.
        guard definition.policy.executionMode != .requiresUserInterface else { return false }
        return host.availability(ofCommand: definition.id).isAvailable
    }
}
