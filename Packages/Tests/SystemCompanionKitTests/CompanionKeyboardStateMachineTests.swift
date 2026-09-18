import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

@Suite struct CompanionKeyboardStateMachineTests {
    @Test func capsTapAndChordHaveDifferentOutcomes() {
        var machine = CompanionKeyboardStateMachine(configuration: .init(hyperEnabled: true))
        _ = machine.process(.init(.physicalCapsDown, timestamp: 1), field: .unknown)
        let tap = machine.process(.init(.physicalCapsUp, timestamp: 1.12), field: .unknown)
        #expect(tap.toggleCapsLock && tap.resetModifiers)
        _ = machine.process(.init(.physicalCapsDown, timestamp: 2), field: .editable)
        let chord = machine.process(.init(.down, keyCode: 0, timestamp: 2.05, text: "a"), field: .editable)
        #expect(chord.addHyper && !chord.consume)
        let release = machine.process(.init(.physicalCapsUp, timestamp: 2.1), field: .editable)
        #expect(!release.toggleCapsLock && release.resetModifiers)
        #expect(!machine.process(.init(.down, keyCode: 0, timestamp: 2.2, text: "a"), field: .editable).addHyper)
    }
    @Test func heldCapsAndSecureInputNeverToggleCaps() {
        var machine = CompanionKeyboardStateMachine(configuration: .init(hyperEnabled: true))
        _ = machine.process(.init(.physicalCapsDown, timestamp: 1), field: .unknown)
        #expect(!machine.process(.init(.physicalCapsUp, timestamp: 1.8), field: .unknown).toggleCapsLock)
        _ = machine.process(.init(.physicalCapsDown, timestamp: 2), field: .unknown)
        #expect(machine.process(.init(.down, keyCode: 0, timestamp: 2.1), field: .secure).resetModifiers)
        #expect(!machine.process(.init(.physicalCapsUp, timestamp: 2.2), field: .unknown).toggleCapsLock)
    }
    @Test func singleKeyProtectsTypingAndSuppressesRepeatsAndItsRelease() {
        let id = UUID(); let binding = CompanionKeyBinding(id: id, key: .a)
        var machine = CompanionKeyboardStateMachine(configuration: .init(keys: [binding]))
        #expect(!machine.process(.init(.down, timestamp: 1, text: "a"), field: .editable).consume)
        #expect(!machine.process(.init(.down, timestamp: 2), field: .unknown).consume)
        let active = machine.process(.init(.down, timestamp: 3), field: .nonEditable)
        #expect(active.consume && active.activation == id)
        let repeated = machine.process(.init(.down, timestamp: 3.1, isRepeat: true), field: .nonEditable)
        #expect(repeated.consume && repeated.activation == nil)
        #expect(machine.process(.init(.up, timestamp: 3.2), field: .nonEditable).consume)
    }
    @Test func doubleTapRequiresTwoCleanShortTaps() {
        let id = UUID()
        var machine = CompanionKeyboardStateMachine(configuration: .init(doubleTaps: [.init(id: id, key: .rightShift)]))
        _ = machine.process(.init(.modifierDown, keyCode: 60, timestamp: 1), field: .unknown)
        #expect(machine.process(.init(.modifierUp, keyCode: 60, timestamp: 1.08), field: .unknown).activation == nil)
        _ = machine.process(.init(.modifierDown, keyCode: 60, timestamp: 1.2), field: .unknown)
        #expect(machine.process(.init(.modifierUp, keyCode: 60, timestamp: 1.3), field: .unknown).activation == id)
        _ = machine.process(.init(.modifierDown, keyCode: 60, timestamp: 2), field: .unknown)
        _ = machine.process(.init(.down, keyCode: 0, timestamp: 2.1), field: .editable)
        _ = machine.process(.init(.modifierUp, keyCode: 60, timestamp: 2.2), field: .unknown)
        _ = machine.process(.init(.modifierDown, keyCode: 60, timestamp: 2.3), field: .unknown)
        #expect(machine.process(.init(.modifierUp, keyCode: 60, timestamp: 2.4), field: .unknown).activation == nil)
    }
    @Test func expansionRetainsOnlyConfiguredPrefixAndClearsAtFocusOrSecureBoundary() {
        let expansion = CompanionKeywordExpansion(id: UUID(), keyword: ";ok", replacement: "👍")
        var machine = CompanionKeyboardStateMachine(configuration: .init(expansions: [expansion]))
        _ = machine.process(.init(.startOfText, timestamp: 1), field: .editable)
        for (offset, text) in [";", "o", "k"].enumerated() {
            _ = machine.process(.init(.down, timestamp: 1.1 + Double(offset) / 10, text: text), field: .editable)
        }
        #expect(machine.retainedSuffixLength == 3)
        #expect(machine.process(.init(.down, timestamp: 1.5, text: " "), field: .editable).expansion == expansion)
        for (offset, text) in ["p", "r", "i", "v", "a", "t", "e"].enumerated() {
            _ = machine.process(.init(.down, timestamp: 2 + Double(offset) / 10, text: text), field: .editable)
            #expect(machine.retainedSuffixLength == 0)
        }
        _ = machine.process(.init(.down, timestamp: 3, text: " "), field: .editable)
        _ = machine.process(.init(.down, timestamp: 3.1, text: ";"), field: .editable)
        _ = machine.process(.init(.boundary, timestamp: 3.2), field: .unknown)
        #expect(machine.retainedSuffixLength == 0)
        #expect(machine.process(.init(.down, timestamp: 3.3, text: " "), field: .secure).expansion == nil)
    }
    @Test func malformedAndAmbiguousConfigurationIsRejected() {
        let id = UUID()
        #expect(!CompanionKeyboardConfiguration(keys: [.init(id: id, key: .a), .init(id: UUID(), key: .a)]).isValid)
        #expect(!CompanionKeyboardConfiguration(keys: [.init(id: id, key: .a, requiresHyper: true)]).isValid)
        #expect(!CompanionKeyboardConfiguration(expansions: [.init(id: id, keyword: "ordinary", replacement: "x")]).isValid)
        #expect(CompanionKeyboardConfiguration(expansions: [.init(id: id, keyword: ";x", replacement: "x")]).isValid)
    }
    @Test @MainActor func controllerIsInertUntilConfigureAndRevokesSynchronously() async {
        let driver = FakeKeyboardDriver(); let controller = CompanionKeyboardController(driver: driver)
        let session = UUID(); controller.connect(session: session)
        #expect(await driver.starts == 0)
        let config = CompanionKeyboardConfiguration(keys: [.init(id: UUID(), key: .f6)])
        let deadline = ContinuousClock().now.advanced(by: .seconds(5))
        #expect(await controller.handle(.configure(config), session: session, deadline: deadline) == .configured(config.revision))
        #expect(await driver.isAuthorized())
        controller.revoke()
        #expect(await driver.isAuthorized() == false)
        await controller.cleanupAfterRevocation()
        #expect(await controller.handle(.nextActivations, session: session, deadline: deadline) == .failure(.disconnected))
    }
}
private actor FakeKeyboardDriver: CompanionKeyboardDriving {
    private(set) var starts = 0
    private var authorized: (@Sendable () -> Bool)?
    func start(configuration: CompanionKeyboardConfiguration, authorized: @escaping @Sendable () -> Bool,
               activation: @escaping @Sendable (UUID) -> Void, stopped: @escaping @Sendable () -> Void) { starts += 1; self.authorized = authorized }
    func stop() { authorized = nil }
    func isAuthorized() -> Bool { authorized?() == true }
}
