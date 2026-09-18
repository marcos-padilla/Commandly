import AIKit
import AICommandBridge
import CommandKit
import Foundation
import ModuleKit
import ModuleRuntime
import Testing
@testable import TimersModule

// MARK: - Deterministic fixtures
//
// Every test drives the store through injected date and UUID sources and disables automatic
// ticking, so no test depends on wall-clock time or on a run-loop timer.

@MainActor
final class TestClock {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
enum TimersFixture {
    static func store(
        clock: TestClock,
        automaticallySchedulesTicks: Bool = false
    ) -> TimerStore {
        var counter = 0
        return TimerStore(
            now: { clock.now },
            uuid: {
                counter += 1
                let suffix = String(format: "%012d", counter)
                return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") ?? UUID()
            },
            automaticallySchedulesTicks: automaticallySchedulesTicks,
            onCompletion: { _ in }
        )
    }

    static func invocation(
        _ arguments: [String: CommandArgumentValue],
        grants: ModuleCallerGrants = .directUser
    ) -> ModuleCommandInvocation {
        ModuleCommandInvocation(
            commandID: TimersModuleIdentifiers.startTool,
            arguments: CommandArguments(arguments),
            context: CommandInvocationContext(source: .search),
            grants: grants
        )
    }
}

// MARK: - Identifier compatibility

struct TimersIdentifierCompatibilityTests {
    @Test func shippedIdentifiersAreUnchanged() {
        #expect(TimersModuleIdentifiers.application.rawValue == "timers.focus")
        #expect(TimersModuleIdentifiers.openTool.rawValue == "timers.focus.tool.open")
        #expect(TimersModuleIdentifiers.newTimerTool.rawValue == "timers.new")
        #expect(TimersModuleIdentifiers.startTool.rawValue == "timers.start")
    }

    @Test func settingsVariableMatchesTheShippedPreferenceKey() {
        #expect(TimersSettings.completionSoundVariable == "completionSound")
    }

    @Test func newTimerStillMeansOpenADraft() {
        // Silently turning `timers.new` into "start a timer" would change a shipped command's
        // meaning and let a caller believe a countdown is running.
        #expect(TimersCommands.newTimer.policy.executionMode == .requiresUserInterface)
        #expect(TimersCommands.newTimer.policy.aiExposure == .hidden)
    }
}

// MARK: - Command policy

struct TimersCommandPolicyTests {
    @Test func onlyStartIsExposedToAI() {
        let exposed = TimersCommands.all
            .filter { $0.policy.aiExposure == .reviewed }
            .map(\.id.rawValue)
        #expect(exposed == ["timers.start"])
    }

    @Test func startIsADirectOperation() {
        #expect(TimersCommands.start.policy.executionMode == .direct)
        #expect(TimersCommands.start.policy.effect == .localMutation)
        #expect(TimersCommands.start.policy.disclosure == .none)
    }

    @Test func startIsNotIdempotent() {
        // Starting a timer twice creates two timers, so it must never be retried automatically.
        #expect(TimersCommands.start.policy.isIdempotent == false)
    }

    @Test func presentationCommandsAreHiddenFromAI() {
        let presentation = [
            TimersCommands.application, TimersCommands.open, TimersCommands.newTimer
        ]
        #expect(presentation.allSatisfy { $0.policy.aiExposure == .hidden })
    }

    @Test func manifestOwnsEveryDeclaredCommand() {
        #expect(Set(TimersModuleManifest.value.ownedCommandIDs) == Set(TimersCommands.all.map(\.id)))
    }
}

// MARK: - Input validation

@MainActor
struct TimerStartValidationTests {
    @Test func missingDurationIsRejected() {
        #expect(throws: TimerStartValidationError.missingDuration) {
            _ = try TimerStartRequest.validate(arguments: .empty)
        }
    }

