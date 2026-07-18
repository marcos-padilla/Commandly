import Foundation

/// Cancelable main-run-loop work used for pointer sampling and submenu dwell.
@MainActor
protocol CommandWheelScheduledTask: AnyObject {
    var isCancelled: Bool { get }
    func cancel()
}

/// Timer boundary kept injectable so interaction tests never wait for wall-clock time.
@MainActor
protocol CommandWheelTimerScheduling: AnyObject {
    func scheduleRepeating(
        every interval: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask

    func scheduleOnce(
        after interval: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask
}

/// Main-run-loop timer implementation. It does not use delays as synchronization; timers are the
/// owned input cadence and user-configured dwell mechanism and are invalidated on every teardown.
@MainActor
final class FoundationCommandWheelTimerScheduler: CommandWheelTimerScheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask {
        FoundationCommandWheelScheduledTask(
            interval: max(1.0 / 240.0, interval),
            repeats: true,
            action: action
        )
    }

    func scheduleOnce(
        after interval: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask {
        FoundationCommandWheelScheduledTask(
            interval: max(0, interval),
            repeats: false,
            action: action
        )
    }
}

@MainActor
private final class FoundationCommandWheelScheduledTask: NSObject, CommandWheelScheduledTask {
    private let repeats: Bool
    private var timer: Timer?
    private var action: (@MainActor () -> Void)?
    private(set) var isCancelled = false

    init(interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
        self.repeats = repeats
        self.action = action
        super.init()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(fire),
            userInfo: nil,
            repeats: repeats
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func fire() {
        guard isCancelled == false else { return }
        action?()
        if repeats == false {
            cancel()
        }
    }

    func cancel() {
        guard isCancelled == false else { return }
        isCancelled = true
        timer?.invalidate()
        timer = nil
        action = nil
    }

    isolated deinit {
        timer?.invalidate()
    }
}
