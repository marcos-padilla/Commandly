import CommandKit
import Foundation
import Observation

@Observable
@MainActor
final class MenuBarShortcutsModel: LauncherApplicationModel {
    static let toggleAction = CommandActionID(rawValue: "menu-bar.toggle-pin")
    let controller: MenuBarShortcutController
    var query = "" { didSet { selectedID = filteredItems.first?.id } }
    var selectedID: CommandID?
    var showsActionsMenu = false
    @ObservationIgnored private let onGoBack: () -> Void
    init(controller: MenuBarShortcutController, onGoBack: @escaping () -> Void) {
        self.controller = controller; self.onGoBack = onGoBack
    }
    var statusMessage: String? { controller.message }
    var filteredItems: [MenuBarShortcutItem] {
        let pinned = Set(controller.pinnedIDs)
        let all = controller.pinnedItems + controller.catalog.filter { !pinned.contains($0.id) }
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { phrase.isEmpty || "\($0.title) \($0.subtitle)".localizedStandardContains(phrase) }
    }
    var selectedItem: MenuBarShortcutItem? { filteredItems.first { $0.id == selectedID } }
    var isSelectedPinned: Bool { selectedID.map { controller.pinnedIDs.contains($0) } == true }
    var canToggle: Bool { !controller.needsPreferenceReset && (isSelectedPinned || selectedItem?.isEnabled == true) }
    var footerActions: [CommandActionDescriptor] {
        guard canToggle else { return [] }
        return [.init(id: Self.toggleAction, title: isSelectedPinned ? "Remove from Menu Bar" : "Pin to Menu Bar",
                      isPrimary: true, keyHint: .return)]
    }
    var menuActions: [CommandActionDescriptor] { [] }
    func load() { controller.refresh(); reconcileSelection() }
    func reconcileSelection() {
        if !filteredItems.contains(where: { $0.id == selectedID }) { selectedID = filteredItems.first?.id }
    }
    func toggleSelected() {
        guard canToggle, let selectedID else { return }
        if isSelectedPinned { controller.remove(selectedID) } else { controller.pin(selectedID) }
        reconcileSelection()
    }
    func moveSelection(offset: Int) {
        guard !filteredItems.isEmpty else { selectedID = nil; return }
        let index = filteredItems.firstIndex { $0.id == selectedID } ?? 0
        selectedID = filteredItems[min(max(index + offset, 0), filteredItems.count - 1)].id
    }
    func perform(_ actionID: CommandActionID) { if actionID == Self.toggleAction { toggleSelected() } }
    func handleEscape() -> Bool { false }
    func stop() { showsActionsMenu = false }
    func goBack() { onGoBack() }
}
