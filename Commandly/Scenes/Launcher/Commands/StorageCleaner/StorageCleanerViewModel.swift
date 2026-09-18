import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated enum StorageCleanerActionID {
    static let refresh = CommandActionID(rawValue: "storage-cleaner.refresh")
    static let chooseDuplicateFolder = CommandActionID(
        rawValue: "storage-cleaner.choose-duplicate-folder"
    )
    static let toggleSelection = CommandActionID(rawValue: "storage-cleaner.toggle-selection")
    static let reviewCleanup = CommandActionID(rawValue: "storage-cleaner.review-cleanup")
    static let confirmCleanup = CommandActionID(rawValue: "storage-cleaner.confirm-cleanup")
    static let cancelCleanup = CommandActionID(rawValue: "storage-cleaner.cancel-cleanup")
    static let selectRecommended = CommandActionID(rawValue: "storage-cleaner.select-recommended")
    static let clearSelection = CommandActionID(rawValue: "storage-cleaner.clear-selection")
}

enum StorageCleanerCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case applicationLeftovers
    case caches
    case duplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Candidates"
        case .applicationLeftovers: return "App Leftovers"
        case .caches: return "Caches"
        case .duplicates: return "Exact Duplicates"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "internaldrive"
        case .applicationLeftovers: return "app.dashed"
        case .caches: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .duplicates: return "doc.on.doc"
        }
    }

    func contains(_ item: StorageCleanupItem) -> Bool {
        switch (self, item.category) {
        case (.all, _),
             (.applicationLeftovers, .applicationLeftover),
             (.caches, .cache),
             (.duplicates, .duplicate):
            return true
        default:
            return false
        }
    }
}

enum StorageCleanerEntryPoint: Sendable {
    case libraryReview
    case exactDuplicates
}

struct StorageCleanerConfirmation: Identifiable, Equatable {
    let id = UUID()
    let itemCount: Int
    let byteCount: Int64

    var message: String {
        let itemLabel = itemCount == 1 ? "item" : "items"
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return "Move \(itemCount) \(itemLabel) (\(size)) to the Trash? You can review or restore them there before emptying the Trash."
    }
}

@Observable
@MainActor
final class StorageCleanerViewModel {
    var query = "" {
        didSet { repairRowSelection() }
    }
    var category: StorageCleanerCategory = .all {
        didSet { repairRowSelection() }
    }
    var selectedRowPath: String?
    var selectedPaths: Set<String> = []
    var showsActionsMenu = false
    private(set) var items: [StorageCleanupItem] = []
    private(set) var isScanningLibrary = false
    private(set) var isScanningDuplicates = false
    private(set) var isCleaning = false
    private(set) var statusMessage: String?
    private(set) var duplicateScopeName: String?
    private(set) var pendingConfirmation: StorageCleanerConfirmation?

    @ObservationIgnored private let scanner: any StorageCleanupScanning
    @ObservationIgnored private let directoryChooser: any StorageCleanupDirectoryChoosing
    @ObservationIgnored private let trashManager: any ApplicationBundleManaging
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var libraryScanTask: Task<Void, Never>?
    @ObservationIgnored private var duplicateScanTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var libraryScanGeneration = 0
    @ObservationIgnored private var duplicateScanGeneration = 0
    @ObservationIgnored private var duplicateScopeURL: URL?
    @ObservationIgnored private var pendingInitialEntryPoint: StorageCleanerEntryPoint?

    init(
        scanner: any StorageCleanupScanning,
        directoryChooser: any StorageCleanupDirectoryChoosing,
        trashManager: any ApplicationBundleManaging,
        onGoBack: @escaping () -> Void,
        initialEntryPoint: StorageCleanerEntryPoint = .libraryReview
    ) {
        self.scanner = scanner
        self.directoryChooser = directoryChooser
        self.trashManager = trashManager
        self.onGoBack = onGoBack
        self.pendingInitialEntryPoint = initialEntryPoint
    }

