import AppKit
import EventKit
import Foundation

/// Injectable one-shot deadline source. Fake schedulers can advance without wall-clock delays.
@MainActor
protocol ScheduleDeadlineScheduling: AnyObject {
    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

@MainActor
final class NativeScheduleDeadlineScheduler: ScheduleDeadlineScheduling {
    private var timer: Timer?

    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() { timer?.invalidate(); timer = nil }
}

/// Notification seam; notifications carry no event metadata across isolation boundaries.
@MainActor
protocol ScheduleChangeObserving: AnyObject {
    func start(onChange: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
final class NativeScheduleChangeMonitor: ScheduleChangeObserving {
    private var eventObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        eventObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stop() {
        if let eventObserver { NotificationCenter.default.removeObserver(eventObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        eventObserver = nil
        wakeObserver = nil
    }

    isolated deinit {
        if let eventObserver { NotificationCenter.default.removeObserver(eventObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
