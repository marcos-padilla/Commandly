import CommandKit
import Testing
@testable import Commandly

@Suite("Global shortcut lifecycle")
struct GlobalShortcutMonitorTests {
    @Test @MainActor
    func planRejectsDuplicateIDsHotKeysAndUnknownKeyCodes() {
        let launcher = GlobalShortcutID(rawValue: "launcher")
        let wheel = GlobalShortcutID(rawValue: "wheel")
        let duplicateID = GlobalShortcutID(rawValue: "launcher")
        let unknown = GlobalShortcutID(rawValue: "unknown")
        let hotKey = LauncherHotKey(keyCode: 49, modifiers: [.control, .option])

        let plan = GlobalShortcutPlan.resolve([
            GlobalShortcutRegistration(id: launcher, hotKey: hotKey),
            GlobalShortcutRegistration(id: wheel, hotKey: hotKey),
            GlobalShortcutRegistration(
                id: duplicateID,
                hotKey: LauncherHotKey(keyCode: 0, modifiers: [.command])
            ),
            GlobalShortcutRegistration(
                id: unknown,
                hotKey: LauncherHotKey(keyCode: 9_999, modifiers: [.command])
            ),
        ])

        #expect(plan.registrations.map(\.id) == [launcher])
        #expect(plan.issues[wheel] == .duplicate(owner: launcher))
        #expect(plan.issues[duplicateID] == .duplicateID)
        #expect(plan.issues[unknown] == .unavailable)
    }

    @Test @MainActor
    func dispatchIgnoresRepeatPressAndDuplicateRelease() {
        let id = GlobalShortcutID(rawValue: "wheel.default")
        let monitor = GlobalShortcutMonitor()
        var events: [GlobalShortcutEvent] = []
        _ = monitor.installForTesting(
            [
                GlobalShortcutRegistration(
                    id: id,
                    hotKey: LauncherHotKey(keyCode: 49, modifiers: [.control, .option])
                )
            ],
            onEvent: { events.append($0) }
        )

        monitor.dispatchForTesting(numericID: 1, phase: .pressed)
        monitor.dispatchForTesting(numericID: 1, phase: .pressed)
        monitor.dispatchForTesting(numericID: 1, phase: .released)
        monitor.dispatchForTesting(numericID: 1, phase: .released)

        #expect(events.map(\.phase) == [.pressed, .released])
        #expect(Set(events.map(\.generation)).count == 1)
    }

    @Test @MainActor
    func replacingRegistrationsCancelsHeldShortcutBeforeNewGeneration() {
        let oldID = GlobalShortcutID(rawValue: "wheel.old")
        let newID = GlobalShortcutID(rawValue: "wheel.new")
        let monitor = GlobalShortcutMonitor()
        var oldEvents: [GlobalShortcutEvent] = []
        var newEvents: [GlobalShortcutEvent] = []
        let hotKey = LauncherHotKey(keyCode: 49, modifiers: [.control, .option])

        _ = monitor.installForTesting(
            [GlobalShortcutRegistration(id: oldID, hotKey: hotKey)],
            onEvent: { oldEvents.append($0) }
        )
        let oldGeneration = monitor.generation
        monitor.dispatchForTesting(numericID: 1, phase: .pressed)

        _ = monitor.installForTesting(
            [GlobalShortcutRegistration(id: newID, hotKey: hotKey)],
            onEvent: { newEvents.append($0) }
        )
        monitor.dispatchForTesting(numericID: 1, phase: .released)
        monitor.dispatchForTesting(numericID: 1, phase: .pressed)
        monitor.dispatchForTesting(numericID: 1, phase: .released)

        #expect(oldEvents.map(\.phase) == [.pressed, .cancelled])
        #expect(oldEvents.allSatisfy { $0.generation == oldGeneration })
        #expect(newEvents.map(\.phase) == [.pressed, .released])
        #expect(newEvents.allSatisfy { $0.generation == oldGeneration &+ 1 })
    }

