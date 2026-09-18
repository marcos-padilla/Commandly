import AppKit
import Foundation

@MainActor
protocol DisplayResolutionTickScheduling: AnyObject {
    func start(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// The interval refreshes the visible countdown; the coordinator uses a continuous monotonic deadline.
@MainActor
final class NativeDisplayResolutionTicker: DisplayResolutionTickScheduling {
    private var timer: Timer?
    func start(_ action: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in MainActor.assumeIsolated { action() } }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
    }
    func cancel() { timer?.invalidate(); timer = nil }
}

@MainActor
protocol DisplayResolutionEnvironmentObserving: AnyObject {
    func start(_ action: @escaping @MainActor () -> Void)
    func stop()
}

/// Only active while the chooser or an unresolved preview exists. Callbacks never directly mutate CG.
@MainActor
final class NativeDisplayResolutionEnvironmentMonitor: DisplayResolutionEnvironmentObserving {
    private var screenObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    func start(_ action: @escaping @MainActor () -> Void) {
        stop()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in MainActor.assumeIsolated { action() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { _ in MainActor.assumeIsolated { action() } }
    }
    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
    }
}

@MainActor
protocol DisplayResolutionWindowPresenting: AnyObject {
    func present(_ model: DisplayResolutionCoordinator)
    func ensureVisible()
    func close()
}
