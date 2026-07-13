import AppCore
import Foundation
import Infrastructure
import Observation

/// Main-actor state and behavior for one temporary floating Shelf board.
@Observable
@MainActor
final class ShelfBoardModel {
    let entryMode: ShelfEntryMode
    let configuration: ShelfConfiguration

    private(set) var items: [ShelfItem] = []
    private(set) var selectedItemIDs: Set<ShelfItem.ID> = []
    private(set) var openWithOptions: [FileActionOption] = []
    private(set) var sharingOptions: [FileActionOption] = []
    private(set) var isLoadingActionOptions = false
    private(set) var isPerformingAction = false
    var isShowingDetails = false
    var statusMessage: String?
    var errorMessage: String?

    private let services: ShelfApplicationServices
    private let onClose: () -> Void
    private var metadataTasks: [ShelfItem.ID: Task<Void, Never>] = [:]
    private var scopedURLs: Set<URL> = []
    private var didLoadInitialContent = false
    private var isTornDown = false
    private var didRequestClose = false

    init(
        entryMode: ShelfEntryMode,
        configuration: ShelfConfiguration = .default,
        services: ShelfApplicationServices,
        onClose: @escaping () -> Void
    ) {
        self.entryMode = entryMode
        self.configuration = configuration
        self.services = services
        self.onClose = onClose
    }

    var accessibilityLabel: String {
        switch entryMode {
        case .empty:
            return "Shelf"
        case .fromClipboard:
            return "Shelf from Clipboard"
        }
    }

    var accessibilityValue: String {
        items.isEmpty ? "Empty" : itemCountDescription
    }

    var itemCountDescription: String {
        Self.countDescription(for: items)
    }

    var actionItems: [ShelfItem] {
        guard selectedItemIDs.isEmpty == false else { return items }
        return items.filter { selectedItemIDs.contains($0.id) }
    }

    var actionURLs: [URL] {
        actionItems.map(\.url)
    }

    var selectionSummary: String {
        if selectedItemIDs.isEmpty {
            return "All \(itemCountDescription)"
        }
        return "\(Self.countDescription(for: actionItems)) selected"
    }

    private static func countDescription(for items: [ShelfItem]) -> String {
        guard let firstKind = items.first?.kind else { return "0 items" }
        let isHomogeneous = items.dropFirst().allSatisfy { $0.kind == firstKind }
        let kind = isHomogeneous ? firstKind : .file
        if isHomogeneous {
            return kind.countDescription(items.count)
        }
        return "\(items.count) items"
    }
}

// MARK: - Staging and selection

extension ShelfBoardModel {
    func loadInitialContent() async {
        guard didLoadInitialContent == false else { return }
        didLoadInitialContent = true
        if entryMode == .fromClipboard {
            await addFromClipboard()
        }
    }

    @discardableResult
    func stage(_ urls: [URL]) -> Int {
        guard isTornDown == false else { return 0 }
        let existingIDs = Set(items.map(\.id))
        var seen = existingIDs
        let accepted = urls.compactMap { candidate -> ShelfItem? in
            guard candidate.isFileURL else { return nil }
            let item = ShelfItem(url: candidate)
            guard seen.insert(item.id).inserted else { return nil }
            return item
        }

        guard accepted.isEmpty == false else {
            statusMessage = items.isEmpty ? "Drop files or folders here." : "Those items are already on this Shelf."
            return 0
        }

        accepted.forEach { retainAccess(for: $0.url) }
        items.append(contentsOf: accepted)
        statusMessage = accepted.count == 1
            ? "Added \(accepted[0].displayName)."
            : "Added \(accepted.count) items."
        errorMessage = nil

        if configuration.playDropSound {
            services.dropFeedback.playDropAccepted()
        }
        loadMetadata(for: accepted)
        return accepted.count
    }

    func addFromClipboard() async {
        let urls = await services.pasteboard.readFileURLs()
        guard urls.isEmpty == false else {
            statusMessage = "The clipboard does not contain files or folders."
            return
        }
        _ = stage(urls)
    }

    func copyItemsToClipboard() async {
        let urls = actionURLs
        guard urls.isEmpty == false else {
            statusMessage = "There are no Shelf items to copy."
            return
        }
        await services.pasteboard.writeFileURLs(urls)
        statusMessage = urls.count == 1 ? "Item copied." : "\(urls.count) items copied."
        errorMessage = nil
    }

    func copyPathsToClipboard() async {
        let urls = actionURLs
        guard urls.isEmpty == false else {
            statusMessage = "There are no Shelf item paths to copy."
            return
        }
        await services.pasteboard.writeString(urls.map(\.path).joined(separator: "\n"))
        statusMessage = urls.count == 1 ? "Path copied." : "\(urls.count) paths copied."
        errorMessage = nil
    }

