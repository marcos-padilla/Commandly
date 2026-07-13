import CommandKit
import Foundation
import Infrastructure
import Observation

enum DownloadsActionID {
    static let refresh = CommandActionID(rawValue: "downloads.refresh")
    static let openNewest = CommandActionID(rawValue: "downloads.open-newest")
    static let copyNewest = CommandActionID(rawValue: "downloads.copy-newest")
}

enum DownloadsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(RecentDownloadsError)
}

private enum DownloadOperation: Sendable {
    case open(URL)
    case reveal(URL)
    case copy(URL)
}

@Observable
@MainActor
final class DownloadsViewModel {
    @ObservationIgnored private let provider: any RecentDownloadsProviding
    @ObservationIgnored private let urlOpener: any URLOpening
    @ObservationIgnored private let fileRevealer: any FileRevealing
    @ObservationIgnored private let pasteboard: any PasteboardAccessing
    @ObservationIgnored private let resultLimit: Int
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onDismiss: () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var operationGeneration = 0

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            resolveSelection()
        }
    }
    private(set) var items: [RecentDownloadItem] = []
    private(set) var selectedID: String?
    private(set) var loadState: DownloadsLoadState = .idle
    private(set) var shouldScrollToSelection = false
    private(set) var isPerformingAction = false
    var statusMessage: String?
    var showsActionsMenu = false

    init(
        provider: any RecentDownloadsProviding,
        urlOpener: any URLOpening,
        fileRevealer: any FileRevealing,
        pasteboard: any PasteboardAccessing,
        resultLimit: Int = NativeRecentDownloadsService.defaultLimit,
        onGoBack: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.provider = provider
        self.urlOpener = urlOpener
        self.fileRevealer = fileRevealer
        self.pasteboard = pasteboard
        self.resultLimit = min(max(1, resultLimit), NativeRecentDownloadsService.maximumLimit)
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
    }

    deinit {
        loadTask?.cancel()
        operationTask?.cancel()
    }

    var filteredItems: [RecentDownloadItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(needle)
                || item.url.pathExtension.localizedCaseInsensitiveContains(needle)
        }
    }

    var newestItem: RecentDownloadItem? {
        items.first
    }

    var selectedItem: RecentDownloadItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    var footerActions: [CommandActionDescriptor] {
        guard let selectedItem else {
            return [
                CommandActionDescriptor(
                    id: DownloadsActionID.refresh,
                    title: loadState == .loading ? "Refreshing…" : "Refresh",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: loadState != .loading
                )
            ]
        }
        let isNewest = selectedItem.id == newestItem?.id
        return [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: isNewest ? "Open Newest" : "Open Download",
                isPrimary: true,
                keyHint: .return,
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copyFile,
                title: isNewest ? "Copy Newest" : "Copy File",
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isPerformingAction == false
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(
                id: DownloadsActionID.openNewest,
                title: "Open Newest Download",
                isEnabled: newestItem != nil && isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: DownloadsActionID.copyNewest,
                title: "Copy Newest Download",
                isEnabled: newestItem != nil && isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: DownloadsActionID.refresh,
                title: "Refresh Downloads",
                isEnabled: loadState != .loading && isPerformingAction == false
            )
        ]
        if selectedItem != nil {
            actions.append(contentsOf: [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openFile,
                    title: "Open Selected Download",
                    isEnabled: isPerformingAction == false
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.revealFile,
                    title: "Show Selected in Finder",
                    isEnabled: isPerformingAction == false
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.copyFile,
                    title: "Copy Selected Download",
                    isEnabled: isPerformingAction == false
                )
            ])
        }
        return actions
    }

    func load() {
        refresh(showSuccessMessage: false)
    }

    func refresh(showSuccessMessage: Bool = true) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadState = .loading
        shouldScrollToSelection = false
        if showSuccessMessage {
            statusMessage = nil
        }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updatedItems = try await provider.recentDownloads(limit: resultLimit)
                guard Task.isCancelled == false, loadGeneration == generation else { return }
                items = updatedItems
                loadState = updatedItems.isEmpty ? .empty : .loaded
                selectedID = LauncherListSelection.resolvedID(
                    in: filteredItems,
                    selectedID: selectedID,
                    id: \.id
                )
                shouldScrollToSelection = true
                if showSuccessMessage {
                    statusMessage = updatedItems.isEmpty
                        ? "No recent downloads found."
                        : "Recent downloads refreshed."
                }
            } catch is CancellationError {
                guard loadGeneration == generation else { return }
                loadState = items.isEmpty ? .idle : .loaded
            } catch let error as RecentDownloadsError {
                guard loadGeneration == generation else { return }
                loadState = .failed(error)
                statusMessage = error.errorDescription
            } catch {
                guard loadGeneration == generation else { return }
                let error = RecentDownloadsError.scanFailed
                loadState = .failed(error)
                statusMessage = error.errorDescription
            }
        }
    }

    func select(_ id: String) {
        guard filteredItems.contains(where: { $0.id == id }) else { return }
        selectedID = id
        shouldScrollToSelection = false
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        guard let nextID = LauncherListSelection.nextID(
            in: filteredItems,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        ) else { return }
        selectedID = nextID
        shouldScrollToSelection = true
        statusMessage = nil
    }

    func performPrimary() {
        guard let action = footerActions.first(where: { $0.isPrimary && $0.isEnabled }) else {
            return
        }
        perform(action.id)
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case DownloadsActionID.refresh:
            refresh()
        case DownloadsActionID.openNewest:
            beginOperation(newestItem.map { .open($0.url) })
        case DownloadsActionID.copyNewest:
            beginOperation(newestItem.map { .copy($0.url) })
        case BuiltInCommandActionID.openFile:
            beginOperation(selectedItem.map { .open($0.url) })
        case BuiltInCommandActionID.revealFile:
            beginOperation(selectedItem.map { .reveal($0.url) })
        case BuiltInCommandActionID.copyFile:
            beginOperation(selectedItem.map { .copy($0.url) })
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        case BuiltInCommandActionID.goBack:
            goBack()
        default:
            break
        }
    }

    func handleEscape() -> Bool {
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func goBack() {
        onGoBack()
    }

    func stop() {
        loadGeneration += 1
        operationGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        operationTask = nil
        isPerformingAction = false
    }

    func waitForLoadForTesting() async {
        await loadTask?.value
    }

    func waitForOperationForTesting() async {
        await operationTask?.value
    }

    private func resolveSelection() {
        selectedID = LauncherListSelection.resolvedID(
            in: filteredItems,
            selectedID: selectedID,
            id: \.id
        )
        shouldScrollToSelection = true
    }

    private func beginOperation(_ operation: DownloadOperation?) {
        guard let operation else {
            statusMessage = "No recent download is available."
            return
        }
        operationGeneration += 1
        let generation = operationGeneration
        operationTask?.cancel()
        isPerformingAction = true
        showsActionsMenu = false
        statusMessage = nil

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch operation {
                case .open(let url):
                    try await urlOpener.openURL(url)
                    guard Task.isCancelled == false, operationGeneration == generation else { return }
                    isPerformingAction = false
                    onDismiss()
                case .reveal(let url):
                    try await fileRevealer.revealInFinder(urls: [url])
                    guard Task.isCancelled == false, operationGeneration == generation else { return }
                    isPerformingAction = false
                    statusMessage = "Shown in Finder."
                case .copy(let url):
                    await pasteboard.writeFileURLs([url])
                    guard Task.isCancelled == false, operationGeneration == generation else { return }
                    isPerformingAction = false
                    statusMessage = "Copied download."
                }
            } catch is CancellationError {
                guard operationGeneration == generation else { return }
                isPerformingAction = false
            } catch {
                guard operationGeneration == generation else { return }
                isPerformingAction = false
                let featureError: RecentDownloadsError
                switch operation {
                case .open: featureError = .openFailed
                case .reveal: featureError = .revealFailed
                case .copy: return
                }
                statusMessage = featureError.errorDescription
            }
        }
    }
}
