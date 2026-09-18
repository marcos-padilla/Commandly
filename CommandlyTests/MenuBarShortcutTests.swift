import CommandKit
import Foundation
import Testing
@testable import Commandly

@Suite("Menu-bar shortcut preferences and runtime", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarShortcutTests {
    @Test
    func preferencesRoundTripOnlyIDsAndRejectCorruptionWithoutOverwritingIt() throws {
        let suite = "commandly.menu-bar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMenuBarShortcutStore(defaults: defaults)
        let ids = [CommandID(rawValue: "camera.preview"), CommandID(rawValue: "unknown.old.tool")]
        try store.save(ids)
        #expect(try store.load() == ids)
        let bad = Data(repeating: 0, count: MenuBarShortcutPolicy.maximumPreferenceBytes + 1)
        defaults.set(bad, forKey: "menuBar.shortcuts.v1")
        #expect(throws: MenuBarShortcutError.self) { try store.load() }
        #expect(defaults.data(forKey: "menuBar.shortcuts.v1") == bad)
        #expect(throws: MenuBarShortcutError.self) { try store.save(ids + ids) }
        #expect(defaults.data(forKey: "menuBar.shortcuts.v1") == bad)
    }

    @Test
    func policyRejectsOversizedListsAndInvalidIdentifiers() {
        for values in [[""], ["a\nb"], [String(repeating: "x", count: 257)], ["same", "same"],
                       (0...8).map { "tool.\($0)" }] {
            #expect(throws: MenuBarShortcutError.self) { try MenuBarShortcutPolicy.validate(values) }
        }
    }

    @Test
    func loadingAndPinningOnlyPresentItemsWithoutExecutingTools() {
        let h = MenuBarTestHarness()
        h.start()
        #expect(h.presenter.items.isEmpty)
        h.controller.pin(h.first.id)
        #expect(h.store.ids == [h.first.id])
        #expect(h.presenter.items == [h.first])
        #expect(h.executions.isEmpty)
        h.controller.refresh()
        #expect(h.executions.isEmpty)
    }

    @Test
    func writeFailureLeavesBothPersistedAndVisibleItemsIntact() {
        let h = MenuBarTestHarness()
        h.start(); h.controller.pin(h.first.id)
        h.store.failsSave = true
        h.controller.remove(h.first.id)
        #expect(h.controller.pinnedIDs == [h.first.id])
        #expect(h.store.ids == [h.first.id])
        #expect(h.presenter.items == [h.first])
        #expect(h.controller.message?.contains("could not be saved") == true)
    }

    @Test
    func missingAndDisabledPinsRemainRemovableAndCannotExecute() async {
        let h = MenuBarTestHarness()
        let missing = CommandID(rawValue: "removed.application")
        h.store.ids = [h.first.id, missing]
        h.start()
        let staleAction = h.presenter.invoke
        h.items = [h.disabledFirst]
        staleAction?(h.first.id)
        h.controller.invoke(missing)
        await h.controller.waitForInvocationForTesting(h.first.id)
        #expect(h.executions.isEmpty)
        #expect(h.presenter.items.count == 2)
        #expect(h.presenter.items.allSatisfy { !$0.isEnabled })
        h.controller.remove(missing)
        h.controller.remove(h.first.id)
        #expect(h.store.ids.isEmpty && h.presenter.items.isEmpty)
    }

    @Test
    func removalBeforeInvocationTaskStartsInvalidatesItsPendingAction() async {
        let h = MenuBarTestHarness()
        h.start(); h.controller.pin(h.first.id)
        h.controller.invoke(h.first.id)
        h.controller.remove(h.first.id)
        await h.controller.waitForInvocationForTesting(h.first.id)
        #expect(h.executions.isEmpty)
    }

    @Test
    func repeatedMenuClicksExecuteOnceAndNeverInvokeAnUnpinnedTarget() async {
        let h = MenuBarTestHarness()
        h.start(); h.controller.pin(h.first.id)
        h.controller.invoke(CommandID(rawValue: "not.pinned"))
        h.controller.invoke(h.first.id)
        h.controller.invoke(h.first.id)
        await h.controller.waitForInvocationForTesting(h.first.id)
        #expect(h.executions == [h.first.id])
    }

    @Test
    func corruptPreferencesRequireExplicitResetAndDoNotCreateIcons() {
        let h = MenuBarTestHarness()
        h.store.failsLoad = true
        h.start()
        #expect(h.controller.needsPreferenceReset)
        h.controller.pin(h.first.id)
        #expect(h.store.saves == 0 && h.presenter.items.isEmpty)
        h.controller.resetInvalidPreferences()
        #expect(!h.controller.needsPreferenceReset && h.store.saves == 1)
        h.controller.pin(h.first.id)
        #expect(h.presenter.items == [h.first])
    }

    @Test
    func pinLimitDoesNotDropExistingItemsAndRuntimeStopRemovesNativeOwnership() {
        let h = MenuBarTestHarness()
        h.items = (0...8).map { h.item(id: "tool.\($0)") }
        h.start()
        for item in h.items { h.controller.pin(item.id) }
        #expect(h.controller.pinnedIDs.count == 8)
        #expect(h.store.ids == h.items.prefix(8).map(\.id))
        h.controller.stop()
        #expect(h.presenter.stops == 1 && h.presenter.items.isEmpty)
        #expect(h.store.ids.count == 8)
    }

    @Test
    func managerKeyboardSelectionPinsAndRemovesWithoutRunningSelectedTool() {
        let h = MenuBarTestHarness()
        h.items.append(h.item(id: "tool.second"))
        h.start()
        let model = MenuBarShortcutsModel(controller: h.controller, onGoBack: {})
        model.load()
        model.moveSelection(offset: 1)
        model.perform(MenuBarShortcutsModel.toggleAction)
        #expect(h.controller.pinnedIDs == [CommandID(rawValue: "tool.second")])
        #expect(model.isSelectedPinned)
        model.perform(MenuBarShortcutsModel.toggleAction)
        #expect(h.controller.pinnedIDs.isEmpty)
        model.query = "nothing matches"
        #expect(model.filteredItems.isEmpty && model.footerActions.isEmpty)
        #expect(h.executions.isEmpty)
    }

    @Test
    func catalogIncludesOnlyRealLaunchableCommandsAndKeepsExactToolIdentity() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        let clock = ContinuousClock()
        let started = clock.now
        let items = MenuBarShortcutCatalog.items(in: registry)
        let elapsed = started.duration(to: clock.now)
        Attachment.record("Registered tools: \(items.count)\nCatalog construction: \(elapsed)\nDebug build; one local sample, including sorting.\n", named: "menu-bar-catalog-timing.txt")
        #expect(!items.contains { $0.id == BuiltInLauncherApplicationGroup.catalogID })
        #expect(items.contains { $0.id == ScreenRecordingApplication.stopToolID })
        #expect(items.contains { $0.id == MenuBarShortcutsApplication.id })
        #expect(items.count == Set(items.map(\.id)).count)
        #expect(items.allSatisfy { registry.isLaunchableCommand($0.id) })
    }
}

