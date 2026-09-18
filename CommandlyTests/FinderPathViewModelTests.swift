import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct FinderPathViewModelTests {
    @Test func openingIsInertAndConsentRequiresSeparateExplicitAction() async throws {
        let context = FinderPathModelTestContext(state: .requiresConsent); let model = context.model()
        model.activate(); #expect(await context.reader.authorizations.isEmpty)
        model.performPrimary(); await model.flushForTesting()
        #expect(await context.reader.authorizations == [false]); #expect(await context.reader.captures == 0)
        #expect(model.needsConsent); #expect(context.copier.paths.isEmpty)
        model.perform(FinderPathActionID.allow); await model.flushForTesting()
        #expect(await context.reader.authorizations == [false, true]); #expect(await context.reader.validations == 1)
        #expect(context.copier.paths == ["/generated/item"]); #expect(model.statusMessage == "Selected Finder item path copied.")
        model.stop()
    }
    @Test func disabledOrUnknownActionsCannotCopyOrRequestPermission() async {
        let context = FinderPathModelTestContext(); let model = context.model(enabled: false)
        model.activate(copyImmediately: true); model.perform(FinderPathActionID.allow); model.performPrimary()
        #expect(await context.reader.authorizations.isEmpty); #expect(context.copier.paths.isEmpty)
        #expect(!model.canCopy); model.stop()
    }
    @Test func deniedChangedContextAndCopyFailureRemainRecoverable() async {
        let context = FinderPathModelTestContext(state: .denied); let model = context.model()
        model.activate(copyImmediately: true); await model.flushForTesting()
        #expect(model.permissionDenied); #expect(context.copier.paths.isEmpty)
        await context.reader.setState(.authorized); await context.reader.setValidationFailure(.changedContext)
        model.performPrimary(); await model.flushForTesting()
        #expect(model.statusMessage == FinderPathError.changedContext.message); #expect(context.copier.paths.isEmpty)
        await context.reader.setValidationFailure(nil); context.copier.fails = true
        model.performPrimary(); await model.flushForTesting()
        #expect(model.statusMessage == FinderPathError.copyFailed.message)
        context.copier.fails = false; model.performPrimary(); await model.flushForTesting()
        #expect(context.copier.paths == ["/generated/item"]); model.stop()
    }
    @Test func rapidCopyCoalescesAndStopDuringValidationRejectsLateCopy() async {
        let context = FinderPathModelTestContext(); let model = context.model()
        await context.reader.holdValidation(); model.activate(); model.performPrimary(); model.performPrimary()
        await context.reader.waitForValidation()
        let old = model.pendingTaskForTesting
        #expect(await context.reader.captures == 1)
        model.stop(); await context.reader.releaseValidation(); await old?.value
        #expect(context.copier.paths.isEmpty); #expect(model.statusMessage == nil)
        model.activate(); model.performPrimary(); await model.flushForTesting()
        #expect(context.copier.paths == ["/generated/item"]); model.stop()
    }
    @Test func escapeCancelsWithoutLeavingAndRecoveryOpensOnlyByAction() async {
        let context = FinderPathModelTestContext(); let model = context.model()
        await context.reader.holdValidation(); model.activate(copyImmediately: true); await context.reader.waitForValidation()
        let old = model.pendingTaskForTesting
        #expect(model.handleEscape()); #expect(!model.isWorking); #expect(!model.handleEscape())
        await context.reader.releaseValidation(); await old?.value; #expect(context.copier.paths.isEmpty)
        #expect(context.settingsOpenCount == 0); model.openSettings(); await model.flushForTesting()
        #expect(context.settingsOpenCount == 1); model.stop()
    }
}

@MainActor private final class FinderPathModelTestContext {
    let reader: FinderPathModelTestReader; let copier = FinderPathModelTestCopier()
    var settingsOpenCount = 0
    init(state: FinderPathAuthorization = .authorized) { reader = FinderPathModelTestReader(state: state) }
    func model(enabled: Bool = true) -> FinderPathViewModel {
        .init(services: .init(reader: reader, copier: copier, openSettings: { [weak self] in self?.settingsOpenCount += 1 }),
              isEnabled: enabled, onGoBack: {})
    }
}
private actor FinderPathModelTestReader: FinderPathReading {
    private var state: FinderPathAuthorization
    private var failure: FinderPathError?
    private var holding = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var authorizations: [Bool] = []; private(set) var captures = 0; private(set) var validations = 0
    init(state: FinderPathAuthorization) { self.state = state }
    func authorization(allowPrompt: Bool) -> FinderPathAuthorization {
        authorizations.append(allowPrompt)
        if allowPrompt, state == .requiresConsent { state = .authorized }
        return state
    }
    func capture() -> FinderPathSnapshot { captures += 1; return .init(id: UUID(), path: "/generated/item", origin: .selectedItem) }
    func validate(_ snapshot: FinderPathSnapshot) async throws {
        validations += 1
        if holding { await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil } }
        if let failure { throw failure }
    }
    func setState(_ state: FinderPathAuthorization) { self.state = state }
    func setValidationFailure(_ value: FinderPathError?) { failure = value }
    func holdValidation() { holding = true }
    func waitForValidation() async { if held == nil { await withCheckedContinuation { waiter = $0 } } }
    func releaseValidation() { holding = false; held?.resume(); held = nil }
}
@MainActor private final class FinderPathModelTestCopier: FinderPathCopying {
    var paths: [String] = []; var fails = false
    func copy(_ path: String) throws { if fails { throw FinderPathError.copyFailed }; paths.append(path) }
}
