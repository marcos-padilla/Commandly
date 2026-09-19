import Foundation
import Infrastructure

/// A system event that can trigger an automatic clipboard clear.
public enum ClipboardAutoClearTrigger: String, Sendable, CaseIterable, Codable {
    /// The configured idle period elapsed after the last copy.
    case idleTimeout
    /// The Mac went to sleep.
    case systemSleep
    /// The display went to sleep.
    case displaySleep
    /// The screen locked.
    case screenLock
}

/// Delivers the system events that can trigger an automatic clear.
///
/// Kept behind a protocol so the scheduler is testable without sleeping a real Mac. A live
/// implementation observes the relevant workspace and distributed notifications.
@MainActor
public protocol ClipboardAutoClearEventObserving: AnyObject, Sendable {
    /// Starts delivering events to `handler`. Called at most once per activation.
    func start(handler: @escaping @MainActor (ClipboardAutoClearTrigger) -> Void)
    /// Stops delivering events and releases every observer it registered.
    func stop()
}

/// Observer that never fires, for tests and for a disabled configuration.
@MainActor
public final class InertClipboardAutoClearEventObserver: ClipboardAutoClearEventObserving {
    public init() {}
    public func start(handler: @escaping @MainActor (ClipboardAutoClearTrigger) -> Void) {
        _ = handler
    }
    public func stop() {}
}

/// Which automatic clears are enabled, and after how long.
public struct ClipboardAutoClearConfiguration: Sendable, Equatable {
    /// Seconds of inactivity after a copy before the clipboard is cleared. Zero disables it.
    public let idleTimeoutSeconds: Int
    /// System events that clear the clipboard when they occur.
    public let triggers: Set<ClipboardAutoClearTrigger>

    /// Nothing is cleared automatically.
    public static let disabled = ClipboardAutoClearConfiguration(
        idleTimeoutSeconds: 0,
        triggers: []
    )

    /// Creates a configuration.
    public init(idleTimeoutSeconds: Int, triggers: Set<ClipboardAutoClearTrigger>) {
        self.idleTimeoutSeconds = max(0, idleTimeoutSeconds)
        self.triggers = triggers
    }

    /// Whether any automatic clearing is configured at all.
    public var isActive: Bool {
        (idleTimeoutSeconds > 0 && triggers.contains(.idleTimeout)) || eventTriggers.isEmpty == false
    }

    /// Enabled triggers other than the idle timeout.
    public var eventTriggers: Set<ClipboardAutoClearTrigger> {
        triggers.subtracting([.idleTimeout])
    }
}

/// Clears the system clipboard on a timeout or a system event.
///
/// This clears **only the system pasteboard**. It never touches Clipboard History's saved entries:
/// clearing what is currently on the clipboard and deleting a user's saved items are separate
/// decisions, and only the second one destroys data the user asked Commandly to keep.
///
/// The idle countdown is driven by an injected sleep so tests do not wait on real time.
@MainActor
public final class ClipboardAutoClearScheduler {
    /// Suspends for a duration. Injected so tests can drive the countdown deterministically.
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let pasteboard: any PasteboardClearing
    private let observer: any ClipboardAutoClearEventObserving
    private let sleeper: Sleeper
    private var configuration: ClipboardAutoClearConfiguration
    private var idleTask: Task<Void, Never>?
    private var isObserving = false

    /// Number of clears performed. Exposed for tests and diagnostics; carries no clipboard content.
    public private(set) var clearCount = 0
    /// Why the most recent clear happened, if any.
    public private(set) var lastTrigger: ClipboardAutoClearTrigger?

    /// Creates a scheduler.
    public init(
        pasteboard: any PasteboardClearing,
        observer: any ClipboardAutoClearEventObserving = InertClipboardAutoClearEventObserver(),
        configuration: ClipboardAutoClearConfiguration = .disabled,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.pasteboard = pasteboard
        self.observer = observer
        self.configuration = configuration
        self.sleeper = sleeper
    }

    /// Applies a new configuration, starting or stopping observation to match.
    ///
    /// Re-applying the same configuration does not restart observation, so repeated settings
    /// writes cannot stack duplicate observers.
    public func apply(_ configuration: ClipboardAutoClearConfiguration) {
        let previous = self.configuration
        self.configuration = configuration
        guard previous != configuration else { return }
        cancelIdleCountdown()
        updateObservation()
    }

    /// Starts observing, if the current configuration asks for it.
    public func start() {
        updateObservation()
    }

    /// Stops the countdown and releases every observer this scheduler owns.
    public func stop() {
        cancelIdleCountdown()
        if isObserving {
            observer.stop()
            isObserving = false
        }
    }

    /// Notifies the scheduler that the user copied something, restarting the idle countdown.
    ///
    /// Each copy replaces the previous countdown rather than adding another, so a burst of copies
    /// cannot queue up several pending clears.
    public func noteClipboardChanged() {
        cancelIdleCountdown()
        guard configuration.triggers.contains(.idleTimeout),
              configuration.idleTimeoutSeconds > 0 else {
            return
        }
        let delay = Duration.seconds(configuration.idleTimeoutSeconds)
        idleTask = Task { [weak self, sleeper] in
            do {
                try await sleeper(delay)
            } catch {
                return
            }
            guard let self, Task.isCancelled == false else { return }
            await self.performClear(trigger: .idleTimeout)
        }
    }

    /// Clears the clipboard now, recording `trigger` as the reason.
    public func performClear(trigger: ClipboardAutoClearTrigger) async {
        await pasteboard.clear()
        clearCount += 1
        lastTrigger = trigger
    }

    private func updateObservation() {
        let wantsEvents = configuration.eventTriggers.isEmpty == false
        if wantsEvents, isObserving == false {
            isObserving = true
            observer.start { [weak self] trigger in
                guard let self, self.configuration.triggers.contains(trigger) else { return }
                Task { @MainActor [weak self] in
                    await self?.performClear(trigger: trigger)
                }
            }
        } else if wantsEvents == false, isObserving {
            observer.stop()
            isObserving = false
        }
    }

    private func cancelIdleCountdown() {
        idleTask?.cancel()
        idleTask = nil
    }
}