    func toggleSelection(_ id: ShelfItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    func selectOnly(_ id: ShelfItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedItemIDs = [id]
    }

    func selectAll() {
        selectedItemIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func dragPayload(for ids: [ShelfItem.ID]) -> [ShelfItem] {
        let requested = Set(ids)
        return items.filter { requested.contains($0.id) }
    }

    func completeDragOut(itemIDs: [ShelfItem.ID], removesReferences: Bool) {
        guard removesReferences else { return }
        remove(itemIDs: Set(itemIDs), status: nil)
    }

    func remove(_ id: ShelfItem.ID) {
        remove(itemIDs: [id], status: "Removed from Shelf.")
    }

    func removeSelectedFromShelf() {
        let ids = Set(actionItems.map(\.id))
        guard ids.isEmpty == false else { return }
        remove(
            itemIDs: ids,
            status: ids.count == 1 ? "Removed from Shelf." : "Removed \(ids.count) items from Shelf."
        )
    }

    func clear() {
        guard items.isEmpty == false else { return }
        remove(itemIDs: Set(items.map(\.id)), status: "Shelf cleared.")
    }
}

// MARK: - File and sharing actions

extension ShelfBoardModel {
    func openSelected() async {
        let urls = actionURLs
        guard urls.isEmpty == false else { return }
        await runAction(success: nil) { [services] in
            for url in urls {
                try Task.checkCancellation()
                try await services.urlOpener.openURL(url)
            }
        }
    }

    func revealSelected() async {
        let urls = actionURLs
        guard urls.isEmpty == false else { return }
        await runAction(success: "Shown in Finder.") { [services] in
            try await services.fileRevealer.revealInFinder(urls: urls)
        }
    }

    func previewSelected(startingWith itemID: ShelfItem.ID? = nil) {
        let previewItems = actionItems
        guard previewItems.isEmpty == false else { return }
        let index = itemID.flatMap { requestedID in
            previewItems.firstIndex { $0.id == requestedID }
        } ?? 0
        services.previewPresenter.preview(
            urls: previewItems.map(\.url),
            selectedIndex: index
        )
        statusMessage = nil
        errorMessage = nil
    }

    func canShare(_ urls: [URL]? = nil, to destination: NativeShareDestination) -> Bool {
        let candidateURLs = urls ?? actionURLs
        return candidateURLs.isEmpty == false
            && services.fileActions.canShare(candidateURLs, to: destination)
    }

    func share(_ urls: [URL]? = nil, to destination: NativeShareDestination) async {
        let candidateURLs = urls ?? actionURLs
        guard candidateURLs.isEmpty == false else { return }
        if urls != nil {
            candidateURLs.forEach { retainAccess(for: $0) }
        }
        await runAction(success: "Opened \(destination.shelfTitle) sharing.") { [services] in
            try services.fileActions.share(candidateURLs, to: destination)
        }
    }

    func refreshOpenWithOptions() async {
        let urls = actionURLs
        guard urls.isEmpty == false else {
            openWithOptions = []
            return
        }
        isLoadingActionOptions = true
        openWithOptions = await services.fileActions.applications(toOpen: urls)
        isLoadingActionOptions = false
    }

    func openSelected(withApplication optionID: String) async {
        let urls = actionURLs
        guard urls.isEmpty == false else { return }
        await runAction(success: nil) { [services] in
            try await services.fileActions.open(urls, withApplication: optionID)
        }
    }

    func refreshSharingOptions() async {
        let urls = actionURLs
        guard urls.isEmpty == false else {
            sharingOptions = []
            return
        }
        isLoadingActionOptions = true
        sharingOptions = await services.fileActions.sharingServices(for: urls)
        isLoadingActionOptions = false
    }

    func shareSelected(withService optionID: String) async {
        let urls = actionURLs
        guard urls.isEmpty == false else { return }
        await runAction(success: "Opened sharing service.") { [services] in
            try services.fileActions.share(urls, withService: optionID)
        }
    }

    func duplicateSelected() async {
        let urls = actionURLs
        guard urls.isEmpty == false else { return }
        var outputs: [URL] = []
        await runAction(success: urls.count == 1 ? "Duplicate created." : "Duplicates created.") { [services] in
            outputs = try await services.fileActions.duplicate(urls)
        }
        if outputs.isEmpty == false {
            _ = stage(outputs)
        }
    }

    func copySelectedToChosenFolder() async {
        let urls = actionURLs
        guard urls.isEmpty == false,
              let destination = await services.fileActions.chooseDestination(title: "Copy Shelf Items") else {
            return
        }
        var outputs: [URL] = []
        await runAction(success: "Copied to the selected folder.") { [services] in
            outputs = try await services.fileActions.copy(urls, to: destination)
        }
        if outputs.isEmpty == false {
            _ = stage(outputs)
        }
    }

    func moveSelectedToChosenFolder() async {
        let sourceItems = actionItems
        guard sourceItems.isEmpty == false,
              let destination = await services.fileActions.chooseDestination(title: "Move Shelf Items") else {
            return
        }
        var outputs: [URL] = []
        await runAction(success: "Moved to the selected folder.") { [services] in
            outputs = try await services.fileActions.move(sourceItems.map(\.url), to: destination)
        }
        guard outputs.count == sourceItems.count else { return }
        replace(sourceItems, with: outputs)
    }

    func rename(_ itemID: ShelfItem.ID, to proposedName: String) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidFileName(name) else {
            errorMessage = "Enter a valid file or folder name."
            return
        }
        var output: URL?
        await runAction(success: "Renamed.") { [services] in
            output = try await services.fileActions.rename(item.url, to: name)
        }
        if let output {
            replace([item], with: [output])
        }
    }

    func moveSelectedToTrash() async {
        let selectedItems = actionItems
        guard selectedItems.isEmpty == false else { return }
        var didMove = false
        await runAction(success: selectedItems.count == 1 ? "Moved to Trash." : "Moved items to Trash.") { [services] in
            try await services.fileActions.moveToTrash(selectedItems.map(\.url))
            didMove = true
        }
        if didMove {
            remove(itemIDs: Set(selectedItems.map(\.id)), status: nil)
        }
    }
}

// MARK: - Lifecycle and internal state

extension ShelfBoardModel {
    func dismissError() {
        errorMessage = nil
    }

