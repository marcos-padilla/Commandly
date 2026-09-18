import AIKit
import CommandKit
import Foundation
import ModuleKit
import Testing
@testable import AICommandBridge

// MARK: - Fakes
//
// Every test here uses a fake dispatcher. No provider adapter, network call, or paid API is
// involved: the bridge is proven offline.

@MainActor
final class RecordingDispatcher: ModuleCommandDispatching {
    struct Call: Equatable {
        let reference: CommandReference
        let grants: ModuleCallerGrants
    }

    private(set) var calls: [Call] = []
    var outcome: ModuleCommandOutcome = .succeeded(message: "ok", output: .empty)

    func dispatch(
        reference: CommandReference,
        grants: ModuleCallerGrants,
        context: CommandInvocationContext
    ) async -> ModuleCommandOutcome {
        calls.append(Call(reference: reference, grants: grants))
        return outcome
    }
}

@MainActor
final class ToggleableEligibility: AICommandEligibilityEvaluating {
    var blocked: Set<CommandID> = []

    func isEligible(_ definition: ModuleCommandDefinition) -> Bool {
        definition.policy.aiExposure == .reviewed && blocked.contains(definition.id) == false
    }
}

@MainActor
enum BridgeFixture {
    static func definition(
        id: String,
        exposure: ModuleCommandAIExposure,
        arguments: [CommandArgument] = [],
        effect: ModuleCommandEffect = .localMutation,
        disclosure: ModuleCommandDisclosure = .none,
        requiresExactApproval: Bool = false
    ) -> ModuleCommandDefinition {
        ModuleCommandDefinition(
            manifest: CommandManifest(
                id: CommandID(rawValue: id),
                title: id,
                systemImage: "circle",
                category: .productivity,
                mode: .action,
                arguments: arguments
            ),
            summary: "Summary for \(id).",
            policy: ModuleCommandPolicy(
                executionMode: .direct,
                effect: effect,
                disclosure: disclosure,
                aiExposure: exposure,
                requiresExactApproval: requiresExactApproval
            )
        )
    }

    static let durationArgument = CommandArgument(
        name: "durationSeconds",
        description: "Length in seconds.",
        isRequired: true,
        valueType: .integer
    )

    static let titleArgument = CommandArgument(
        name: "title",
        description: "Optional name.",
        isRequired: false,
        valueType: .string
    )

    static func context() -> CommandInvocationContext {
        CommandInvocationContext(source: .search, timestamp: Date(timeIntervalSince1970: 0))
    }

    static func call(_ name: String, _ arguments: [String: AIJSONValue]) -> AIToolCall {
        AIToolCall(id: "call-1", name: name, arguments: .object(arguments))
    }
}

// MARK: - Default-deny exposure

@MainActor
struct AIExposurePolicyTests {
    @Test func hiddenCommandsAreNeverExposed() throws {
        let definitions = [
            BridgeFixture.definition(id: "a.hidden", exposure: .hidden),
            BridgeFixture.definition(id: "a.reviewed", exposure: .reviewed)
        ]
        let bridge = AICommandBridge(
            definitions: { definitions },
            dispatcher: RecordingDispatcher()
        )

        #expect(bridge.exposedDefinitions().map(\.id.rawValue) == ["a.reviewed"])
        #expect(try bridge.availableTools().map(\.name) == ["a_reviewed"])
    }

    @Test func aCatalogWithoutReviewedCommandsExposesNothing() throws {
        let definitions = [
            BridgeFixture.definition(id: "a.one", exposure: .hidden),
            BridgeFixture.definition(id: "a.two", exposure: .hidden)
        ]
        let bridge = AICommandBridge(
            definitions: { definitions },
            dispatcher: RecordingDispatcher()
        )
        #expect(try bridge.availableTools().isEmpty)
    }

    @Test func runtimeEligibilityCanWithdrawAReviewedCommand() throws {
        let definition = BridgeFixture.definition(id: "a.reviewed", exposure: .reviewed)
        let eligibility = ToggleableEligibility()
        let bridge = AICommandBridge(
            definitions: { [definition] },
            dispatcher: RecordingDispatcher(),
            eligibility: eligibility
        )
        #expect(try bridge.availableTools().count == 1)

        eligibility.blocked = [definition.id]
        #expect(try bridge.availableTools().isEmpty)
    }