    var filteredItems: [StorageCleanupItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard category.contains(item) else { return false }
            guard trimmedQuery.isEmpty == false else { return true }
            return item.name.localizedCaseInsensitiveContains(trimmedQuery)
                || item.containerPath.localizedCaseInsensitiveContains(trimmedQuery)
                || item.associatedBundleIdentifier?.localizedCaseInsensitiveContains(
                    trimmedQuery
                ) == true
        }
    }

    var selectedItems: [StorageCleanupItem] {
        items.filter { selectedPaths.contains($0.path) }
    }

    var selectedByteCount: Int64 {
        selectedItems.reduce(0) { $0 + $1.byteCount }
    }

    var selectedSummary: String {
        let count = selectedItems.count
        let itemsLabel = count == 1 ? "1 item" : "\(count) items"
        let byteLabel = ByteCountFormatter.string(
            fromByteCount: selectedByteCount,
            countStyle: .file
        )
        return "\(itemsLabel) • \(byteLabel)"
    }

    var visibleByteCount: Int64 {
        filteredItems.reduce(0) { $0 + $1.byteCount }
    }

    var isScanning: Bool {
        isScanningLibrary || isScanningDuplicates
    }

    var canReviewCleanup: Bool {
        selectedPaths.isEmpty == false && isScanning == false && isCleaning == false
    }

    var footerActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: StorageCleanerActionID.toggleSelection,
                title: "Toggle Selection",
                isPrimary: true,
                keyHint: .return,
                isEnabled: filteredItems.isEmpty == false && isCleaning == false
            ),
            CommandActionDescriptor(
                id: StorageCleanerActionID.reviewCleanup,
                title: "Review Cleanup…",
                keyHint: CommandKeyHint(symbols: ["⌘", "↩"]),
                isEnabled: canReviewCleanup
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isCleaning == false
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: StorageCleanerActionID.refresh,
                title: "Rescan App Leftovers and Caches",
                isEnabled: isScanning == false && isCleaning == false
            ),
            CommandActionDescriptor(
                id: StorageCleanerActionID.chooseDuplicateFolder,
                title: "Choose Folder for Duplicate Scan…",
                isEnabled: isScanning == false && isCleaning == false
            ),
            CommandActionDescriptor(
                id: StorageCleanerActionID.selectRecommended,
                title: "Select Recommended Items",
                isEnabled: items.isEmpty == false && isCleaning == false
            ),
            CommandActionDescriptor(
                id: StorageCleanerActionID.clearSelection,
                title: "Clear Selection",
                isEnabled: selectedPaths.isEmpty == false && isCleaning == false
            )
        ]
    }

    func start() {
        guard isScanning == false, isCleaning == false else { return }
        if let pendingInitialEntryPoint {
            self.pendingInitialEntryPoint = nil
            switch pendingInitialEntryPoint {
            case .libraryReview:
                scanLibrary()
            case .exactDuplicates:
                category = .duplicates
                chooseAndScanDuplicateFolder()
            }
            return
        }
        guard items.isEmpty else { return }
        scanLibrary()
    }

    func stop() {
        libraryScanGeneration += 1
        duplicateScanGeneration += 1
        libraryScanTask?.cancel()
        duplicateScanTask?.cancel()
        cleanupTask?.cancel()
        libraryScanTask = nil
        duplicateScanTask = nil
        cleanupTask = nil
        duplicateScopeURL = nil
        isScanningLibrary = false
        isScanningDuplicates = false
        isCleaning = false
    }

    func goBack() {
        stop()
        onGoBack()
    }

    func scanLibrary() {
        guard isScanningLibrary == false, isCleaning == false else { return }
        libraryScanGeneration += 1
        let generation = libraryScanGeneration
        libraryScanTask?.cancel()
        isScanningLibrary = true
        statusMessage = nil
        libraryScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await scanner.scanLibrary()
                guard Task.isCancelled == false, libraryScanGeneration == generation else {
                    return
                }
                let duplicates = items.filter { $0.category == .duplicate }
                items = Self.sorted(result.items + duplicates)
                let duplicateSelections = selectedPaths.filter { path in
                    duplicates.contains { $0.path == path }
                }
                selectedPaths = Set(
                    result.items.filter(\.isSuggestedForRemoval).map(\.path)
                )
                .union(duplicateSelections)
                repairRowSelection()
                statusMessage = Self.scanStatus(
                    result: result,
                    label: "App leftovers and caches"
                )
            } catch is CancellationError {
                return
            } catch {
                guard libraryScanGeneration == generation else { return }
                statusMessage = error.localizedDescription
            }
            if libraryScanGeneration == generation {
                isScanningLibrary = false
            }
        }
    }

    func chooseAndScanDuplicateFolder() {
        guard isScanning == false, isCleaning == false else { return }
        duplicateScanTask?.cancel()
        duplicateScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let directory = await directoryChooser.chooseDuplicateScanDirectory() else {
                return
            }
            duplicateScanGeneration += 1
            let generation = duplicateScanGeneration
            isScanningDuplicates = true
            statusMessage = nil
            duplicateScopeName = directory.lastPathComponent
            duplicateScopeURL = directory
            do {
                let result = try await scanner.scanDuplicates(in: directory)
                guard Task.isCancelled == false, duplicateScanGeneration == generation else {
                    return
                }
                let nonDuplicates = items.filter { $0.category != .duplicate }
                items = Self.sorted(nonDuplicates + result.items)
                selectedPaths = selectedPaths.filter { path in
                    nonDuplicates.contains { $0.path == path }
                }
                .union(result.items.filter(\.isSuggestedForRemoval).map(\.path))
                category = .duplicates
                repairRowSelection()
                statusMessage = Self.scanStatus(
                    result: result,
                    label: "Exact duplicate scan"
                )
            } catch is CancellationError {
                return
            } catch {
                guard duplicateScanGeneration == generation else { return }
                statusMessage = error.localizedDescription
            }
            if duplicateScanGeneration == generation {
                isScanningDuplicates = false
            }
        }
    }

    func setCategory(_ category: StorageCleanerCategory) {
        self.category = category
    }

    func selectRow(_ item: StorageCleanupItem) {
        selectedRowPath = item.path
    }

    func toggleSelection(of item: StorageCleanupItem) {
        selectedRowPath = item.path
        if selectedPaths.contains(item.path) {
            selectedPaths.remove(item.path)
            return
        }
        if let groupID = item.duplicateGroupID {
            let group = duplicateGroup(groupID)
            let unselected = group.filter { selectedPaths.contains($0.path) == false }
            if unselected.count <= 1,
               let replacementKeep = group.first(where: {
                   $0.path != item.path && selectedPaths.contains($0.path)
               }) {
                selectedPaths.remove(replacementKeep.path)
                statusMessage = "Keeping \(replacementKeep.name) so one copy remains."
            }
        }
        selectedPaths.insert(item.path)
    }

    func selectAllVisible() {
        selectedPaths.formUnion(filteredItems.map(\.path))
        let duplicateGroupIDs = Set(
            items.compactMap(\.duplicateGroupID)
        )
        for groupID in duplicateGroupIDs {
            let group = duplicateGroup(groupID)
            if group.allSatisfy({ selectedPaths.contains($0.path) }),
               let keep = group.first {
                selectedPaths.remove(keep.path)
            }
        }
    }

    func clearVisibleSelection() {
        selectedPaths.subtract(filteredItems.map(\.path))
    }

    func selectRecommended() {
        selectedPaths = Set(items.filter(\.isSuggestedForRemoval).map(\.path))
    }

    func moveSelection(offset: Int) {
        selectedRowPath = LauncherListSelection.nextID(
            in: filteredItems,
            selectedID: selectedRowPath,
            offset: offset,
            id: \.path
        )
    }

    func toggleSelectedRow() {
        guard let selectedRow = filteredItems.first(where: {
            $0.path == selectedRowPath
        }) ?? filteredItems.first else { return }
        toggleSelection(of: selectedRow)
    }

    func requestCleanupConfirmation() {
        guard canReviewCleanup else { return }
        pendingConfirmation = StorageCleanerConfirmation(
            itemCount: selectedItems.count,
            byteCount: selectedByteCount
        )
    }

    func cancelCleanupConfirmation() {
        pendingConfirmation = nil
    }

    func confirmCleanup() {
        guard pendingConfirmation != nil, canReviewCleanup else { return }
        pendingConfirmation = nil
        isCleaning = true
        statusMessage = nil
        let candidates = selectedItems.sorted {
            $0.path.count > $1.path.count
        }
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let selectedDuplicateScope = candidates.contains {
                $0.category == .duplicate
            } ? duplicateScopeURL : nil
            let didStartDuplicateAccess =
                selectedDuplicateScope?.startAccessingSecurityScopedResource() == true
            defer {
                if didStartDuplicateAccess {
                    selectedDuplicateScope?.stopAccessingSecurityScopedResource()
                }
            }
            var succeededPaths: Set<String> = []
            var failureCount = 0
            for candidate in candidates {
                if Task.isCancelled { break }
                do {
                    try await trashManager.moveItemToTrash(atPath: candidate.path)
                    succeededPaths.insert(candidate.path)
                } catch {
                    failureCount += 1
                }
            }
            selectedPaths.subtract(succeededPaths)
            items.removeAll { succeededPaths.contains($0.path) }
            pruneResolvedDuplicateGroups()
            repairRowSelection()
            isCleaning = false

            if Task.isCancelled {
                statusMessage = "Cleanup stopped. Items already moved remain in the Trash."
            } else if failureCount == 0 {
                let count = succeededPaths.count
                statusMessage = count == 1
                    ? "Moved 1 item to the Trash."
                    : "Moved \(count) items to the Trash."
            } else if succeededPaths.isEmpty {
                statusMessage = "Nothing was moved. Check folder access and try again."
            } else {
                statusMessage = "Moved \(succeededPaths.count) items. \(failureCount) couldn’t be moved to the Trash."
            }
        }
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case StorageCleanerActionID.refresh:
            scanLibrary()
        case StorageCleanerActionID.chooseDuplicateFolder:
            chooseAndScanDuplicateFolder()
        case StorageCleanerActionID.toggleSelection:
            toggleSelectedRow()
        case StorageCleanerActionID.reviewCleanup:
            requestCleanupConfirmation()
        case StorageCleanerActionID.confirmCleanup:
            confirmCleanup()
        case StorageCleanerActionID.cancelCleanup:
            cancelCleanupConfirmation()
        case StorageCleanerActionID.selectRecommended:
            selectRecommended()
        case StorageCleanerActionID.clearSelection:
            selectedPaths.removeAll()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            goBack()
        default:
            break
        }
    }

    func handleEscape() -> Bool {
        if pendingConfirmation != nil {
            pendingConfirmation = nil
            return true
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func itemCount(in category: StorageCleanerCategory) -> Int {
        items.filter(category.contains).count
    }

    func byteCount(in category: StorageCleanerCategory) -> Int64 {
        items.filter(category.contains).reduce(0) { $0 + $1.byteCount }
    }

    func waitForCurrentOperationsForTesting() async {
        await libraryScanTask?.value
        await duplicateScanTask?.value
        await cleanupTask?.value
    }

    private func duplicateGroup(_ groupID: String) -> [StorageCleanupItem] {
        items.filter { $0.duplicateGroupID == groupID }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func repairRowSelection() {
        selectedRowPath = LauncherListSelection.resolvedID(
            in: filteredItems,
            selectedID: selectedRowPath,
            id: \.path
        )
    }

    private func pruneResolvedDuplicateGroups() {
        let groupIDs = Set(items.compactMap(\.duplicateGroupID))
        for groupID in groupIDs {
            let groupPaths = items.filter { $0.duplicateGroupID == groupID }.map(\.path)
            if groupPaths.count < 2 {
                selectedPaths.subtract(groupPaths)
                items.removeAll { $0.duplicateGroupID == groupID }
            }
        }
    }

    private static func sorted(_ items: [StorageCleanupItem]) -> [StorageCleanupItem] {
        items.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            if $0.byteCount != $1.byteCount {
                return $0.byteCount > $1.byteCount
            }
            return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private static func scanStatus(
        result: StorageCleanupScanResult,
        label: String
    ) -> String {
        if result.isPartial {
            return "\(label) finished with limits or inaccessible items. Review the results shown."
        }
        let count = result.items.count
        return count == 1 ? "\(label) found 1 candidate." : "\(label) found \(count) candidates."
    }
}