    func close() {
        guard didRequestClose == false else { return }
        didRequestClose = true
        tearDown()
        onClose()
    }

    func tearDown() {
        guard isTornDown == false else { return }
        isTornDown = true
        for task in metadataTasks.values {
            task.cancel()
        }
        metadataTasks.removeAll()
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }

    private func loadMetadata(for stagedItems: [ShelfItem]) {
        for item in stagedItems {
            let reader = services.metadataReader
            metadataTasks[item.id]?.cancel()
            metadataTasks[item.id] = Task { [weak self] in
                defer { self?.metadataTasks[item.id] = nil }
                do {
                    let metadata = try await reader.metadata(for: [item.url])
                    try Task.checkCancellation()
                    guard let value = metadata.first else {
                        self?.markUnavailable(item.id)
                        return
                    }
                    self?.apply(value, to: item.id)
                } catch is CancellationError {
                    return
                } catch {
                    self?.markUnavailable(item.id)
                }
            }
        }
    }

    private func apply(_ metadata: FileResourceMetadata, to itemID: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].displayName = metadata.displayName
        items[index].isDirectory = metadata.isDirectory
        items[index].byteCount = metadata.byteCount
        items[index].contentTypeIdentifier = metadata.contentTypeIdentifier
        items[index].isAvailable = true
    }

    private func markUnavailable(_ itemID: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isAvailable = false
        statusMessage = "One Shelf item is no longer available."
    }

    private func replace(_ sourceItems: [ShelfItem], with outputURLs: [URL]) {
        let replacements = Dictionary(
            uniqueKeysWithValues: zip(sourceItems, outputURLs).map { ($0.id, $1) }
        )
        let originalSelection = selectedItemIDs
        for source in sourceItems {
            releaseAccess(for: source.url)
            metadataTasks[source.id]?.cancel()
            metadataTasks[source.id] = nil
        }

        var replacementItems: [ShelfItem] = []
        items = items.compactMap { item in
            guard let replacementURL = replacements[item.id] else { return item }
            let replacement = ShelfItem(url: replacementURL)
            replacementItems.append(replacement)
            return replacement
        }
        selectedItemIDs = Set(replacementItems.compactMap { replacement in
            sourceItems.contains { source in
                originalSelection.contains(source.id)
                    && replacements[source.id] == replacement.url
            } ? replacement.id : nil
        })
        replacementItems.forEach { retainAccess(for: $0.url) }
        loadMetadata(for: replacementItems)
    }

    private func remove(itemIDs: Set<ShelfItem.ID>, status: String?) {
        guard itemIDs.isEmpty == false else { return }
        let hadItems = items.isEmpty == false
        let removedItems = items.filter { itemIDs.contains($0.id) }
        guard removedItems.isEmpty == false else { return }

        for item in removedItems {
            metadataTasks[item.id]?.cancel()
            metadataTasks[item.id] = nil
            releaseAccess(for: item.url)
        }
        items.removeAll { itemIDs.contains($0.id) }
        selectedItemIDs.subtract(itemIDs)
        if let status {
            statusMessage = status
        }
        if items.isEmpty {
            isShowingDetails = false
            if hadItems, configuration.clearWhenEmpty {
                close()
            }
        }
    }

    private func releaseAccess(for url: URL) {
        guard scopedURLs.remove(url) != nil else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func retainAccess(for url: URL) {
        guard scopedURLs.contains(url) == false else { return }
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.insert(url)
        }
    }

    private func runAction(
        success: String?,
        operation: () async throws -> Void
    ) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await operation()
            statusMessage = success
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private static func isValidFileName(_ name: String) -> Bool {
        name.isEmpty == false
            && name != "."
            && name != ".."
            && name.contains("/") == false
            && name.contains("\0") == false
    }

    private static func userFacingMessage(for error: Error) -> String {
        guard let commandlyError = error as? CommandlyError else {
            return "The Shelf action could not be completed."
        }
        switch commandlyError {
        case .notFound(let message),
             .invalidInput(let message),
             .unsupported(let message),
             .persistence(let message),
             .security(let message),
             .internalFailure(let message):
            return message
        }
    }
}