    @Test @MainActor
    func queuedOldCallbackCannotTargetReplacementReusingNumericID() throws {
        let oldID = GlobalShortcutID(rawValue: "wheel.old")
        let newID = GlobalShortcutID(rawValue: "wheel.new")
        let monitor = GlobalShortcutMonitor()
        var oldEvents: [GlobalShortcutEvent] = []
        var newEvents: [GlobalShortcutEvent] = []
        let hotKey = LauncherHotKey(keyCode: 49, modifiers: [.control, .option])

        _ = monitor.installForTesting(
            [GlobalShortcutRegistration(id: oldID, hotKey: hotKey)],
            onEvent: { oldEvents.append($0) }
        )
        let queuedOldPress = try #require(
            monitor.captureCallbackForTesting(numericID: 1)
        )

        _ = monitor.installForTesting(
            [GlobalShortcutRegistration(id: newID, hotKey: hotKey)],
            onEvent: { newEvents.append($0) }
        )
        monitor.dispatchForTesting(identity: queuedOldPress, phase: .pressed)

        #expect(oldEvents.isEmpty)
        #expect(newEvents.isEmpty)

        monitor.dispatchForTesting(numericID: 1, phase: .pressed)
        monitor.dispatchForTesting(numericID: 1, phase: .released)
        #expect(newEvents.map(\.id) == [newID, newID])
        #expect(newEvents.map(\.phase) == [.pressed, .released])
    }

    @Test @MainActor
    func stopIsIdempotentAndCancelsAtMostOnce() {
        let id = GlobalShortcutID(rawValue: "wheel.default")
        let monitor = GlobalShortcutMonitor()
        var phases: [GlobalShortcutPhase] = []
        _ = monitor.installForTesting(
            [
                GlobalShortcutRegistration(
                    id: id,
                    hotKey: LauncherHotKey(keyCode: 49, modifiers: [.control, .option])
                )
            ],
            onEvent: { phases.append($0.phase) }
        )

        monitor.dispatchForTesting(numericID: 1, phase: .pressed)
        monitor.stop()
        monitor.stop()

        #expect(phases == [.pressed, .cancelled])
    }

    @Test @MainActor
    func runtimeCatalogKeepsExistingShortcutsAheadOfWheelProfiles() throws {
        var configuration = CommandWheelDefaults.configuration
        configuration.isEnabled = true
        configuration.contextAwareProfileSelectionEnabled = true
        configuration.profiles[0].shortcut = LauncherHotKey(
            keyCode: 11,
            modifiers: [.control, .option]
        )
        let applicationID = CommandID(rawValue: "test.application")
        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: [
                (
                    applicationID,
                    LauncherHotKey(keyCode: 2, modifiers: [.command, .option])
                )
            ],
            wheelConfiguration: configuration
        )

        #expect(bindings.first?.route == .launcher)
        #expect(
            bindings.dropFirst().prefix(ShelfGlobalShortcut.allCases.count).map(\.route)
                == ShelfGlobalShortcut.allCases.map(RuntimeGlobalShortcutRoute.shelf)
        )
        #expect(bindings[1 + ShelfGlobalShortcut.allCases.count].route == .application(applicationID))
        #expect(
            bindings.last?.route == .commandWheel(
                profileID: configuration.defaultProfileID,
                allowsContextOverride: true
            )
        )
    }

    @Test @MainActor
    func disabledWheelDoesNotRegisterProfileShortcut() {
        var configuration = CommandWheelDefaults.configuration
        configuration.profiles[0].shortcut = LauncherHotKey(
            keyCode: 11,
            modifiers: [.control, .option]
        )

        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: [],
            wheelConfiguration: configuration
        )

        #expect(bindings.contains { binding in
            if case .commandWheel = binding.route { return true }
            return false
        } == false)
    }

    @Test @MainActor
    func wheelShortcutCannotStealLauncherShortcut() throws {
        var configuration = CommandWheelDefaults.configuration
        configuration.isEnabled = true
        configuration.profiles[0].shortcut = LauncherHotKey(
            keyCode: 49,
            modifiers: .option
        )
        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: [],
            wheelConfiguration: configuration
        )
        let plan = GlobalShortcutPlan.resolve(bindings.map(\.registration))
        let wheel = try #require(bindings.last)

        #expect(plan.issues[wheel.registration.id] == .duplicate(
            owner: RuntimeGlobalShortcutCatalog.launcherID
        ))
    }
}
