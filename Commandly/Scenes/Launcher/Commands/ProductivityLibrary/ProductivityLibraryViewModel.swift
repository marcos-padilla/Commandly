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
    var tags: String

    init(
        kind: ProductivityLibraryItemKind = .snippet,
        title: String = "",
        content: String = "",
        tags: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.content = content
        self.tags = tags
    }

    init(item: ProductivityLibraryItem) {
        self.init(kind: item.kind, title: item.title, content: item.content, tags: item.tags.joined(separator: ", "))
    }
}

enum ProductivityLibraryActionID {
    static let useSelected = CommandActionID(rawValue: "productivity-library.use")
    static let createItem = CommandActionID(rawValue: "productivity-library.create")
    static let editSelected = CommandActionID(rawValue: "productivity-library.edit")
    static let requestDelete = CommandActionID(rawValue: "productivity-library.delete")
    static let saveDraft = CommandActionID(rawValue: "productivity-library.save")
    static let cancelEditor = CommandActionID(rawValue: "productivity-library.cancel-editor")
    static let openFloatingNote = CommandActionID(rawValue: "productivity-library.open-floating-note")
}

@Observable
@MainActor
final class ProductivityLibraryViewModel: LauncherApplicationModel {
    @ObservationIgnored private let floatingNotes: (any FloatingNotePresenting)?
    @ObservationIgnored private var loadedFloatingRevision = 0
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
    @ObservationIgnored
    private var pendingInitialCreateKind: ProductivityLibraryItemKind?
    @ObservationIgnored private var editorBaseItem: ProductivityLibraryItem?
    @ObservationIgnored private var pendingDeletionBaseItem: ProductivityLibraryItem?

    private(set) var items: [ProductivityLibraryItem] = []
    private(set) var selectedID: UUID?
    private(set) var loadState: ProductivityLibraryLoadState = .idle
    private(set) var statusMessage: String?
    private(set) var isSaving = false
    private(set) var hasPersistenceConflict = false
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
    private(set) var pendingSnippet: ProductivityLibraryItem?
    private(set) var snippetFields: [String] = []
    var snippetInputs: [String: String] = [:]
    var selectedTag: String? {
        didSet { refreshSelection() }
    }

    init(
        services: ProductivityLibraryApplicationServices,
        onGoBack: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        initialCreateKind: ProductivityLibraryItemKind? = nil
    ) {
        self.persistence = services.persistence
        self.floatingNotes = services.floatingNotes
        self.pasteboard = services.pasteboard
        self.urlOpener = services.urlOpener
        self.quicklinkValidator = services.quicklinkValidator
        self.now = services.now
        self.makeID = services.makeID
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
        self.pendingInitialCreateKind = initialCreateKind
    }

