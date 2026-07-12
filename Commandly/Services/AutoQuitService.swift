import Foundation
import Infrastructure

/// Periodically terminates apps marked for auto-quit when they are idle (not frontmost).
@MainActor
final class AutoQuitService {
    /// Idle duration before a listed background app is terminated.
    static let idleThreshold: TimeInterval = 5 * 60
    /// How often to evaluate running apps.
    static let pollInterval: Duration = .seconds(30)

    private let preferencesStore: any ApplicationPreferencesStoring
    private let runningApps: any RunningApplicationControlling
    private let now: () -> Date

    /// Last time each bundle ID was observed as frontmost.
    private var lastActiveAt: [String: Date] = [:]
    private var pollTask: Task<Void, Never>?

    init(
        preferencesStore: any ApplicationPreferencesStoring,
        runningApps: any RunningApplicationControlling = WorkspaceRunningApplicationController(),
        now: @escaping () -> Date = Date.init
    ) {
        self.preferencesStore = preferencesStore
        self.runningApps = runningApps
        self.now = now
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while let self, Task.isCancelled == false {
                await self.evaluate()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Runs one evaluation pass (also used by tests).
    func evaluate() async {
        let prefs = preferencesStore.load()
        let autoQuitIDs = prefs.autoQuitBundleIDs
        guard autoQuitIDs.isEmpty == false else { return }

        let instant = now()
        if let frontmost = await runningApps.frontmostBundleIdentifier() {
            lastActiveAt[frontmost] = instant
        }

        let running = await runningApps.runningApplications()
        for app in running where autoQuitIDs.contains(app.bundleIdentifier) {
            if app.isActive {
                lastActiveAt[app.bundleIdentifier] = instant
                continue
            }
            guard let lastActive = lastActiveAt[app.bundleIdentifier] else {
                // First sighting while backgrounded: start the idle clock.
                lastActiveAt[app.bundleIdentifier] = instant
                continue
            }
            if instant.timeIntervalSince(lastActive) >= Self.idleThreshold {
                _ = await runningApps.terminate(bundleIdentifier: app.bundleIdentifier)
                lastActiveAt.removeValue(forKey: app.bundleIdentifier)
            }
        }
    }

    /// Test helper: seed last-active timestamps.
    func setLastActiveAtForTesting(_ bundleIdentifier: String, date: Date) {
        lastActiveAt[bundleIdentifier] = date
    }
}
