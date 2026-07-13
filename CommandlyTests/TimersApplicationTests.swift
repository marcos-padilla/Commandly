import Foundation
import Testing
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
}
