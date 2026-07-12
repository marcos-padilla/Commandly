import Foundation
import Observation

@Observable
@MainActor
final class LauncherViewModel {
    private(set) var items: [LauncherItem]
    var query: String = "" {
        didSet { clampSelection() }
    }
    var selectedID: String?
    private(set) var statusMessage: String?
    /// When true, the list may auto-scroll to keep the selection visible (keyboard navigation).
    private(set) var shouldScrollToSelection = false

    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    init(
        items: [LauncherItem] = LauncherPlaceholderCatalog.items,
        onDismiss: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.items = items
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.selectedID = filteredItems.first?.id
    }

    var filteredItems: [LauncherItem] {
        items.filter { $0.matches(query: query) }
    }

    var sections: [(kind: LauncherSectionKind, items: [LauncherItem])] {
        LauncherSectionKind.allCases.compactMap { kind in
            let sectionItems = filteredItems.filter { $0.section == kind }
            guard sectionItems.isEmpty == false else { return nil }
            return (kind, sectionItems)
        }
    }

    var selectedItem: LauncherItem? {
        filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    var primaryActionTitle: String {
        guard let selectedItem else { return "Select" }
        switch selectedItem.action {
        case .openSettings:
            return "Open Settings"
        case .dismiss:
            return "Close"
        case .placeholder:
            return "Preview"
        }
    }

    func prepareForPresentation() {
        query = ""
        statusMessage = nil
        shouldScrollToSelection = false
        selectedID = filteredItems.first?.id
    }

    func select(_ id: String) {
        shouldScrollToSelection = false
        selectedID = id
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        let list = filteredItems
        guard list.isEmpty == false else { return }
        let currentIndex = list.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = (currentIndex + offset + list.count) % list.count
        shouldScrollToSelection = true
        selectedID = list[nextIndex].id
        statusMessage = nil
    }

    func confirmSelection() {
        guard let item = selectedItem else { return }
        switch item.action {
        case .openSettings:
            onDismiss()
            onOpenSettings()
        case .dismiss:
            onDismiss()
        case .placeholder(let message):
            statusMessage = message
        }
    }

    func dismiss() {
        onDismiss()
    }

    private func clampSelection() {
        let list = filteredItems
        if list.isEmpty {
            selectedID = nil
            return
        }
        if list.contains(where: { $0.id == selectedID }) == false {
            selectedID = list.first?.id
        }
    }
}