    @Test func invokingAHiddenCommandIsRejectedWithoutDispatch() async {
        let dispatcher = RecordingDispatcher()
        let bridge = AICommandBridge(
            definitions: { [BridgeFixture.definition(id: "a.hidden", exposure: .hidden)] },
            dispatcher: dispatcher
        )

        let result = await bridge.invoke(
            BridgeFixture.call("a_hidden", [:]),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func invokingAWithdrawnCommandIsRejectedWithoutDispatch() async {
        let definition = BridgeFixture.definition(id: "a.reviewed", exposure: .reviewed)
        let eligibility = ToggleableEligibility()
        eligibility.blocked = [definition.id]
        let dispatcher = RecordingDispatcher()
        let bridge = AICommandBridge(
            definitions: { [definition] },
            dispatcher: dispatcher,
            eligibility: eligibility
        )

        let result = await bridge.invoke(
            BridgeFixture.call("a_reviewed", [:]),
            context: BridgeFixture.context()
        )
        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }
}

// MARK: - Naming

struct AICommandToolNamingTests {
    @Test func namesArePortableAndReversible() throws {
        let map = try AICommandToolNameMap(commandIDs: [
            CommandID(rawValue: "timers.start"),
            CommandID(rawValue: "clipboard.history")
        ])
        #expect(map.name(for: CommandID(rawValue: "timers.start")) == "timers_start")
        #expect(map.commandID(forToolName: "timers_start") == CommandID(rawValue: "timers.start"))
        #expect(map.commandID(forToolName: "unknown_tool") == nil)
    }

    @Test func namingIsDeterministicRegardlessOfInputOrder() throws {
        let ids = [
            CommandID(rawValue: "b.two"),
            CommandID(rawValue: "a.one"),
            CommandID(rawValue: "c.three")
        ]
        let forward = try AICommandToolNameMap(commandIDs: ids)
        let reversed = try AICommandToolNameMap(commandIDs: ids.reversed())
        for id in ids {
            #expect(forward.name(for: id) == reversed.name(for: id))
        }
    }

    @Test func collidingIdentifiersAreRejectedRatherThanSilentlyMerged() {
        // Both normalize to "timers_start": the map must refuse instead of losing one command.
        #expect(throws: (any Error).self) {
            _ = try AICommandToolNameMap(commandIDs: [
                CommandID(rawValue: "timers.start"),
                CommandID(rawValue: "timers/start")
            ])
        }
    }

    @Test func duplicateIdentifiersAreIdempotent() throws {
        let map = try AICommandToolNameMap(commandIDs: [
            CommandID(rawValue: "timers.start"),
            CommandID(rawValue: "timers.start")
        ])
        #expect(map.count == 1)
    }
}

// MARK: - Schema and validation agreement

@MainActor
struct AISchemaValidationTests {
    private func bridge(
        _ definition: ModuleCommandDefinition,
        dispatcher: RecordingDispatcher
    ) -> AICommandBridge {
        AICommandBridge(definitions: { [definition] }, dispatcher: dispatcher)
    }

    @Test func schemaMarksRequiredArgumentsAndValidatesCleanly() throws {
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument, BridgeFixture.titleArgument]
        )
        let tool = try #require(
            try bridge(definition, dispatcher: RecordingDispatcher()).availableTools().first
        )
        try tool.validate()

        guard case .object(let properties, let required, let additional, _) = tool.inputSchema else {
            Issue.record("Expected an object schema.")
            return
        }
        #expect(Set(properties.keys) == ["durationSeconds", "title"])
        #expect(required == ["durationSeconds"])
        #expect(additional == false)
    }

    @Test func missingRequiredArgumentIsRejectedBeforeDispatch() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument]
        )
        let result = await bridge(definition, dispatcher: dispatcher)
            .invoke(BridgeFixture.call("a_op", [:]), context: BridgeFixture.context())

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func unknownArgumentIsRejectedBeforeDispatch() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument]
        )
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            BridgeFixture.call("a_op", ["durationSeconds": .number(60), "surprise": .boolean(true)]),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func fractionalValueIsRejectedForAWholeNumberArgument() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument]
        )
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            BridgeFixture.call("a_op", ["durationSeconds": .number(5.5)]),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func wrongTypeIsRejectedBeforeDispatch() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument]
        )
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            BridgeFixture.call("a_op", ["durationSeconds": .string("sixty")]),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func nonObjectArgumentsAreRejected() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(id: "a.op", exposure: .reviewed)
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            AIToolCall(id: "call-1", name: "a_op", arguments: .string("nope")),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func oversizedArgumentsAreRejectedBeforeDispatch() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.titleArgument]
        )
        let huge = String(repeating: "x", count: AICommandBridge.maximumArgumentBytes + 64)
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            BridgeFixture.call("a_op", ["title": .string(huge)]),
            context: BridgeFixture.context()
        )

        #expect(result.isError)
        #expect(dispatcher.calls.isEmpty)
    }

    @Test func acceptedCallReachesTheSharedDispatcherWithValidatedArguments() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            arguments: [BridgeFixture.durationArgument, BridgeFixture.titleArgument]
        )
        let result = await bridge(definition, dispatcher: dispatcher).invoke(
            BridgeFixture.call("a_op", ["durationSeconds": .number(90), "title": .string("Focus")]),
            context: BridgeFixture.context()
        )

        #expect(result.isError == false)
        #expect(dispatcher.calls.count == 1)
        #expect(dispatcher.calls[0].reference.commandID == CommandID(rawValue: "a.op"))
        #expect(dispatcher.calls[0].reference.arguments["durationSeconds"] == .integer(90))
        #expect(dispatcher.calls[0].reference.arguments["title"] == .string("Focus"))
    }
}

