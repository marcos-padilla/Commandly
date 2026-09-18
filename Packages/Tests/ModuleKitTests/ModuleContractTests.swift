import CommandKit
import Foundation
import Testing
@testable import ModuleKit

struct ModuleCommandPolicyTests {
    @Test func aiExposureDefaultsToHidden() {
        let policy = ModuleCommandPolicy(executionMode: .direct, effect: .localMutation)
        #expect(policy.aiExposure == .hidden)
    }

    @Test func nonIdempotentIsTheDefault() {
        let policy = ModuleCommandPolicy(executionMode: .direct, effect: .localMutation)
        #expect(policy.isIdempotent == false)
        #expect(policy.requiresExactApproval == false)
    }
}

struct ModuleCallerGrantsTests {
    private func policy(
        effect: ModuleCommandEffect,
        disclosure: ModuleCommandDisclosure = .none
    ) -> ModuleCommandPolicy {
        ModuleCommandPolicy(executionMode: .direct, effect: effect, disclosure: disclosure)
    }

    @Test func anonymousCallerIsRejected() {
        let grants: ModuleCallerGrants = []
        #expect(grants.satisfy(policy(effect: .readOnly)) == false)
    }

    @Test func automationSatisfiesLocalMutation() {
        let grants: ModuleCallerGrants = [.automation]
        #expect(grants.satisfy(policy(effect: .localMutation)))
    }

    @Test func automationAloneCannotMutateTheFilesystem() {
        let grants: ModuleCallerGrants = [.automation]
        #expect(grants.satisfy(policy(effect: .filesystemMutation)) == false)
        #expect(grants.union(.filesystemMutation).satisfy(policy(effect: .filesystemMutation)))
    }

    @Test func automationAloneCannotTakeExternalAction() {
        let grants: ModuleCallerGrants = [.automation]
        #expect(grants.satisfy(policy(effect: .externalAction)) == false)
        #expect(grants.union(.externalAction).satisfy(policy(effect: .externalAction)))
    }

    @Test func privateContentRequiresDisclosureGrant() {
        let grants: ModuleCallerGrants = [.automation]
        let disclosing = policy(effect: .readOnly, disclosure: .localPrivateContent)
        #expect(grants.satisfy(disclosing) == false)
        #expect(grants.union(.sensitiveDisclosure).satisfy(disclosing))
    }

    @Test func directUserCarriesEveryEffectGrant() {
        #expect(ModuleCallerGrants.directUser.satisfy(policy(effect: .filesystemMutation)))
        #expect(ModuleCallerGrants.directUser.satisfy(policy(effect: .externalAction)))
        #expect(
            ModuleCallerGrants.directUser
                .satisfy(policy(effect: .readOnly, disclosure: .remoteDisclosureAllowed))
        )
    }
}

struct ModuleCommandOutcomeTests {
    @Test func successProjectsToSuccess() {
        let outcome = ModuleCommandOutcome.succeeded(message: "done", output: .empty)
        #expect(outcome.commandResult == .success(message: "done"))
        #expect(outcome.didCompleteEffect)
    }

    @Test func cancellationProjectsToCancelled() {
        #expect(ModuleCommandOutcome.cancelled.commandResult == .cancelled)
    }

    @Test func interactionRequiredIsNotSuccess() {
        let outcome = ModuleCommandOutcome.interactionRequired(message: "Needs the window.")
        #expect(outcome.didCompleteEffect == false)
        #expect(outcome.commandResult == .failure(message: "Needs the window."))
    }

    @Test func denialIsNotSuccess() {
        let outcome = ModuleCommandOutcome.denied(
            reason: .missingCallerGrant,
            message: "Not allowed."
        )
        #expect(outcome.didCompleteEffect == false)
        #expect(outcome.commandResult == .failure(message: "Not allowed."))
    }

    @Test func acceptedIsNotACompletedEffect() {
        let outcome = ModuleCommandOutcome.accepted(
            operationID: ModuleOperationID(rawValue: "op-1"),
            message: "Recording."
        )
        #expect(outcome.didCompleteEffect == false)
        #expect(outcome.commandResult == .success(message: "Recording."))
    }

    @Test func historyOutcomesStayPrivacySafe() {
        let denied = ModuleCommandOutcome.denied(reason: .approvalInvalid, message: "Stale.")
        #expect(denied.commandResult.executionOutcome == .failed)
        let unavailable = ModuleCommandOutcome.unavailable(
            reason: .disabled,
            message: "Turned off."
        )
        #expect(unavailable.commandResult.executionOutcome == .failed)
    }
}

struct ModuleAvailabilityTests {
    @Test func availableHasNoUnavailableReason() {
        #expect(ModuleAvailability.available.isAvailable)
        #expect(ModuleAvailability.available.unavailableReason == nil)
    }

    @Test func statesProjectOntoSharedReasons() {
        #expect(ModuleAvailability.disabled.unavailableReason == .disabled)
        #expect(
            ModuleAvailability.permissionRequired(identifier: "screen")
                .unavailableReason == .missingPermission(identifier: "screen")
        )
        #expect(
            ModuleAvailability.disconnected(identifier: "notion")
                .unavailableReason == .missingDependency(identifier: "notion")
        )
        #expect(ModuleAvailability.unsupported(reason: "x").unavailableReason == .unsupported)
        #expect(
            ModuleAvailability.busy(reason: "recording")
                .unavailableReason == .temporarilyUnavailable
        )
        #expect(ModuleAvailability.interactiveOnly.unavailableReason == .invalidContext)
    }
}

struct ModuleConfigurationFieldKindTests {
    @Test func kindsRejectMismatchedValues() {
        #expect(ModuleConfigurationFieldKind.toggle.accepts(.boolean(true)))
        #expect(ModuleConfigurationFieldKind.toggle.accepts(.text("true")) == false)
        #expect(ModuleConfigurationFieldKind.selection.accepts(.text("a")))
        #expect(ModuleConfigurationFieldKind.integer.accepts(.decimal(1)) == false)
    }
}