    var filteredItems: [ProductivityLibraryItem] {
        let activeKind = filter.kind
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard activeKind == nil || item.kind == activeKind else { return false }
            guard selectedTag == nil || item.tags.contains(where: {
                $0.localizedCaseInsensitiveCompare(selectedTag ?? "") == .orderedSame
            }) else { return false }
            guard needle.isEmpty == false else { return true }
            return item.title.localizedCaseInsensitiveContains(needle)
                || item.content.localizedCaseInsensitiveContains(needle)
                || item.kind.title.localizedCaseInsensitiveContains(needle)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    var availableTags: [String] {
        ProductivityLibraryTags.normalized(items.flatMap(\.tags), limit: Int.max)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var canCopyPreparedSnippet: Bool {
        pendingSnippet != nil && !isBusy
            && snippetFields.allSatisfy { snippetInputs[$0]?.isEmpty == false }
    }

    func cancelSnippetInput() {
        if pendingSnippet != nil { primaryActionTask?.cancel() }
        clearSnippetInput()
    }

    private func clearSnippetInput() {
        pendingSnippet = nil
        snippetFields = []
        snippetInputs = [:]
    }

    func copyPreparedSnippet() {
        guard canCopyPreparedSnippet, let item = pendingSnippet else { return }
        let inputs = snippetInputs
        executePrimaryAction(item, inputs: inputs)
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
        } catch let error as SnippetTemplate.Failure {
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
        var actions = [
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
        if selectedItem.kind == .quickNote, floatingNotes != nil {
            actions.insert(CommandActionDescriptor(
                id: ProductivityLibraryActionID.openFloatingNote,
                title: "Open Floating Note", isEnabled: isBusy == false
            ), at: 1)
        }
        return actions
    }

    var floatingNoteRevision: Int { floatingNotes?.savedRevision ?? 0 }
    var canCreateFloatingNote: Bool { floatingNotes != nil && !isBusy }
    var canOpenFloatingNote: Bool { floatingNotes != nil && selectedItem?.kind == .quickNote && !isBusy }
    var canRefreshFromFloatingNotes: Bool {
        loadState == .loaded && editorMode == nil && !isBusy
            && pendingDeletionID == nil && pendingSnippet == nil
    }

    func refreshForFloatingNoteChanges() {
        guard canRefreshFromFloatingNotes, loadedFloatingRevision != floatingNoteRevision else { return }
        requestReload()
    }

    func openSelectedFloatingNote() {
        guard canOpenFloatingNote, let item = selectedItem, let floatingNotes else { return }
        showsActionsMenu = false
        onDismiss()
        floatingNotes.openNote(item)
    }

    func createFloatingNote() {
        guard canCreateFloatingNote, let floatingNotes else { return }
        onDismiss()
        floatingNotes.newNote()
    }

    func load(force: Bool = false) async {
        guard force || loadState == .idle || loadState == .failed else { return }
        let noteRevision = floatingNoteRevision
        loadState = .loading
        statusMessage = nil
        do {
            let loadedItems = try await persistence.loadItems()
            try Task.checkCancellation()
            items = Self.sorted(loadedItems)
            loadedFloatingRevision = noteRevision
            loadState = .loaded
            refreshSelection()
            if let pendingInitialCreateKind {
                self.pendingInitialCreateKind = nil
                beginCreating(kind: pendingInitialCreateKind)
            }
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
        editorBaseItem = nil
        hasPersistenceConflict = false
        editorMode = .creating
        showsActionsMenu = false
        statusMessage = nil
    }

    func beginEditingSelected() {
        guard let selectedItem, isBusy == false else { return }
        draft = ProductivityLibraryDraft(item: selectedItem)
        editorBaseItem = selectedItem
        hasPersistenceConflict = false
        editorMode = .editing(selectedItem.id)
        showsActionsMenu = false
        statusMessage = nil
    }

    func cancelEditor() {
        guard isSaving == false else { return }
        editorMode = nil
        editorBaseItem = nil
        hasPersistenceConflict = false
        draft = ProductivityLibraryDraft()
        statusMessage = nil
    }

    /// Explicit conflict recovery preserves the current draft under a new item identity.
    func saveDraftAsNew() {
        guard hasPersistenceConflict, editorMode != nil, isBusy == false else { return }
        editorMode = .creating
        editorBaseItem = nil
        saveDraft()
    }

    func presentActions(for id: UUID) {
        select(id)
        showsActionsMenu = true
    }

    func requestDeleteSelected() {
        guard let selectedItem, isBusy == false else { return }
        pendingDeletionID = selectedItem.id
        pendingDeletionBaseItem = selectedItem
        showsActionsMenu = false
    }

    func cancelDelete() {
        pendingDeletionID = nil
        pendingDeletionBaseItem = nil
    }

    func confirmDelete() {
        guard pendingDeletionID != nil, let expected = pendingDeletionBaseItem, isBusy == false else { return }
        cancelDelete()
        beginPersisting(
            [.delete(expected: expected)],
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
        } catch let error as SnippetTemplate.Failure {
            statusMessage = error.message
            return
        } catch {
            statusMessage = "This item can’t be saved."
            return
        }

        let timestamp = now()
        let mutation: ProductivityLibraryMutation
        let savedID: UUID
        switch editorMode {
        case .creating:
            savedID = makeID()
            mutation = .create(ProductivityLibraryItem(
                id: savedID, kind: draft.kind, title: prepared.title, content: prepared.content,
                createdAt: timestamp, updatedAt: timestamp, tags: ProductivityLibraryTags.parse(draft.tags)
            ))
        case .editing(let id):
            guard let expected = editorBaseItem, expected.id == id else {
                statusMessage = "That item is no longer available. Your draft is still here."
                hasPersistenceConflict = true
                return
            }
            savedID = id
            var updated = expected
            updated.kind = draft.kind
            updated.title = prepared.title
            updated.content = prepared.content
            updated.updatedAt = timestamp
            updated.tags = ProductivityLibraryTags.parse(draft.tags)
            mutation = .replace(updated, expected: expected)
        }
        beginPersisting(
            [mutation], selectedID: savedID, successMessage: "Item saved.", closesEditor: true
        )
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case ProductivityLibraryActionID.openFloatingNote:
            openSelectedFloatingNote()
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
        if pendingSnippet != nil {
            cancelSnippetInput()
            return true
        }
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
        cancelSnippetInput()
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
        case .snippet:
            _ = try SnippetTemplate(draft.content)
            return (title, draft.content)
        case .quickNote:
            return (title, draft.content)
        }
    }

    private func beginPersisting(
        _ changes: [ProductivityLibraryMutation],
        selectedID: UUID?,
        successMessage: String,
        closesEditor: Bool
    ) {
        guard isBusy == false else { return }
        isSaving = true
        statusMessage = nil
        hasPersistenceConflict = false
        persistenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSaving = false }
            do {
                let savedItems = try await self.persistence.applyChanges(changes)
                try Task.checkCancellation()
                let sortedItems = Self.sorted(savedItems)
                self.items = sortedItems
                self.query = ""
                self.filter = .all
                self.selectedTag = nil
                self.selectedID = selectedID ?? sortedItems.first?.id
                if closesEditor {
                    self.editorMode = nil
                    self.editorBaseItem = nil
                    self.draft = ProductivityLibraryDraft()
                }
                self.statusMessage = successMessage
            } catch is CancellationError {
                return
            } catch ProductivityLibraryPersistenceError.conflict {
                self.hasPersistenceConflict = true
                self.statusMessage = self.editorMode == nil
                    ? "This item changed in another window. Reload the library before deleting it."
                    : "This item changed in another window. Your draft is intact; save it as a new item to keep both versions."
            } catch {
                self.statusMessage = "Your changes couldn’t be saved."
            }
        }
    }

    private func useSelectedItem() {
        guard let selectedItem, isBusy == false else { return }
        if selectedItem.kind == .snippet {
            do {
                let template = try SnippetTemplate(selectedItem.content)
                if !template.fields.isEmpty {
                    pendingSnippet = selectedItem
                    snippetFields = template.fields
                    snippetInputs = [:]
                    statusMessage = nil
                    showsActionsMenu = false
                    return
                }
            } catch let error as SnippetTemplate.Failure {
                statusMessage = error.message
                return
            } catch {
                statusMessage = "This snippet couldn’t be prepared."
                return
            }
        }
        executePrimaryAction(selectedItem)
    }

    private func executePrimaryAction(_ selectedItem: ProductivityLibraryItem, inputs: [String: String] = [:]) {
        isPerformingPrimaryAction = true
        statusMessage = nil
        showsActionsMenu = false
        primaryActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isPerformingPrimaryAction = false }
            do {
                switch selectedItem.kind {
                case .snippet:
                    let template = try SnippetTemplate(selectedItem.content)
                    let clipboardText = template.needsClipboard ? await self.pasteboard.readString() ?? "" : ""
                    try Task.checkCancellation()
                    let output = try template.expanded(
                        clipboard: clipboardText, date: self.now(), uuid: self.makeID(), inputs: inputs
                    )
                    try Task.checkCancellation()
                    await self.pasteboard.writeString(output)
                    try Task.checkCancellation()
                    self.clearSnippetInput()
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
            } catch let error as SnippetTemplate.Failure {
                self.statusMessage = error.message
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
