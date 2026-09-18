import Foundation
import Infrastructure
import SecurityKit

/// Focused dependencies shared by Schedule sessions and their explicitly armed occurrence.
@MainActor
struct ScheduleApplicationServices {
    let reader: any ScheduleReading
    let permissions: any PermissionServicing
    let privacySettings: any PrivacySettingsOpening
    let autoJoin: ScheduleAutoJoinCoordinator
    let now: @MainActor () -> Date
    let calendar: Calendar
    let makeChangeMonitor: @MainActor () -> any ScheduleChangeObserving

    init(
        reader: any ScheduleReading,
        permissions: any PermissionServicing,
        privacySettings: any PrivacySettingsOpening,
        autoJoin: ScheduleAutoJoinCoordinator,
        now: @escaping @MainActor () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        makeChangeMonitor: @escaping @MainActor () -> any ScheduleChangeObserving = {
            NativeScheduleChangeMonitor()
        }
    ) {
        self.reader = reader
        self.permissions = permissions
        self.privacySettings = privacySettings
        self.autoJoin = autoJoin
        self.now = now
        self.calendar = calendar
        self.makeChangeMonitor = makeChangeMonitor
    }

    static var inMemory: Self {
        let reader = InMemoryScheduleReader()
        return Self(
            reader: reader,
            permissions: InMemoryPermissionService(),
            privacySettings: InMemoryPrivacySettingsOpener(),
            autoJoin: ScheduleAutoJoinCoordinator(
                reader: reader, opener: NoOpURLOpener(),
                scheduler: InMemoryScheduleDeadlineScheduler(), monitor: InMemoryScheduleChangeMonitor()
            ),
            makeChangeMonitor: { InMemoryScheduleChangeMonitor() }
        )
    }
}

@MainActor
final class InMemoryScheduleChangeMonitor: ScheduleChangeObserving {
    private var action: (@MainActor @Sendable () -> Void)?
    func start(onChange: @escaping @MainActor @Sendable () -> Void) { action = onChange }
    func stop() { action = nil }
    func notifyChange() { action?() }
}

@MainActor
final class InMemoryScheduleDeadlineScheduler: ScheduleDeadlineScheduling {
    private(set) var scheduledDate: Date?
    private var action: (@MainActor @Sendable () -> Void)?
    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void) {
        scheduledDate = date
        self.action = action
    }
    func cancel() { scheduledDate = nil; action = nil }
    func fire() {
        let pending = action
        cancel()
        pending?()
    }
}