@MainActor
private final class MenuBarTestHarness {
    let store = MenuBarTestStore()
    let presenter = MenuBarTestPresenter()
    lazy var controller = MenuBarShortcutController(store: store, presenter: presenter)
    var executions: [CommandID] = []
    var items: [MenuBarShortcutItem] = [MenuBarShortcutItem(id: CommandID(rawValue: "tool.first"),
        title: "First", subtitle: "A generated test tool", systemImage: "star", isEnabled: true)]
    var first: MenuBarShortcutItem { item(id: "tool.first", title: "First") }
    var disabledFirst: MenuBarShortcutItem { item(id: "tool.first", title: "First", enabled: false) }
    func item(id: String, title: String? = nil, enabled: Bool = true) -> MenuBarShortcutItem {
        .init(id: CommandID(rawValue: id), title: title ?? id, subtitle: "A generated test tool", systemImage: "star", isEnabled: enabled)
    }
    func start() {
        controller.start(catalog: { [weak self] in self?.items ?? [] },
            execute: { [weak self] in self?.executions.append($0) }, manage: {})
    }
}

@MainActor
private final class MenuBarTestStore: MenuBarShortcutStoring {
    var ids: [CommandID] = []
    var failsLoad = false
    var failsSave = false
    var saves = 0
    func load() throws -> [CommandID] {
        if failsLoad { throw MenuBarShortcutError.invalidPreferences }; return ids
    }
    func save(_ ids: [CommandID]) throws {
        if failsSave { throw MenuBarShortcutError.saveFailed }; self.ids = ids; saves += 1
    }
}

@MainActor
private final class MenuBarTestPresenter: MenuBarShortcutsPresenting {
    var items: [MenuBarShortcutItem] = []
    var invoke: ((CommandID) -> Void)?
    var stops = 0
    func update(_ items: [MenuBarShortcutItem], invoke: @escaping (CommandID) -> Void,
                remove: @escaping (CommandID) -> Void, manage: @escaping () -> Void) {
        self.items = items; self.invoke = invoke
    }
    func stop() { items = []; stops += 1 }
}
