import CommandKit
import Foundation
import Infrastructure
import Observation

enum ProductivityLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case snippets
    case quickNotes
    case quicklinks
    case emojiKeywords

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Items"
        case .snippets: return "Snippets"
        case .quickNotes: return "Quick Notes"
        case .quicklinks: return "Quicklinks"
        case .emojiKeywords: return "Emoji Keywords"
        }
    }

    var kind: ProductivityLibraryItemKind? {
        switch self {
        case .all: return nil
        case .snippets: return .snippet
        case .quickNotes: return .quickNote
        case .quicklinks: return .quicklink
        case .emojiKeywords: return .emojiKeyword
        }
    }
}

enum ProductivityLibraryLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ProductivityLibraryEditorMode: Equatable {
    case creating
    case editing(UUID)
}

struct ProductivityLibraryDraft: Equatable {
    var kind: ProductivityLibraryItemKind
    var title: String
    var content: String

    init(
        kind: ProductivityLibraryItemKind = .snippet,
        title: String = "",
        content: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.content = content
    }

    init(item: ProductivityLibraryItem) {
        self.init(kind: item.kind, title: item.title, content: item.content)
    }
}

enum ProductivityLibraryActionID {
    static let useSelected = CommandActionID(rawValue: "productivity-library.use")
    static let createItem = CommandActionID(rawValue: "productivity-library.create")
    static let editSelected = CommandActionID(rawValue: "productivity-library.edit")
    static let requestDelete = CommandActionID(rawValue: "productivity-library.delete")
    static let saveDraft = CommandActionID(rawValue: "productivity-library.save")
    static let cancelEditor = CommandActionID(rawValue: "productivity-library.cancel-editor")
}

@Observable
@MainActor
final class ProductivityLibraryViewModel: LauncherApplicationModel {
    @ObservationIgnored
    private let persistence: any ProductivityLibraryPersisting
    @ObservationIgnored
    private let pasteboard: any PasteboardAccessing
    @ObservationIgnored
    private let urlOpener: any URLOpening
    @ObservationIgnored
    private let quicklinkValidator: ProductivityQuicklinkValidator
    @ObservationIgnored
    private let now: () -> Date
    @ObservationIgnored
    private let makeID: () -> UUID
    @ObservationIgnored
    private let onGoBack: () -> Void
    @ObservationIgnored
    private let onDismiss: () -> Void
    @ObservationIgnored
    private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored
    private var primaryActionTask: Task<Void, Never>?

    private(set) var items: [ProductivityLibraryItem] = []
    private(set) var selectedID: UUID?
    private(set) var loadState: ProductivityLibraryLoadState = .idle
    private(set) var statusMessage: String?
    private(set) var isSaving = false
    private(set) var isPerformingPrimaryAction = false
    private(set) var pendingDeletionID: UUID?
    private(set) var loadRequestID = 0

    var query: String = "" {
        didSet { refreshSelection() }
    }
    var filter: ProductivityLibraryFilter = .all {
        didSet { refreshSelection() }
    }
    var showsActionsMenu = false
    var editorMode: ProductivityLibraryEditorMode?
    var draft = ProductivityLibraryDraft()

    init(
        services: ProductivityLibraryApplicationServices,
        onGoBack: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.persistence = services.persistence
        self.pasteboard = services.pasteboard
        self.urlOpener = services.urlOpener
        self.quicklinkValidator = services.quicklinkValidator
        self.now = services.now
        self.makeID = services.makeID
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
    }

