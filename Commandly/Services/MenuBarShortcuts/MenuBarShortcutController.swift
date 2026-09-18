import CommandKit
import Foundation
import Observation

struct MenuBarShortcutItem: Identifiable, Equatable {
    let id: CommandID
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
}

@MainActor
protocol MenuBarShortcutsPresenting {
    func update(_ items: [MenuBarShortcutItem], invoke: @escaping (CommandID) -> Void,
                remove: @escaping (CommandID) -> Void, manage: @escaping () -> Void)
    func stop()
}

/// Owns opted-in status items independently of the temporary launcher view. Publishing preferences
/// never executes a command; every native menu action revalidates membership and current enablement.
@Observable
@MainActor
final class MenuBarShortcutController {
    private(set) var pinnedIDs: [CommandID] = []
    private(set) var catalog: [MenuBarShortcutItem] = []
    private(set) var needsPreferenceReset = false
    private(set) var message: String?
    @ObservationIgnored private let store: any MenuBarShortcutStoring
    @ObservationIgnored private let presenter: any MenuBarShortcutsPresenting
    @ObservationIgnored private var catalogProvider: () -> [MenuBarShortcutItem] = { [] }
    @ObservationIgnored private var execute: (CommandID) async -> Void = { _ in }
    @ObservationIgnored private var manage: () -> Void = {}
    @ObservationIgnored private var invocations: [CommandID: Task<Void, Never>] = [:]
    @ObservationIgnored private var invocationIDs: [CommandID: UUID] = [:]
    @ObservationIgnored private var isStarted = false

    init(store: any MenuBarShortcutStoring, presenter: any MenuBarShortcutsPresenting) {
        self.store = store; self.presenter = presenter
    }

    var pinnedItems: [MenuBarShortcutItem] {
        pinnedIDs.map { id in
            catalog.first { $0.id == id } ?? MenuBarShortcutItem(id: id, title: "Unavailable shortcut",
                subtitle: id.rawValue, systemImage: "questionmark.square", isEnabled: false)
        }
    }

    func start(catalog: @escaping () -> [MenuBarShortcutItem], execute: @escaping (CommandID) async -> Void,
               manage: @escaping () -> Void) {
        guard !isStarted else { return }
        isStarted = true
        catalogProvider = catalog; self.execute = execute; self.manage = manage
        do { pinnedIDs = try MenuBarShortcutPolicy.validate(store.load().map(\.rawValue)) }
        catch {
            needsPreferenceReset = true
            message = "Saved menu-bar shortcuts could not be read. Reset them to choose a new list."
        }
        refresh()
    }

    func refresh() {
        guard isStarted else { return }
        var seen: Set<CommandID> = []
        catalog = catalogProvider().filter { seen.insert($0.id).inserted }
        presenter.update(pinnedItems, invoke: { [weak self] in self?.invoke($0) },
            remove: { [weak self] in self?.remove($0) }, manage: { [weak self] in self?.manage() })
    }

    func pin(_ id: CommandID) {
        guard isStarted, !needsPreferenceReset else { return }
        refresh()
        guard !pinnedIDs.contains(id), catalog.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        guard pinnedIDs.count < MenuBarShortcutPolicy.maximumItems else {
            message = "Keep up to eight shortcuts in the menu bar. Remove one to add another."; return
        }
        persist(pinnedIDs + [id], success: "Added to the menu bar.")
    }

    func remove(_ id: CommandID) {
        guard isStarted, !needsPreferenceReset, pinnedIDs.contains(id) else { return }
        persist(pinnedIDs.filter { $0 != id }, success: "Removed from the menu bar.")
    }

    func resetInvalidPreferences() {
        guard needsPreferenceReset else { return }
        persist([], success: "Menu-bar shortcuts reset. Choose the tools you want to keep nearby.")
    }

    func invoke(_ id: CommandID) {
        guard isStarted, invocations[id] == nil, pinnedIDs.contains(id) else { return }
        refresh()
        guard catalog.contains(where: { $0.id == id && $0.isEnabled }) else {
            message = "That shortcut is unavailable. Enable its application in Settings or remove it."; return
        }
        let execute = execute
        let token = UUID()
        invocationIDs[id] = token
        invocations[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if invocationIDs[id] == token { invocations[id] = nil; invocationIDs[id] = nil }
            }
            guard !Task.isCancelled, isStarted, pinnedIDs.contains(id) else { return }
            refresh()
            guard catalog.contains(where: { $0.id == id && $0.isEnabled }) else { return }
            await execute(id)
        }
    }

    func stop() {
        isStarted = false
        invocations.values.forEach { $0.cancel() }
        invocations.removeAll()
        invocationIDs.removeAll()
        presenter.stop()
        catalogProvider = { [] }; execute = { _ in }; manage = {}
    }

    func waitForInvocationForTesting(_ id: CommandID) async { await invocations[id]?.value }

    private func persist(_ ids: [CommandID], success: String) {
        do {
            try store.save(ids)
            pinnedIDs = ids
            needsPreferenceReset = false
            message = success
            refresh()
        } catch { message = "The menu-bar change could not be saved. Your previous shortcuts are still in place." }
    }
}

@MainActor
final class InMemoryMenuBarShortcutPresenter: MenuBarShortcutsPresenting {
    private(set) var items: [MenuBarShortcutItem] = []
    func update(_ items: [MenuBarShortcutItem], invoke: @escaping (CommandID) -> Void,
                remove: @escaping (CommandID) -> Void, manage: @escaping () -> Void) { self.items = items }
    func stop() { items = [] }
}
