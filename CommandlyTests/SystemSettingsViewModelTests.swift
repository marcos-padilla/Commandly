import CommandKit
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct SystemSettingsViewModelTests {
    @Test func catalogOpenAndSearchDoNotRequestNavigation() async {
        let opener = SettingsModelTestOpener()
        let model = makeModel(opener)
        model.query = "display"
        model.moveSelection(offset: 1)
        model.perform(BuiltInCommandActionID.openActions)
        #expect(model.items.count == 6)
        #expect(await opener.requests.isEmpty)
        #expect(model.menuActions.contains { $0.id == SystemSettingsActionID.openSelected })
    }
    @Test func explicitOpenUsesSelectedPaneOnceAndDismissesAfterAcceptedRequest() async throws {
        let opener = SettingsModelTestOpener()
        var opened = 0
        let model = SystemSettingsViewModel(opener: opener, onGoBack: {}, onOpened: { opened += 1 })
        model.query = "sound"
        #expect(model.selectedItem?.pane == .sound)
        model.openSelected(); model.openSelected()
        await model.flushForTesting()
        #expect(await opener.requests == [.sound])
        #expect(opened == 1 && !model.isOpening)
        #expect(model.statusMessage == "Requested Sound in System Settings.")
    }
    @Test func fallbackAndFailureKeepSelectionAndShowRecovery() async {
        let opener = SettingsModelTestOpener(mode: .fallback)
        var opened = 0
        let model = SystemSettingsViewModel(opener: opener, onGoBack: {}, onOpened: { opened += 1 })
        model.openSelected()
        await model.flushForTesting()
        #expect(opened == 0 && model.canOpen)
        #expect(model.statusMessage?.contains("choose Displays") == true)
        await opener.setMode(.failure)
        model.openSelected()
        await model.flushForTesting()
        #expect(opened == 0 && model.canOpen)
        #expect(model.statusMessage == SystemSettingsNavigationError.navigationFailed.message)
        await opener.setMode(.success)
        model.openSelected()
        await model.flushForTesting()
        #expect(opened == 1)
    }
    @Test func invalidSearchAndDisabledModelCannotDispatch() async {
        let opener = SettingsModelTestOpener()
        let model = makeModel(opener)
        model.query = "no matching setting"
        model.openSelected()
        #expect(!model.canOpen && model.selectedItem == nil)
        let disabled = SystemSettingsViewModel(opener: opener, isEnabled: false, onGoBack: {}, onOpened: {})
        disabled.openSelected(); disabled.perform(SystemSettingsActionID.openApplication)
        await disabled.flushForTesting()
        #expect(await opener.requests.isEmpty)
        #expect(!disabled.canOpen)
    }
    @Test func changedQueryAndStopSuppressQueuedAndLateNavigationResults() async {
        let opener = SettingsModelTestOpener(mode: .held)
        var opened = 0
        let model = SystemSettingsViewModel(opener: opener, onGoBack: {}, onOpened: { opened += 1 })
        model.openSelected()
        let queued = model.pendingOperationForTesting()
        model.query = "sound"
        await queued?.value
        #expect(await opener.requests.isEmpty)
        model.openSelected()
        let active = model.pendingOperationForTesting()
        await opener.waitForStart()
        model.stop()
        await opener.release()
        await active?.value
        #expect(opened == 0 && model.statusMessage == nil && !model.isOpening)
    }
    @Test func escapeClearsSearchBeforeLeavingAndOpenApplicationIsExplicit() async {
        let opener = SettingsModelTestOpener()
        let model = makeModel(opener)
        model.query = "keyboard"
        #expect(model.handleEscape())
        #expect(model.query.isEmpty)
        #expect(!model.handleEscape())
        model.perform(SystemSettingsActionID.openApplication)
        await model.flushForTesting()
        #expect(await opener.requests.count == 1)
        #expect(await opener.requests.first == Optional<SystemSettingsPane?>.some(nil))
    }
    private func makeModel(_ opener: SettingsModelTestOpener) -> SystemSettingsViewModel {
        .init(opener: opener, onGoBack: {}, onOpened: {})
    }
}

actor SettingsModelTestOpener: SystemSettingsOpening {
    enum Mode: Sendable { case success, failure, fallback, held }
    private var mode: Mode
    private(set) var requests: [SystemSettingsPane?] = []
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(mode: Mode = .success) { self.mode = mode }
    func setMode(_ mode: Mode) { self.mode = mode }
    func open(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationResult {
        requests.append(pane)
        if mode == .held {
            await withCheckedContinuation { continuation in
                pending = continuation
                started?.resume(); started = nil
            }
        }
        if mode == .failure { throw SystemSettingsNavigationError.navigationFailed }
        if mode == .fallback { return .openedApplication(fallbackFor: pane) }
        return pane.map { .requestedPane($0) } ?? .openedApplication(fallbackFor: nil)
    }
    func waitForStart() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { pending?.resume(); pending = nil }
}
