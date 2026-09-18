import CommandKit
import Foundation
import Testing
import TimersModule
@testable import Commandly

struct TimersApplicationTests {
    @Test @MainActor func countdownUsesAbsoluteDatesAndCompletesAtItsDeadline() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        var now = start
        let store = TimerStore(
            now: { now },
            uuid: { id },
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )

        let createdID = store.createTimer(name: "Tea", duration: 120)
        #expect(createdID == id)
        #expect(try #require(store.remainingTime(for: id)) == 120)

        now = start.addingTimeInterval(37.5)
        store.refresh()
        #expect(try #require(store.remainingTime(for: id)) == 82.5)

        now = start.addingTimeInterval(200)
        store.refresh()
        let completed = try #require(store.timer(id: id))
        #expect(completed.phase == .completed)
        #expect(completed.completedAt == start.addingTimeInterval(120))
        #expect(store.remainingTime(for: id) == 0)

        store.refresh()
        #expect(store.timer(id: id)?.completedAt == start.addingTimeInterval(120))
    }

    @Test @MainActor func pauseResumeResetAndDeleteDoNotAccumulateTickDrift() throws {
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        let id = UUID()
        var now = start
        let store = TimerStore(
            now: { now },
            uuid: { id },
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )
        store.createTimer(name: "Stretch", duration: 100)

        now = start.addingTimeInterval(30)
        #expect(store.pause(id: id))
        #expect(store.timer(id: id)?.phase == .paused)
        #expect(store.remainingTime(for: id) == 70)

        now = start.addingTimeInterval(530)
        store.refresh()
        #expect(store.remainingTime(for: id) == 70)

        #expect(store.start(id: id))
        now = start.addingTimeInterval(540)
        store.refresh()
        #expect(store.remainingTime(for: id) == 60)

        #expect(store.reset(id: id))
        #expect(store.timer(id: id)?.phase == .ready)
        #expect(store.remainingTime(for: id) == 100)
        #expect(store.delete(id: id))
        #expect(store.timers.isEmpty)
    }

    @Test @MainActor func modelRunsMultipleNamedFocusAndBreakCountdowns() throws {
        let start = Date(timeIntervalSince1970: 1_800_200_000)
        var now = start
        var ids = [UUID(), UUID()]
        let store = TimerStore(
            now: { now },
            uuid: { ids.removeFirst() },
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )
        let model = TimersViewModel(store: store, onGoBack: {})

        #expect(model.isCreating)
        #expect(model.draftName == "Focus")
        #expect(model.draftMinutes == 25)
        model.startDraftTimer()

        #expect(store.timers.count == 1)
        #expect(store.timers.first?.name == "Focus")
        #expect(store.timers.first?.totalDuration == 1_500)

        model.perform(TimersActionID.startBreak)
        #expect(store.timers.count == 2)
        #expect(store.timers.first?.name == "Short Break")
        #expect(store.timers.first?.totalDuration == 300)

        now = start.addingTimeInterval(10)
        model.pauseSelected()
        #expect(model.selectedTimer?.phase == .paused)
        #expect(model.remainingText(for: try #require(model.selectedTimer)) == "04:50")

        model.startSelected()
        #expect(model.selectedTimer?.phase == .running)
        model.deleteSelected()
        #expect(store.timers.count == 1)
        #expect(store.timers.first?.name == "Focus")
    }

    @Test @MainActor func applicationSessionLeavesSharedStoreRunningAfterSessionStops() throws {
        let start = Date(timeIntervalSince1970: 1_800_300_000)
        var now = start
        let store = TimerStore(
            now: { now },
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )
        let application = TimersApplication(store: store)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: ["completionSound": .boolean(false)]
            )
        )

        let launch = application.launch(in: context)
        guard case .present(let session) = launch else {
            Issue.record("Expected TimersApplication to present a session")
            return
        }
        let model = try #require(session.model(as: TimersViewModel.self))
        #expect(store.isCompletionSoundEnabled == false)

        model.perform(TimersActionID.startFocus)
        let timerID = try #require(store.timers.first?.id)
        session.stop()

        now = start.addingTimeInterval(60)
        store.refresh()
        #expect(store.timer(id: timerID)?.phase == .running)
        #expect(store.remainingTime(for: timerID) == 1_440)
        #expect(application.definition.id == TimersApplication.applicationID)
    }

    @Test @MainActor
    func timerToolsAreRegisteredAndNewTimerOpensTheExistingDraftEditor() throws {
        let store = TimerStore(
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )
        store.createTimer(name: "Existing", duration: 300)
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let tools = registry.children(of: TimersApplication.applicationID)

        #expect(tools.map(\.id) == [
            TimersApplication.openToolID,
            TimersApplication.newTimerToolID,
            TimersApplication.startToolID
        ])
        #expect(tools.allSatisfy { $0.kind == .tool })
        #expect(tools.allSatisfy { $0.parentID == TimersApplication.applicationID })
        #expect(
            registry.owningApplicationID(for: TimersApplication.newTimerToolID)
                == TimersApplication.applicationID
        )
        #expect(registry.allManifests().contains { manifest in
            manifest.id == TimersApplication.newTimerToolID
                && manifest.keywords.contains("new timer")
        })
        #expect(registry.resolvedSettings(for: TimersApplication.newTimerToolID) != nil)

        let application = try #require(
            registry.application(for: TimersApplication.applicationID)
        )
        let settings = try #require(
            registry.resolvedSettings(for: TimersApplication.applicationID)
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: settings
        )

        guard case .present(let openSession) = application.launch(
            toolID: TimersApplication.openToolID,
            arguments: CommandArguments(),
            in: context
        ) else {
            Issue.record("Expected Open Timers to present a session")
            return
        }
        #expect(openSession.model(as: TimersViewModel.self)?.isCreating == false)

        guard case .present(let newTimerSession) = application.launch(
            toolID: TimersApplication.newTimerToolID,
            arguments: CommandArguments(),
            in: context
        ) else {
            Issue.record("Expected New Timer to present a Timers session")
            return
        }
        let model = try #require(newTimerSession.model(as: TimersViewModel.self))
        #expect(model.isCreating)
        #expect(model.draftName == TimerPreset.focus.title)
        #expect(model.draftMinutes == TimerPreset.focus.minutes)
        #expect(store.timers.map(\.name) == ["Existing"])
    }

    // MARK: - timers.start as a shared direct operation

    @MainActor
    private func makeStartContext(
        registry: LauncherApplicationRegistry
    ) throws -> LauncherApplicationResolvedSettings {
        try #require(registry.resolvedSettings(for: TimersApplication.applicationID))
    }

    @Test @MainActor
    func startToolRunsWithoutPresentingASessionAndKeepsTheTimerRunning() async throws {
        let start = Date(timeIntervalSince1970: 1_800_400_000)
        var now = start
        let store = TimerStore(
            now: { now },
            automaticallySchedulesTicks: false,
            onCompletion: { _ in }
        )
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let application = try #require(
            registry.application(for: TimersApplication.applicationID)
                as? LauncherApplicationToolBackgroundInvoking
        )

        // The shared executor dispatches start through the background-tool path, not a session.
        #expect(application.backgroundToolIDs.contains(TimersApplication.startToolID))
        #expect(registry.isBackgroundInvokingCommand(TimersApplication.startToolID))

        let result = await application.invokeToolInBackground(
            toolID: TimersApplication.startToolID,
            arguments: CommandArguments([
                "durationSeconds": .integer(1_500),
                "title": .string("Deep Work")
            ]),
            settings: try makeStartContext(registry: registry)
        )

        guard case .success = result else {
            Issue.record("Expected timers.start to succeed. Got \(result).")
            return
        }
        #expect(store.timers.count == 1)
        #expect(store.timers.first?.name == "Deep Work")
        #expect(store.timers.first?.phase == .running)

        // No launcher session exists; the countdown still advances.
        now = start.addingTimeInterval(500)
        store.refresh()
        let id = try #require(store.timers.first?.id)
        #expect(store.remainingTime(for: id) == 1_000)
        #expect(store.timer(id: id)?.phase == .running)
    }

    @Test @MainActor func startToolRejectsInvalidDurationsWithoutCreatingATimer() async throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let application = try #require(
            registry.application(for: TimersApplication.applicationID)
                as? LauncherApplicationToolBackgroundInvoking
        )
        let settings = try makeStartContext(registry: registry)

        for invalid in [0, -5, 86_401] {
            let result = await application.invokeToolInBackground(
                toolID: TimersApplication.startToolID,
                arguments: CommandArguments(["durationSeconds": .integer(invalid)]),
                settings: settings
            )
            guard case .failure = result else {
                Issue.record("Expected \(invalid) seconds to be rejected. Got \(result).")
                continue
            }
        }
        let missing = await application.invokeToolInBackground(
            toolID: TimersApplication.startToolID,
            arguments: CommandArguments(),
            settings: settings
        )
        guard case .failure = missing else {
            Issue.record("Expected a missing duration to be rejected. Got \(missing).")
            return
        }
        #expect(store.timers.isEmpty)
    }

    @Test @MainActor func startToolIsNeverPresentedAsASession() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let application = TimersApplication(store: store)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {}, openSettings: {}, goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "", hotKey: nil, isEnabled: true, configuration: [:]
            )
        )

        // Falling back to opening the surface would report success while no timer had started.
        let launch = application.launch(
            toolID: TimersApplication.startToolID,
            arguments: CommandArguments(["durationSeconds": .integer(60)]),
            in: context
        )
        guard case .message = launch else {
            Issue.record("Expected timers.start not to present a session. Got \(launch).")
            return
        }
        #expect(store.timers.isEmpty)
    }

    @Test @MainActor func newTimerStillOnlyOpensADraft() throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let application = TimersApplication(store: store)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {}, openSettings: {}, goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "", hotKey: nil, isEnabled: true, configuration: [:]
            )
        )

        guard case .present(let session) = application.launch(
            toolID: TimersApplication.newTimerToolID,
            arguments: CommandArguments(),
            in: context
        ) else {
            Issue.record("Expected New Timer to present a session")
            return
        }
        #expect(session.model(as: TimersViewModel.self)?.isCreating == true)
        // The shipped meaning of timers.new is unchanged: it opens a draft, it does not start.
        #expect(store.timers.isEmpty)
    }

    @Test @MainActor func theUIDraftAndTheStartCommandShareOneOperation() async throws {
        let store = TimerStore(automaticallySchedulesTicks: false, onCompletion: { _ in })
        let registry = LauncherApplicationRegistry.makeBuiltIn(timerStore: store)
        let application = try #require(
            registry.application(for: TimersApplication.applicationID)
        )
        let settings = try makeStartContext(registry: registry)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {}, openSettings: {}, goBack: {}
            ),
            settings: settings
        )

        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected a Timers session")
            return
        }
        let model = try #require(session.model(as: TimersViewModel.self))
        model.draftName = "From UI"
        model.draftMinutes = 5
        model.startDraftTimer()

        let backgroundApplication = try #require(
            application as? LauncherApplicationToolBackgroundInvoking
        )
        _ = await backgroundApplication.invokeToolInBackground(
            toolID: TimersApplication.startToolID,
            arguments: CommandArguments([
                "durationSeconds": .integer(300),
                "title": .string("From command")
            ]),
            settings: settings
        )

        // Both paths produced an equivalent running countdown through TimerOperations.
        #expect(store.timers.count == 2)
        #expect(store.timers.allSatisfy { $0.phase == .running })
        #expect(store.timers.allSatisfy { $0.totalDuration == 300 })
        #expect(Set(store.timers.map(\.name)) == ["From UI", "From command"])
    }
}