// MARK: - Authority

@MainActor
struct AIAuthorityTests {
    @Test func modelArgumentsCannotForgeUserProvenance() async {
        let dispatcher = RecordingDispatcher()
        let definition = BridgeFixture.definition(id: "a.op", exposure: .reviewed)
        let bridge = AICommandBridge(definitions: { [definition] }, dispatcher: dispatcher)

        // A model cannot smuggle grants through arguments; the host supplies them.
        _ = await bridge.invoke(
            BridgeFixture.call("a_op", [:]),
            context: BridgeFixture.context()
        )

        #expect(dispatcher.calls.count == 1)
        #expect(dispatcher.calls[0].grants == [.automation])
        #expect(dispatcher.calls[0].grants.contains(.userInitiated) == false)
    }

    @Test func approvalRequirementIsCarriedToTheProviderDefinition() throws {
        let definition = BridgeFixture.definition(
            id: "a.op",
            exposure: .reviewed,
            effect: .filesystemMutation,
            requiresExactApproval: true
        )
        let bridge = AICommandBridge(
            definitions: { [definition] },
            dispatcher: RecordingDispatcher()
        )
        let tool = try #require(try bridge.availableTools().first)
        #expect(tool.confirmation == .always)
        #expect(tool.effect == .destructive)
    }
}

// MARK: - Result truthfulness

@MainActor
struct AIResultTests {
    private func invoke(outcome: ModuleCommandOutcome) async -> AIToolResult {
        let dispatcher = RecordingDispatcher()
        dispatcher.outcome = outcome
        let bridge = AICommandBridge(
            definitions: { [BridgeFixture.definition(id: "a.op", exposure: .reviewed)] },
            dispatcher: dispatcher
        )
        return await bridge.invoke(
            BridgeFixture.call("a_op", [:]),
            context: BridgeFixture.context()
        )
    }

    private func status(_ result: AIToolResult) -> String? {
        guard case .object(let payload) = result.content,
              case .string(let status)? = payload["status"] else {
            return nil
        }
        return status
    }

    @Test func interactionRequiredIsNotReportedAsSuccess() async {
        let result = await invoke(outcome: .interactionRequired(message: "Needs the window."))
        #expect(status(result) == "interaction_required")
        #expect(result.isError)
    }

    @Test func denialIsReportedWithItsReason() async {
        let result = await invoke(
            outcome: .denied(reason: .approvalInvalid, message: "Approval expired.")
        )
        #expect(status(result) == "denied")
        #expect(result.isError)
        guard case .object(let payload) = result.content,
              case .string(let reason)? = payload["reason"] else {
            Issue.record("Expected a denial reason.")
            return
        }
        #expect(reason == ModuleCommandDenialReason.approvalInvalid.rawValue)
    }

    @Test func unavailableIsNotReportedAsSuccess() async {
        let result = await invoke(outcome: .unavailable(reason: .disabled, message: "Turned off."))
        #expect(status(result) == "unavailable")
        #expect(result.isError)
    }

    @Test func acceptedLongRunningWorkIsNotReportedAsCompleted() async {
        let result = await invoke(
            outcome: .accepted(
                operationID: ModuleOperationID(rawValue: "op-7"),
                message: "Recording started."
            )
        )
        #expect(status(result) == "accepted")
        #expect(result.isError == false)
    }

    @Test func cancellationIsReported() async {
        let result = await invoke(outcome: .cancelled)
        #expect(status(result) == "cancelled")
    }

    @Test func structuredOutputIsCarriedBack() async {
        let result = await invoke(
            outcome: .succeeded(
                message: "Started.",
                output: ModuleCommandOutput([
                    "timerID": .string("ABC"),
                    "durationSeconds": .integer(60)
                ])
            )
        )
        #expect(status(result) == "succeeded")
        guard case .object(let payload) = result.content,
              case .object(let output)? = payload["output"] else {
            Issue.record("Expected structured output.")
            return
        }
        #expect(output["timerID"] == .string("ABC"))
        #expect(output["durationSeconds"] == .number(60))
    }
}
