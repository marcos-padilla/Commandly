import Foundation
import Observation
import AppKit
import CommandKit

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Types"
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    func matches(_ type: ClipboardContentType) -> Bool {
        switch self {
        case .all: return true
        case .text: return type == .text
        case .image: return type == .image
        case .file: return type == .fileURL
        }
    }
}

@Observable
@MainActor
final class ClipboardHistoryViewModel {
    /// Not observation-ignored: the clipboard surface must refresh when
    /// `store.entries` changes while this view model is alive. Dismiss paths
    /// nil out `LauncherViewModel.clipboardViewModel` so background polls do
    /// not keep the launcher subscribed after close.
    private let store: ClipboardHistoryStore
    private let onGoBack: () -> Void
    private let onDismiss: () -> Void

    var query: String = "" {
        didSet { refreshSelection() }
    }
    var filter: ClipboardHistoryFilter = .all {
        didSet { refreshSelection() }
    }
    var selectedID: UUID?
    var showsActionsMenu = false
    private(set) var statusMessage: String?
    private(set) var shouldScrollToSelection = false
    private(set) var inputDevice: LauncherInputDevice = .pointer
    private var hoveredID: UUID?

    let manifestTitle = "Clipboard History"
    let manifestSystemImage = "clipboard"
    let searchPlaceholder = "Type to filter entries…"

    init(
        store: ClipboardHistoryStore,
        onGoBack: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
        store.startMonitoring()
        store.poll()
        selectedID = filteredEntries.first?.id
    }

    var filteredEntries: [ClipboardHistoryEntry] {
        // Read observable inputs before touching `store` so Observation always
        // registers query/filter dependencies (including when entries is empty).
        // Matching uses capture-time metadata only — never runs Vision/PDFKit here.
        let activeFilter = filter
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        return store.entries.filter { entry in
            guard activeFilter.matches(entry.contentType) else { return false }
            guard trimmed.isEmpty == false else { return true }
            return entry.preview.lowercased().contains(needle)
                || (entry.text?.lowercased().contains(needle) ?? false)
                || (entry.searchableText?.lowercased().contains(needle) ?? false)
                || entry.classificationLabels.contains { $0.lowercased().contains(needle) }
                || (entry.sourceAppName?.lowercased().contains(needle) ?? false)
        }
    }

    var sections: [(title: String, entries: [ClipboardHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
            if calendar.isDateInToday(entry.createdAt) { return "Today" }
            if calendar.isDateInYesterday(entry.createdAt) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: entry.createdAt)
        }
        let order = ["Today", "Yesterday"]
        let keys = grouped.keys.sorted { left, right in
            let leftIndex = order.firstIndex(of: left) ?? Int.max
            let rightIndex = order.firstIndex(of: right) ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left > right
        }
        return keys.compactMap { key in
            guard let entries = grouped[key], entries.isEmpty == false else { return nil }
            return (key, entries)
        }
    }

    var selectedEntry: ClipboardHistoryEntry? {
        filteredEntries.first { $0.id == selectedID } ?? filteredEntries.first
    }

    var footerActions: [CommandActionDescriptor] {
        let hasSelection = selectedEntry != nil
        return [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy",
                isPrimary: true,
                keyHint: .return,
                isEnabled: hasSelection
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: true
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy to Clipboard",
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.delete,
                title: "Delete",
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.clearHistory,
                title: "Clear History",
                isEnabled: store.entries.isEmpty == false
            )
        ]
    }

    func select(_ id: UUID) {
        shouldScrollToSelection = false
        selectedID = id
        statusMessage = nil
    }

    func setHovered(_ id: UUID?) {
        hoveredID = id
        guard let id, inputDevice == .pointer else { return }
        select(id)
    }

    func clearHovered(_ id: UUID) {
        if hoveredID == id {
            hoveredID = nil
        }
    }

    func beginPointerInput() {
        guard inputDevice != .pointer else { return }
        inputDevice = .pointer
        if let hoveredID {
            select(hoveredID)
        }
    }

    func moveSelection(offset: Int) {
        let list = filteredEntries
        guard list.isEmpty == false else { return }
        let currentIndex = list.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = (currentIndex + offset + list.count) % list.count
        inputDevice = .keyboard
        shouldScrollToSelection = true
        selectedID = list[nextIndex].id
        statusMessage = nil
    }

    func refreshSelection() {
        if filteredEntries.contains(where: { $0.id == selectedID }) == false {
            selectedID = filteredEntries.first?.id
        }
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case BuiltInCommandActionID.copy:
            copySelected()
        case BuiltInCommandActionID.delete:
            deleteSelected()
        case BuiltInCommandActionID.clearHistory:
            store.clear()
            selectedID = nil
            statusMessage = "Clipboard history cleared."
            showsActionsMenu = false
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            onGoBack()
        default:
            break
        }
    }

    func copySelected() {
        guard let entry = selectedEntry else { return }
        copyEntry(entry)
    }

    /// Copies a specific entry (e.g. sidebar hover Copy) without relying on selection.
    /// Success feedback for the row Copy control is handled locally in the view.
    func copyEntry(_ entry: ClipboardHistoryEntry) {
        store.copyToPasteboard(entry)
        showsActionsMenu = false
    }

    func deleteSelected() {
        guard let id = selectedEntry?.id else { return }
        store.delete(id: id)
        refreshSelection()
        statusMessage = "Deleted."
        showsActionsMenu = false
    }

    func goBack() {
        onGoBack()
    }

    func dismiss() {
        onDismiss()
    }

    func copiedLabel(for entry: ClipboardHistoryEntry) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(entry.createdAt) {
            formatter.dateFormat = "'Today at' h:mm:ss a"
        } else if Calendar.current.isDateInYesterday(entry.createdAt) {
            formatter.dateFormat = "'Yesterday at' h:mm:ss a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
        }
        return formatter.string(from: entry.createdAt)
    }
}
