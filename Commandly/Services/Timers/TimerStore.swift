import AppKit
import Foundation
import Observation

/// Lifecycle of a Commandly countdown.
enum CountdownTimerPhase: String, Sendable, Equatable, CaseIterable {
    case ready
    case running
    case paused
    case completed
}

/// One named countdown managed by ``TimerStore``.
struct CountdownTimer: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let totalDuration: TimeInterval
    private(set) var name: String
    private(set) var phase: CountdownTimerPhase
    private(set) var completedAt: Date?

    private var remainingWhenStopped: TimeInterval
    private var runningSince: Date?

    init(
        id: UUID,
        name: String,
        duration: TimeInterval,
        createdAt: Date,
        startsImmediately: Bool
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.totalDuration = duration
        self.remainingWhenStopped = duration
        self.runningSince = startsImmediately ? createdAt : nil
        self.phase = startsImmediately ? .running : .ready
        self.completedAt = nil
    }

    /// Remaining duration derived from an absolute start time, avoiding per-tick drift.
    func remaining(at date: Date) -> TimeInterval {
        guard phase == .running, let runningSince else {
            return max(0, remainingWhenStopped)
        }
        let elapsed = max(0, date.timeIntervalSince(runningSince))
        return max(0, remainingWhenStopped - elapsed)
    }

    func elapsedProgress(at date: Date) -> Double {
        guard totalDuration > 0 else { return 1 }
        let elapsed = totalDuration - remaining(at: date)
        return min(1, max(0, elapsed / totalDuration))
    }

    mutating func pause(at date: Date) {
        guard phase == .running else { return }
        remainingWhenStopped = remaining(at: date)
        runningSince = nil
        phase = remainingWhenStopped > 0 ? .paused : .completed
        if phase == .completed {
            completedAt = date
        }
    }

    mutating func start(at date: Date) {
        guard phase == .ready || phase == .paused, remainingWhenStopped > 0 else { return }
        runningSince = date
        phase = .running
        completedAt = nil
    }

    mutating func reset() {
        remainingWhenStopped = totalDuration
        runningSince = nil
        phase = .ready
        completedAt = nil
    }

    mutating func complete(at observedDate: Date) {
        guard phase == .running else { return }
        let deadline = runningSince?.addingTimeInterval(remainingWhenStopped) ?? observedDate
        remainingWhenStopped = 0
        runningSince = nil
        phase = .completed
        completedAt = deadline
    }
}

/// Shared in-process countdown owner.
///
/// `AppRuntime` should retain one store and inject it into every timer application session. The
/// store owns its lightweight refresh timer, so closing the launcher surface does not pause active
/// countdowns. Refreshes only trigger recomputation from absolute dates; they never decrement the
/// remaining value and therefore cannot accumulate timer drift.
@Observable
@MainActor
final class TimerStore {
    typealias NowProvider = @MainActor () -> Date
    typealias CompletionHandler = @MainActor (CountdownTimer) -> Void

    private(set) var timers: [CountdownTimer] = []
    private(set) var displayDate: Date
    private(set) var isCompletionSoundEnabled: Bool

    @ObservationIgnored private let nowProvider: NowProvider
    @ObservationIgnored private let uuidProvider: @MainActor () -> UUID
    @ObservationIgnored private let completionHandler: CompletionHandler
    @ObservationIgnored private let automaticallySchedulesTicks: Bool
    @ObservationIgnored private var tickTimer: Foundation.Timer?

    init(
        now: @escaping NowProvider = Date.init,
        uuid: @escaping @MainActor () -> UUID = UUID.init,
        automaticallySchedulesTicks: Bool = true,
        isCompletionSoundEnabled: Bool = true,
        onCompletion: CompletionHandler? = nil
    ) {
        let initialDate = now()
        self.nowProvider = now
        self.uuidProvider = uuid
        self.automaticallySchedulesTicks = automaticallySchedulesTicks
        self.isCompletionSoundEnabled = isCompletionSoundEnabled
        self.displayDate = initialDate
        self.completionHandler = onCompletion ?? { _ in
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    var hasRunningTimers: Bool {
        timers.contains { $0.phase == .running }
    }

    @discardableResult
    func createTimer(
        name: String,
        duration: TimeInterval,
        startsImmediately: Bool = true
    ) -> UUID {
        let currentDate = nowProvider()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let timer = CountdownTimer(
            id: uuidProvider(),
            name: normalizedName.isEmpty ? "Timer" : normalizedName,
            duration: max(1, duration),
            createdAt: currentDate,
            startsImmediately: startsImmediately
        )
        displayDate = currentDate
        timers.insert(timer, at: 0)
        updateAutomaticTicking()
        return timer.id
    }

    func timer(id: UUID) -> CountdownTimer? {
        timers.first { $0.id == id }
    }

    func remainingTime(for timer: CountdownTimer) -> TimeInterval {
        timer.remaining(at: displayDate)
    }

    func remainingTime(for id: UUID) -> TimeInterval? {
        timer(id: id)?.remaining(at: displayDate)
    }

    func elapsedProgress(for timer: CountdownTimer) -> Double {
        timer.elapsedProgress(at: displayDate)
    }

    /// Recomputes all running timers from the injected date source.
    func refresh() {
        let currentDate = nowProvider()
        displayDate = currentDate

        var completions: [CountdownTimer] = []
        for index in timers.indices {
            var timer = timers[index]
            guard timer.phase == .running, timer.remaining(at: currentDate) <= 0 else {
                continue
            }
            timer.complete(at: currentDate)
            timers[index] = timer
            completions.append(timer)
        }

        updateAutomaticTicking()
        if isCompletionSoundEnabled {
            completions.forEach(completionHandler)
        }
    }

    @discardableResult
    func pause(id: UUID) -> Bool {
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].phase == .running else {
            return false
        }
        var timer = timers[index]
        timer.pause(at: displayDate)
        timers[index] = timer
        updateAutomaticTicking()
        return true
    }

    @discardableResult
    func start(id: UUID) -> Bool {
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].phase == .ready || timers[index].phase == .paused else {
            return false
        }
        var timer = timers[index]
        timer.start(at: displayDate)
        timers[index] = timer
        updateAutomaticTicking()
        return true
    }

    @discardableResult
    func reset(id: UUID) -> Bool {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return false }
        displayDate = nowProvider()
        var timer = timers[index]
        timer.reset()
        timers[index] = timer
        updateAutomaticTicking()
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return false }
        timers.remove(at: index)
        updateAutomaticTicking()
        return true
    }

    func setCompletionSoundEnabled(_ isEnabled: Bool) {
        isCompletionSoundEnabled = isEnabled
    }

    /// Stops only the store's refresh source. Countdown state remains available to its owner.
    func stopAutomaticUpdates() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func updateAutomaticTicking() {
        guard automaticallySchedulesTicks else { return }
        guard hasRunningTimers else {
            stopAutomaticUpdates()
            return
        }
        guard tickTimer == nil else { return }

        let timer = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.refresh()
            }
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