    var filteredItems: [ProductivityLibraryItem] {
        let activeKind = filter.kind
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard activeKind == nil || item.kind == activeKind else { return false }
            guard needle.isEmpty == false else { return true }
            return item.title.localizedCaseInsensitiveContains(needle)
                || item.content.localizedCaseInsensitiveContains(needle)
                || item.kind.title.localizedCaseInsensitiveContains(needle)
        }
    }

    var selectedItem: ProductivityLibraryItem? {
        filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    var pendingDeletionItem: ProductivityLibraryItem? {
        guard let pendingDeletionID else { return nil }
        return items.first { $0.id == pendingDeletionID }
    }

    var isBusy: Bool {
        isSaving || isPerformingPrimaryAction
    }

    var draftValidationMessage: String? {
        guard editorMode != nil else { return nil }
        do {
            _ = try preparedDraft(draft)
            return nil
        } catch let error as ProductivityLibraryValidationError {
            return error.message
        } catch {
            return "This item can’t be saved."
        }
    }

    var canSaveDraft: Bool {
        editorMode != nil && draftValidationMessage == nil && isBusy == false
    }

    var footerActions: [CommandActionDescriptor] {
        if editorMode != nil {
            return [
                CommandActionDescriptor(
                    id: ProductivityLibraryActionID.saveDraft,
                    title: "Save",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: canSaveDraft
                ),
                CommandActionDescriptor(
                    id: ProductivityLibraryActionID.cancelEditor,
                    title: "Cancel",
                    keyHint: .escape,
                    isEnabled: isSaving == false
                )
            ]
        }
        guard let selectedItem else {
            return [
                CommandActionDescriptor(
                    id: ProductivityLibraryActionID.createItem,
                    title: "New Item",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: loadState == .loaded
                )
            ]
        }
        return [
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.useSelected,
                title: selectedItem.kind.primaryActionTitle,
                isPrimary: true,
                keyHint: .return,
                isEnabled: isBusy == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isBusy == false
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        guard let selectedItem, editorMode == nil else { return [] }
        return [
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.useSelected,
                title: selectedItem.kind.primaryActionTitle,
                isEnabled: isBusy == false
            ),
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.editSelected,
                title: "Edit",
                isEnabled: isBusy == false
            ),
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.requestDelete,
                title: "Delete",
                isEnabled: isBusy == false
            ),
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.createItem,
                title: "New Item",
                isEnabled: isBusy == false
            )
        ]
    }

    func load(force: Bool = false) async {
        guard force || loadState == .idle || loadState == .failed else { return }
        loadState = .loading
        statusMessage = nil
        do {
            let loadedItems = try await persistence.loadItems()
            try Task.checkCancellation()
            items = Self.sorted(loadedItems)
            loadState = .loaded
            refreshSelection()
        } catch is CancellationError {
            if loadState == .loading { loadState = .idle }
        } catch {
            loadState = .failed
            statusMessage = "Your productivity library couldn’t be loaded."
        }
    }

    func requestReload() {
        guard loadState != .loading else { return }
        loadState = .idle
        loadRequestID += 1
    }

    func select(_ id: UUID) {
        guard filteredItems.contains(where: { $0.id == id }) else { return }
        selectedID = id
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        guard editorMode == nil, pendingDeletionID == nil else { return }
        selectedID = LauncherListSelection.nextID(
            in: filteredItems,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        )
        statusMessage = nil
    }

    func beginCreating(kind: ProductivityLibraryItemKind = .snippet) {
        guard loadState == .loaded, isBusy == false else { return }
        draft = ProductivityLibraryDraft(kind: kind)
        editorMode = .creating
        showsActionsMenu = false
        statusMessage = nil
    }

    func beginEditingSelected() {
        guard let selectedItem, isBusy == false else { return }
        draft = ProductivityLibraryDraft(item: selectedItem)
        editorMode = .editing(selectedItem.id)
        showsActionsMenu = false
        statusMessage = nil
    }

    func cancelEditor() {
        guard isSaving == false else { return }
        editorMode = nil
        draft = ProductivityLibraryDraft()
        statusMessage = nil
    }

    func presentActions(for id: UUID) {
        select(id)
        showsActionsMenu = true
    }

    func requestDeleteSelected() {
        guard let selectedItem, isBusy == false else { return }
        pendingDeletionID = selectedItem.id
        showsActionsMenu = false
    }

    func cancelDelete() {
        pendingDeletionID = nil
    }

    func confirmDelete() {
        guard let id = pendingDeletionID, isBusy == false else { return }
        pendingDeletionID = nil
        let updatedItems = items.filter { $0.id != id }
        beginPersisting(
            updatedItems,
            selectedID: nil,
            successMessage: "Item deleted.",
            closesEditor: false
        )
    }

    func saveDraft() {
        guard let editorMode, isBusy == false else { return }
        let prepared: (title: String, content: String)
        do {
            prepared = try preparedDraft(draft)
        } catch let error as ProductivityLibraryValidationError {
            statusMessage = error.message
            return
        } catch {
            statusMessage = "This item can’t be saved."
            return
        }

        let timestamp = now()
        var updatedItems = items
        let savedID: UUID
        switch editorMode {
        case .creating:
            savedID = makeID()
            updatedItems.append(
                ProductivityLibraryItem(
                    id: savedID,
                    kind: draft.kind,
                    title: prepared.title,
                    content: prepared.content,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        case .editing(let id):
            guard let index = updatedItems.firstIndex(where: { $0.id == id }) else {
                statusMessage = "That item is no longer available."
                self.editorMode = nil
                return
            }
            savedID = id
            updatedItems[index].kind = draft.kind
            updatedItems[index].title = prepared.title
            updatedItems[index].content = prepared.content
            updatedItems[index].updatedAt = timestamp
        }
        beginPersisting(
            updatedItems,
            selectedID: savedID,
            successMessage: "Item saved.",
            closesEditor: true
        )
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case ProductivityLibraryActionID.useSelected:
            useSelectedItem()
        case ProductivityLibraryActionID.createItem:
            beginCreating()
        case ProductivityLibraryActionID.editSelected:
            beginEditingSelected()
        case ProductivityLibraryActionID.requestDelete:
            requestDeleteSelected()
        case ProductivityLibraryActionID.saveDraft:
            saveDraft()
        case ProductivityLibraryActionID.cancelEditor:
            cancelEditor()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        default:
            break
        }
    }

    func goBack() {
        if editorMode != nil {
            cancelEditor()
        } else {
            onGoBack()
        }
    }

    func handleEscape() -> Bool {
        if pendingDeletionID != nil {
            cancelDelete()
            return true
        }
        if showsActionsMenu {
            showsActionsMenu = false
            return true
        }
        if editorMode != nil {
            cancelEditor()
            return true
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func stop() {
        persistenceTask?.cancel()
        primaryActionTask?.cancel()
        showsActionsMenu = false
    }

    func flushPersistenceForTesting() async {
        await persistenceTask?.value
    }

    func flushPrimaryActionForTesting() async {
        await primaryActionTask?.value
    }

    private func refreshSelection() {
        selectedID = LauncherListSelection.resolvedID(
            in: filteredItems,
            selectedID: selectedID,
            id: \.id
        )
    }

    private func preparedDraft(
        _ draft: ProductivityLibraryDraft
    ) throws -> (title: String, content: String) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            throw ProductivityLibraryValidationError.missingTitle
        }
        guard draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ProductivityLibraryValidationError.missingContent
        }

        switch draft.kind {
        case .quicklink:
            let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try quicklinkValidator.validatedURL(from: content)
            return (title, content)
        case .emojiKeyword:
            return (title, draft.content.trimmingCharacters(in: .whitespacesAndNewlines))
        case .snippet, .quickNote:
            return (title, draft.content)
        }
    }

    private func beginPersisting(
        _ newItems: [ProductivityLibraryItem],
        selectedID: UUID?,
        successMessage: String,
        closesEditor: Bool
    ) {
        guard isBusy == false else { return }
        isSaving = true
        statusMessage = nil
        let sortedItems = Self.sorted(newItems)
        persistenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSaving = false }
            do {
                try await self.persistence.saveItems(sortedItems)
                try Task.checkCancellation()
                self.items = sortedItems
                self.query = ""
                self.filter = .all
                self.selectedID = selectedID ?? sortedItems.first?.id
                if closesEditor {
                    self.editorMode = nil
                    self.draft = ProductivityLibraryDraft()
                }
                self.statusMessage = successMessage
            } catch is CancellationError {
                return
            } catch {
                self.statusMessage = "Your changes couldn’t be saved."
            }
        }
    }

    private func useSelectedItem() {
        guard let selectedItem, isBusy == false else { return }
        isPerformingPrimaryAction = true
        statusMessage = nil
        showsActionsMenu = false
        primaryActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isPerformingPrimaryAction = false }
            do {
                switch selectedItem.kind {
                case .snippet:
                    var output = selectedItem.content
                    if output.contains("{{clipboard}}") {
                        let clipboardText = await self.pasteboard.readString() ?? ""
                        try Task.checkCancellation()
                        output = output.replacingOccurrences(
                            of: "{{clipboard}}",
                            with: clipboardText
                        )
                    }
                    try Task.checkCancellation()
                    await self.pasteboard.writeString(output)
                    try Task.checkCancellation()
                    self.statusMessage = "Snippet copied."
                case .quickNote:
                    await self.pasteboard.writeString(selectedItem.content)
                    try Task.checkCancellation()
                    self.statusMessage = "Note copied."
                case .emojiKeyword:
                    await self.pasteboard.writeString(selectedItem.content)
                    try Task.checkCancellation()
                    self.statusMessage = "Emoji copied."
                case .quicklink:
                    let url = try self.quicklinkValidator.validatedURL(
                        from: selectedItem.content
                    )
                    try Task.checkCancellation()
                    try await self.urlOpener.openURL(url)
                    try Task.checkCancellation()
                    self.onDismiss()
                }
            } catch is CancellationError {
                return
            } catch is ProductivityLibraryValidationError {
                self.statusMessage = "This Quicklink uses an invalid or unsafe URL."
            } catch {
                self.statusMessage = "That action couldn’t be completed."
            }
        }
    }

    private static func sorted(
        _ items: [ProductivityLibraryItem]
    ) -> [ProductivityLibraryItem] {
        items.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }
}