    @Test func nonIntegerDurationIsRejected() {
        #expect(throws: TimerStartValidationError.missingDuration) {
            _ = try TimerStartRequest.validate(
                arguments: CommandArguments(["durationSeconds": .string("60")])
            )
        }
    }

    @Test func zeroAndNegativeDurationsAreRejected() {
        for seconds in [0, -1, Int.min] {
            #expect(throws: TimerStartValidationError.durationOutOfRange) {
                _ = try TimerStartRequest.validate(
                    arguments: CommandArguments(["durationSeconds": .integer(seconds)])
                )
            }
        }
    }

    @Test func overflowingDurationsAreRejected() {
        for seconds in [TimersDurationBounds.maximumSeconds + 1, Int.max] {
            #expect(throws: TimerStartValidationError.durationOutOfRange) {
                _ = try TimerStartRequest.validate(
                    arguments: CommandArguments(["durationSeconds": .integer(seconds)])
                )
            }
        }
    }

    @Test func boundsAreInclusive() throws {
        let minimum = try TimerStartRequest.validate(
            arguments: CommandArguments([
                "durationSeconds": .integer(TimersDurationBounds.minimumSeconds)
            ])
        )
        #expect(minimum.durationSeconds == TimersDurationBounds.minimumSeconds)

        let maximum = try TimerStartRequest.validate(
            arguments: CommandArguments([
                "durationSeconds": .integer(TimersDurationBounds.maximumSeconds)
            ])
        )
        #expect(maximum.durationSeconds == TimersDurationBounds.maximumSeconds)
    }

    @Test func titleIsTrimmed() throws {
        let request = try TimerStartRequest.validate(
            arguments: CommandArguments([
                "durationSeconds": .integer(60),
                "title": .string("  Deep Work  ")
            ])
        )
        #expect(request.title == "Deep Work")
    }

    @Test func nonTextTitleIsRejected() {
        #expect(throws: TimerStartValidationError.invalidTitle) {
            _ = try TimerStartRequest.validate(
                arguments: CommandArguments([
                    "durationSeconds": .integer(60),
                    "title": .integer(5)
                ])
            )
        }
    }
}

// MARK: - The direct operation

@MainActor
struct TimerStartOperationTests {
    @Test func startCreatesARunningTimerWithAStableIdentity() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation([
                "durationSeconds": .integer(600),
                "title": .string("Focus")
            ])
        )

        guard case .succeeded(_, let output) = outcome else {
            Issue.record("Expected the start operation to succeed. Got \(outcome).")
            return
        }
        #expect(output[TimersCommandOutputName.title] == .string("Focus"))
        #expect(output[TimersCommandOutputName.durationSeconds] == .integer(600))
        #expect(output[TimersCommandOutputName.phase] == .string(CountdownTimerPhase.running.rawValue))

        guard case .string(let rawID)? = output[TimersCommandOutputName.timerID],
              let id = UUID(uuidString: rawID) else {
            Issue.record("Expected a stable timer identifier.")
            return
        }
        #expect(store.timer(id: id)?.phase == .running)
        #expect(store.timers.count == 1)
    }

    @Test func endTimeReflectsTheRequestedDuration() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(300)])
        )

        guard case .succeeded(_, let output) = outcome,
              case .string(let endsAt)? = output[TimersCommandOutputName.endsAt] else {
            Issue.record("Expected an end time. Got \(outcome).")
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expected = clock.now.addingTimeInterval(300)
        #expect(formatter.string(from: expected) == endsAt)
    }

    @Test func anUnnamedTimerGetsTheDefaultName() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(60)])
        )

        guard case .succeeded(_, let output) = outcome else {
            Issue.record("Expected success. Got \(outcome).")
            return
        }
        #expect(output[TimersCommandOutputName.title] == .string("Timer"))
    }

    @Test func invalidInputCreatesNoTimer() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(0)])
        )

        guard case .failed = outcome else {
            Issue.record("Expected a failure for an out-of-range duration. Got \(outcome).")
            return
        }
        #expect(store.timers.isEmpty)
    }

    @Test func anUngrantedCallerIsDeniedWithoutEffect() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(60)], grants: [])
        )

        guard case .denied(let reason, _) = outcome else {
            Issue.record("Expected a denial for an ungranted caller. Got \(outcome).")
            return
        }
        #expect(reason == .missingCallerGrant)
        #expect(store.timers.isEmpty)
    }

    @Test func theUIActionAndTheCommandShareOneOperation() async {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let operations = TimerOperations(store: store)
        let handler = StartTimerCommandHandler(operations: operations)

        // The Timers UI's own start action goes through TimerOperations…
        let fromUI = operations.start(TimerStartRequest(durationSeconds: 120, title: "UI"))
        // …and so does the shared command.
        let outcome = await handler.execute(
            TimersFixture.invocation([
                "durationSeconds": .integer(120),
                "title": .string("Command")
            ])
        )

        guard case .succeeded = outcome else {
            Issue.record("Expected success. Got \(outcome).")
            return
        }
        #expect(store.timers.count == 2)
        #expect(store.timer(id: fromUI.id)?.phase == .running)
        #expect(store.timers.allSatisfy { $0.totalDuration == 120 })
    }

    @Test func theCountdownContinuesAfterTheLauncherIsDismissed() async {
        let clock = TestClock()
        // A session-scoped view would be torn down here; the store is module-scoped and keeps
        // deriving remaining time from absolute dates.
        let store = TimersFixture.store(clock: clock)
        let handler = StartTimerCommandHandler(operations: TimerOperations(store: store))

        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(100)])
        )
        guard case .succeeded(_, let output) = outcome,
              case .string(let rawID)? = output[TimersCommandOutputName.timerID],
              let id = UUID(uuidString: rawID) else {
            Issue.record("Expected a started timer. Got \(outcome).")
            return
        }

        clock.advance(by: 40)
        store.refresh()

        #expect(store.timer(id: id)?.phase == .running)
        #expect(store.remainingTime(for: id) == 60)

        clock.advance(by: 60)
        store.refresh()
        #expect(store.timer(id: id)?.phase == .completed)
    }

    @Test func presentationCommandsReportInteractionRequired() async {
        let handler = TimersPresentationCommandHandler()
        for commandID in [
            TimersModuleIdentifiers.application,
            TimersModuleIdentifiers.openTool,
            TimersModuleIdentifiers.newTimerTool
        ] {
            let outcome = await handler.execute(
                ModuleCommandInvocation(
                    commandID: commandID,
                    arguments: .empty,
                    context: CommandInvocationContext(source: .search),
                    grants: .directUser
                )
            )
            guard case .interactionRequired = outcome else {
                Issue.record("Expected \(commandID.rawValue) to require interaction. Got \(outcome).")
                continue
            }
            #expect(outcome.didCompleteEffect == false)
        }
    }
}

