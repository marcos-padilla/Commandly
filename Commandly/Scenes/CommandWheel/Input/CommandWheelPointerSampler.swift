import AppKit
import CoreGraphics

/// Reads the global pointer position. The system implementation is sampled only while a wheel is
/// active and does not install a mouse-movement event tap or require Accessibility permission.
@MainActor
protocol CommandWheelPointerLocationProviding: AnyObject {
    var currentPointerLocation: CGPoint { get }
}

@MainActor
final class NSEventCommandWheelPointerLocationProvider: CommandWheelPointerLocationProviding {
    var currentPointerLocation: CGPoint { NSEvent.mouseLocation }
}

nonisolated struct CommandWheelPointerSample: Sendable, Equatable {
    let location: CGPoint
    let isFinal: Bool

    static func == (lhs: CommandWheelPointerSample, rhs: CommandWheelPointerSample) -> Bool {
        lhs.location.x == rhs.location.x
            && lhs.location.y == rhs.location.y
            && lhs.isFinal == rhs.isFinal
    }
}

/// Lifecycle-owned latest-position sampler. A final synchronous sample can be requested on key-up
/// before the repeating timer is invalidated, which preserves fast flick behavior.
@MainActor
final class CommandWheelPointerSampler {
    private let pointerProvider: any CommandWheelPointerLocationProviding
    private let timerScheduler: any CommandWheelTimerScheduling
    private let samplingInterval: TimeInterval

    private var timer: (any CommandWheelScheduledTask)?
    private var handler: ((CommandWheelPointerSample) -> Void)?

    private(set) var isSampling = false

    var currentPointerLocation: CGPoint {
        pointerProvider.currentPointerLocation
    }

    init(
        pointerProvider: any CommandWheelPointerLocationProviding =
            NSEventCommandWheelPointerLocationProvider(),
        timerScheduler: any CommandWheelTimerScheduling =
            FoundationCommandWheelTimerScheduler(),
        samplingInterval: TimeInterval = 1.0 / 120.0
    ) {
        self.pointerProvider = pointerProvider
        self.timerScheduler = timerScheduler
        self.samplingInterval = max(1.0 / 240.0, samplingInterval)
    }

    func start(handler: @escaping (CommandWheelPointerSample) -> Void) {
        stop()
        self.handler = handler
        isSampling = true
        sample(isFinal: false)
        timer = timerScheduler.scheduleRepeating(every: samplingInterval) { [weak self] in
            self?.sample(isFinal: false)
        }
    }

    func sampleFinalAndStop() {
        guard isSampling else { return }
        sample(isFinal: true)
        stop()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        handler = nil
        isSampling = false
    }

    private func sample(isFinal: Bool) {
        guard isSampling, let handler else { return }
        handler(
            CommandWheelPointerSample(
                location: pointerProvider.currentPointerLocation,
                isFinal: isFinal
            )
        )
    }

    isolated deinit {
        timer?.cancel()
    }
}