// MARK: - Host integration

@MainActor
struct TimersModuleHostTests {
    @Test func theModuleRegistersAndValidates() throws {
        let host = ModuleHost()
        try host.register(TimersAssembly())
        #expect(
            host.commandDefinitions().map(\.id.rawValue).sorted()
                == ["timers.focus", "timers.focus.tool.open", "timers.new", "timers.start"]
        )
    }

    @Test func metadataDiscoveryStartsNoTimerService() throws {
        final class Box: @unchecked Sendable {
            // Justification for @unchecked Sendable: this box is only touched from the
            // @MainActor test body and the @MainActor store factory below.
            var madeStore = false
        }
        let box = Box()
        let host = ModuleHost()
        try host.register(
            TimersAssembly(makeStore: {
                box.madeStore = true
                return TimerStore(automaticallySchedulesTicks: false)
            })
        )

        _ = host.commandDefinitions()
        _ = host.settingsContributions()
        _ = host.documentationContributions()
        _ = host.availability(of: TimersModuleIdentifiers.module)

        #expect(box.madeStore == false)
        #expect(host.isActivated(TimersModuleIdentifiers.module) == false)
    }

    @Test func startIsDispatchableThroughTheHostWithoutPresentingAnything() async throws {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let host = ModuleHost()
        try host.register(TimersAssembly(makeStore: { store }))

        let handler = try await host.handler(for: TimersModuleIdentifiers.startTool)
        let outcome = await handler.execute(
            TimersFixture.invocation(["durationSeconds": .integer(45), "title": .string("Break")])
        )

        #expect(outcome.didCompleteEffect)
        #expect(store.timers.count == 1)
        #expect(store.timers.first?.name == "Break")
    }

    @Test func deactivationStopsTheRefreshSourceWithoutDeletingTimers() async throws {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock, automaticallySchedulesTicks: true)
        let host = ModuleHost()
        try host.register(TimersAssembly(makeStore: { store }))

        let handler = try await host.handler(for: TimersModuleIdentifiers.startTool)
        _ = await handler.execute(TimersFixture.invocation(["durationSeconds": .integer(600)]))
        #expect(store.timers.count == 1)

        #expect(await host.deactivate(TimersModuleIdentifiers.module))

        // Disabling a module is not permission to delete its data.
        #expect(store.timers.count == 1)
        #expect(host.isActivated(TimersModuleIdentifiers.module) == false)
    }

    @Test func documentationReferencesResolveAgainstDeclaredThings() throws {
        // Registration validates every documentation reference, so a successful register()
        // proves there are no dangling command or setting references.
        let host = ModuleHost()
        #expect(throws: Never.self) { try host.register(TimersAssembly()) }
        #expect(host.documentationContributions().first?.documentation.articles.count == 1)
    }
}

// MARK: - AI bridge integration

@MainActor
struct TimersAICommandBridgeTests {
    final class FakeDispatcher: ModuleCommandDispatching {
        private let host: ModuleHost
        init(host: ModuleHost) { self.host = host }

        func dispatch(
            reference: CommandReference,
            grants: ModuleCallerGrants,
            context: CommandInvocationContext
        ) async -> ModuleCommandOutcome {
            guard let handler = try? await host.handler(for: reference.commandID) else {
                return .unavailable(reason: .unsupported, message: "No handler.")
            }
            return await handler.execute(
                ModuleCommandInvocation(
                    commandID: reference.commandID,
                    arguments: reference.arguments,
                    context: context,
                    grants: grants
                )
            )
        }
    }

    private func makeBridge(store: TimerStore) throws -> AICommandBridge {
        let host = ModuleHost()
        try host.register(TimersAssembly(makeStore: { store }))
        return AICommandBridge(
            definitions: { host.commandDefinitions() },
            dispatcher: FakeDispatcher(host: host)
        )
    }

    @Test func onlyTheReviewedStartCommandIsOffered() throws {
        let clock = TestClock()
        let bridge = try makeBridge(store: TimersFixture.store(clock: clock))
        #expect(try bridge.availableTools().map(\.name) == ["timers_start"])
    }

    @Test func aModelCanStartATimerThroughTheSharedPath() async throws {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let bridge = try makeBridge(store: store)

        let result = await bridge.invoke(
            AIToolCall(
                id: "call-1",
                name: "timers_start",
                arguments: .object([
                    "durationSeconds": .number(1500),
                    "title": .string("Pomodoro")
                ])
            ),
            context: CommandInvocationContext(source: .search),
            grants: [.automation]
        )

        #expect(result.isError == false)
        #expect(store.timers.count == 1)
        #expect(store.timers.first?.name == "Pomodoro")
        #expect(store.timers.first?.phase == .running)
    }

    @Test func aModelCannotOpenTheNewTimerDraft() async throws {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let bridge = try makeBridge(store: store)

        let result = await bridge.invoke(
            AIToolCall(id: "call-1", name: "timers_new", arguments: .object([:])),
            context: CommandInvocationContext(source: .search)
        )

        #expect(result.isError)
        #expect(store.timers.isEmpty)
    }

    @Test func invalidDurationFromAModelCreatesNoTimer() async throws {
        let clock = TestClock()
        let store = TimersFixture.store(clock: clock)
        let bridge = try makeBridge(store: store)

        let result = await bridge.invoke(
            AIToolCall(
                id: "call-1",
                name: "timers_start",
                arguments: .object(["durationSeconds": .number(999_999)])
            ),
            context: CommandInvocationContext(source: .search)
        )

        #expect(result.isError)
        #expect(store.timers.isEmpty)
    }

    @Test func schemaMatchesWhatTheRuntimeAccepts() throws {
        let clock = TestClock()
        let bridge = try makeBridge(store: TimersFixture.store(clock: clock))
        let tool = try #require(try bridge.availableTools().first)

        guard case .object(let properties, let required, let additional, _) = tool.inputSchema else {
            Issue.record("Expected an object schema.")
            return
        }
        #expect(Set(properties.keys) == ["durationSeconds", "title"])
        #expect(required == ["durationSeconds"])
        #expect(additional == false)
    }
}
