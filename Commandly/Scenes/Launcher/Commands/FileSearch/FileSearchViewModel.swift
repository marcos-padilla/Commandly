import Foundation
import Observation
import CommandKit
import Infrastructure
import SearchKit

enum FileSearchLoadState: Equatable {
    case idle
    case loading
    case loaded
    case needsFolderAccess
    case failed
}

enum FileSearchActionPage: Equatable {
    case main
    case openWith
    case share
    case move
    case copy
    case shortcut
}

@Observable
@MainActor
final class FileSearchViewModel {
    @ObservationIgnored
    private let searchService: any FileSearching
    @ObservationIgnored
    private let urlOpener: any URLOpening
    @ObservationIgnored
    private let fileRevealer: any FileRevealing
    @ObservationIgnored
    private let fileActionService: any FileActionServicing
    @ObservationIgnored
    private let finderInfoPresenter: any FinderInfoPresenting
    @ObservationIgnored
    private let pasteboard: any PasteboardAccessing
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    var category: FileSearchCategory = .all {
        didSet {
            guard category != oldValue else { return }
            scheduleSearch(debounce: false)
        }
    }
    private(set) var results: [FileSearchItem] = []
    private(set) var loadState: FileSearchLoadState = .idle
    private(set) var selectedID: String?
    private(set) var shouldScrollToSelection = false
    var statusMessage: String?
    var showsActionsMenu = false
    var showsDetails = true
    var actionQuery = ""
    private(set) var actionTargetID: String?
    private(set) var actionPage: FileSearchActionPage = .main
    private(set) var actionOptions: [FileActionOption] = []
    private(set) var isLoadingActionOptions = false

    let searchPlaceholder = "Search files and contents…"
    let onGoBack: () -> Void
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    init(
        searchService: any FileSearching,
        urlOpener: any URLOpening,
        fileRevealer: any FileRevealing,
        fileActionService: any FileActionServicing = InMemoryFileActionService(),
        finderInfoPresenter: any FinderInfoPresenting = InMemoryFinderInfoPresenter(),
        pasteboard: any PasteboardAccessing,
        onGoBack: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.searchService = searchService
        self.urlOpener = urlOpener
        self.fileRevealer = fileRevealer
        self.fileActionService = fileActionService
        self.finderInfoPresenter = finderInfoPresenter
        self.pasteboard = pasteboard
        self.onGoBack = onGoBack
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }

    deinit {
        searchTask?.cancel()
    }

    var selectedItem: FileSearchItem? {
        results.first { $0.id == selectedID } ?? results.first
    }

    var sectionTitle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recent Files" : "Results"
    }

    var footerActions: [CommandActionDescriptor] {
        guard selectedItem != nil else {
            if loadState == .needsFolderAccess {
                return [
                    CommandActionDescriptor(
                        id: BuiltInCommandActionID.settings,
                        title: "Open Settings",
                        isPrimary: true,
                        keyHint: .return
                    )
                ]
            }
            return []
        }
        return [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: "Open",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        guard selectedItem != nil else { return [] }
        return [
            CommandActionDescriptor(id: BuiltInCommandActionID.openFile, title: "Open"),
            CommandActionDescriptor(id: BuiltInCommandActionID.revealFile, title: "Show in Finder"),
            CommandActionDescriptor(id: BuiltInCommandActionID.copyFilePath, title: "Copy Path")
        ]
    }

    var showsActionPanel: Bool { actionTargetID != nil }

    var actionPanelTitle: String {
        switch actionPage {
        case .main: return actionTarget?.name ?? "File Actions"
        case .openWith: return "Open With"
        case .share: return "Share"
        case .move: return "Move To"
        case .copy: return "Copy To"
        case .shortcut: return "Create Shortcut In"
        }
    }

    var filteredActionPanelItems: [LauncherActionPanelItem] {
        let items = actionPanelItems
        let trimmed = actionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    func load() {
        (searchService as? any FileSearchSessionManaging)?.beginFileSearchSession()
        scheduleSearch(debounce: false)
    }

    func stop() {
        searchTask?.cancel()
        (searchService as? any FileSearchSessionManaging)?.endFileSearchSession()
    }

    func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        let querySnapshot = query
        let categorySnapshot = category
        searchTask = Task { [weak self] in
            if debounce {
                do {
                    try await ContinuousClock().sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard Task.isCancelled == false else { return }
            await self?.performSearch(query: querySnapshot, category: categorySnapshot)
        }
    }

    func performSearch(query: String, category: FileSearchCategory) async {
        let namesRequest = FileSearchRequest(
            query: SearchQuery(text: query, limit: 100),
            category: category,
            includesFileContents: false
        )
        loadState = .loading
        statusMessage = nil
        do {
            if namesRequest.query.isEmpty {
                let newResults = try await searchService.search(namesRequest)
                try Task.checkCancellation()
                guard self.query == query, self.category == category else { return }
                applyResults(newResults)
                return
            }

            let contentRequest = FileSearchRequest(
                query: namesRequest.query,
                category: category,
                includesFileNames: false,
                includesFileContents: true
            )
            async let contentSearch = searchService.search(contentRequest)
            let filenameResults = try await searchService.search(namesRequest)
            try Task.checkCancellation()
            guard self.query == query, self.category == category else { return }
            applyResults(filenameResults)

            do {
                let contentResults = try await contentSearch
                try Task.checkCancellation()
                guard self.query == query, self.category == category else { return }
                applyResults(merge(filenameResults: filenameResults, contentResults: contentResults))
            } catch is CancellationError {
                return
            } catch {
                // Filename search remains fully usable when Spotlight content extraction
                // is unavailable for a volume or individual file type.
                statusMessage = "Some file-content results may be unavailable."
            }
        } catch is CancellationError {
            return
        } catch FileSearchError.noAuthorizedScopes {
            guard self.query == query, self.category == category else { return }
            results = []
            selectedID = nil
            loadState = .needsFolderAccess
        } catch {
            guard self.query == query, self.category == category else { return }
            results = []
            selectedID = nil
            loadState = .failed
            statusMessage = "File search is temporarily unavailable."
        }
    }

    func flushSearchForTesting() async {
        searchTask?.cancel()
        await performSearch(query: query, category: category)
    }

    func select(_ id: String) {
        guard results.contains(where: { $0.id == id }) else { return }
        selectedID = id
        shouldScrollToSelection = false
    }

    func moveSelection(offset: Int) {
        guard results.isEmpty == false else { return }
        let current = selectedItem.flatMap { item in results.firstIndex(where: { $0.id == item.id }) } ?? 0
        selectedID = results[(current + offset + results.count) % results.count].id
        shouldScrollToSelection = true
    }

    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        if actionID == BuiltInCommandActionID.openActions {
            presentActions(for: selectedItem?.id)
            return
        }
        if actionID == BuiltInCommandActionID.settings, loadState == .needsFolderAccess {
            onOpenSettings()
            return
        }
        guard let item = selectedItem else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                switch actionID {
                case BuiltInCommandActionID.openFile:
                    try await urlOpener.openURL(item.url)
                    onDismiss()
                case BuiltInCommandActionID.revealFile:
                    try await fileRevealer.revealInFinder(urls: [item.url])
                    statusMessage = "Shown in Finder."
                case BuiltInCommandActionID.copyFilePath:
                    await pasteboard.writeString(item.url.path)
                    statusMessage = "Path copied."
                default:
                    break
                }
            } catch {
                statusMessage = "That file action couldn’t be completed."
            }
        }
    }

    func presentActions(for itemID: String?) {
        guard let itemID, results.contains(where: { $0.id == itemID }) else { return }
        select(itemID)
        actionTargetID = itemID
        actionPage = .main
        actionQuery = ""
        actionOptions = []
    }

    func dismissActionPanel() {
        actionTargetID = nil
        actionPage = .main
        actionQuery = ""
        actionOptions = []
        isLoadingActionOptions = false
    }

    func actionPanelBack() {
        guard actionPage != .main else {
            dismissActionPanel()
            return
        }
        actionPage = .main
        actionQuery = ""
        actionOptions = []
    }

    func performPanelAction(_ actionID: CommandActionID) {
        guard let item = actionTarget else { return }
        switch actionID {
        case BuiltInCommandActionID.openFileWith:
            showOptions(page: .openWith, for: item)
        case BuiltInCommandActionID.shareFile:
            showOptions(page: .share, for: item)
        case BuiltInCommandActionID.moveFile:
            showDestinations(page: .move)
        case BuiltInCommandActionID.copyFileTo:
            showDestinations(page: .copy)
        case BuiltInCommandActionID.createFileShortcut:
            showDestinations(page: .shortcut)
        case BuiltInCommandActionID.toggleFileDetails:
            showsDetails.toggle()
            statusMessage = showsDetails ? "Details shown." : "Details hidden."
            dismissActionPanel()
        case BuiltInCommandActionID.copyFile:
            Task { [weak self] in
                await self?.pasteboard.writeFileURLs([item.url])
                self?.statusMessage = "File copied."
                self?.dismissActionPanel()
            }
        case BuiltInCommandActionID.copyFileName:
            copyText(item.name, message: "Name copied.")
        case BuiltInCommandActionID.copyFilePath:
            copyText(item.url.path, message: "Path copied.")
        case BuiltInCommandActionID.openFile:
            runAction(success: nil, dismissLauncher: true) { [urlOpener] in
                try await urlOpener.openURL(item.url)
            }
        case BuiltInCommandActionID.revealFile:
            runAction(success: "Shown in Finder.") { [fileRevealer] in
                try await fileRevealer.revealInFinder(urls: [item.url])
            }
        case BuiltInCommandActionID.showFileInfo:
            runAction(success: "Info opened in Finder.") { [finderInfoPresenter] in
                try await finderInfoPresenter.showGetInfo(atPath: item.url.path)
            }
        case BuiltInCommandActionID.openEnclosingFolder:
            runAction(success: nil) { [urlOpener] in
                try await urlOpener.openURL(item.url.deletingLastPathComponent())
            }
        case BuiltInCommandActionID.duplicateFile:
            runAction(success: "Duplicate created.") { [fileActionService] in
                _ = try await fileActionService.duplicate(item.url)
            }
        case BuiltInCommandActionID.trashFile:
            runAction(success: "Moved to Trash.", removeTarget: true) { [fileActionService] in
                try await fileActionService.moveToTrash(item.url)
            }
        default:
            if let option = option(for: actionID) {
                performOption(option, for: item)
            } else if let directory = destination(for: actionID) {
                performDestination(directory, for: item)
            } else if actionID.rawValue == "file.destination.choose" {
                chooseDestination(for: item)
            }
        }
    }

    private var actionTarget: FileSearchItem? {
        guard let actionTargetID else { return nil }
        return results.first { $0.id == actionTargetID }
    }

    private var actionPanelItems: [LauncherActionPanelItem] {
        if isLoadingActionOptions {
            return [LauncherActionPanelItem(
                id: CommandActionID(rawValue: "file.loading"),
                title: "Loading…",
                systemImage: "progress.indicator",
                isEnabled: false
            )]
        }
        switch actionPage {
        case .main:
            return mainActionItems
        case .openWith, .share:
            let icon = actionPage == .openWith ? "app" : "square.and.arrow.up"
            return actionOptions.enumerated().map { index, option in
                LauncherActionPanelItem(
                    id: CommandActionID(rawValue: "file.option.\(index)"),
                    title: option.title,
                    systemImage: icon
                )
            }
        case .move, .copy, .shortcut:
            return destinationItems
        }
    }

    private var mainActionItems: [LauncherActionPanelItem] {
        [
            .init(id: BuiltInCommandActionID.openFile, title: "Open", systemImage: "arrow.up.forward.app", keyHint: .return, section: "open"),
            .init(id: BuiltInCommandActionID.openFileWith, title: "Open With…", systemImage: "square.and.arrow.up", section: "open"),
            .init(id: BuiltInCommandActionID.showFileInfo, title: "Show Info in Finder", systemImage: "info.square", section: "finder"),
            .init(id: BuiltInCommandActionID.revealFile, title: "Show in Finder", systemImage: "finder", section: "finder"),
            .init(id: BuiltInCommandActionID.openEnclosingFolder, title: "Open Enclosing Folder", systemImage: "folder", section: "finder"),
            .init(id: BuiltInCommandActionID.toggleFileDetails, title: showsDetails ? "Hide Details" : "Show Details", systemImage: "sidebar.right", section: "finder"),
            .init(id: BuiltInCommandActionID.shareFile, title: "Share…", systemImage: "square.and.arrow.up", section: "share"),
            .init(id: BuiltInCommandActionID.moveFile, title: "Move To…", systemImage: "folder", section: "manage"),
            .init(id: BuiltInCommandActionID.copyFileTo, title: "Copy To…", systemImage: "folder.badge.plus", section: "manage"),
            .init(id: BuiltInCommandActionID.duplicateFile, title: "Duplicate", systemImage: "doc.on.doc", section: "manage"),
            .init(id: BuiltInCommandActionID.createFileShortcut, title: "Create Commandly Shortcut…", systemImage: "link", section: "shortcut"),
            .init(id: BuiltInCommandActionID.copyFile, title: "Copy File", systemImage: "doc.on.clipboard", section: "clipboard"),
            .init(id: BuiltInCommandActionID.copyFileName, title: "Copy Name", systemImage: "textformat", section: "clipboard"),
            .init(id: BuiltInCommandActionID.copyFilePath, title: "Copy Path", systemImage: "point.topleft.down.to.point.bottomright.curvepath", section: "clipboard"),
            .init(id: BuiltInCommandActionID.trashFile, title: "Move to Trash", systemImage: "trash", isDestructive: true, section: "trash")
        ]
    }

    private var destinationItems: [LauncherActionPanelItem] {
        let standard = standardDestinations.enumerated().map { index, destination in
            LauncherActionPanelItem(
                id: CommandActionID(rawValue: "file.destination.\(index)"),
                title: destination.lastPathComponent,
                systemImage: "folder"
            )
        }
        return standard + [
            LauncherActionPanelItem(
                id: CommandActionID(rawValue: "file.destination.choose"),
                title: "Choose Folder…",
                systemImage: "folder.badge.plus",
                section: "choose"
            )
        ]
    }

    private var standardDestinations: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Documents", "Downloads"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }

    private func showOptions(page: FileSearchActionPage, for item: FileSearchItem) {
        actionPage = page
        actionQuery = ""
        actionOptions = []
        isLoadingActionOptions = true
        Task { [weak self] in
            guard let self else { return }
            let options = if page == .openWith {
                await fileActionService.applications(toOpen: item.url)
            } else {
                await fileActionService.sharingServices(for: item.url)
            }
            guard actionTargetID == item.id, actionPage == page else { return }
            actionOptions = options
            isLoadingActionOptions = false
        }
    }

    private func showDestinations(page: FileSearchActionPage) {
        actionPage = page
        actionQuery = ""
        actionOptions = []
    }

    private func option(for actionID: CommandActionID) -> FileActionOption? {
        guard actionID.rawValue.hasPrefix("file.option."),
              let index = Int(actionID.rawValue.dropFirst("file.option.".count)),
              actionOptions.indices.contains(index)
        else { return nil }
        return actionOptions[index]
    }

    private func destination(for actionID: CommandActionID) -> URL? {
        guard actionID.rawValue.hasPrefix("file.destination."),
              let index = Int(actionID.rawValue.dropFirst("file.destination.".count)),
              standardDestinations.indices.contains(index)
        else { return nil }
        return standardDestinations[index]
    }

    private func performOption(_ option: FileActionOption, for item: FileSearchItem) {
        let page = actionPage
        runAction(success: page == .share ? "Shared." : nil, dismissLauncher: page == .openWith) { [fileActionService] in
            if page == .openWith {
                try await fileActionService.open(item.url, withApplication: option.id)
            } else {
                try await fileActionService.share(item.url, withService: option.id)
            }
        }
    }

    private func chooseDestination(for item: FileSearchItem) {
        let page = actionPage
        Task { [weak self] in
            guard let self else { return }
            let title = page == .move ? "Move \(item.name)" : page == .copy ? "Copy \(item.name)" : "Create Shortcut"
            guard let directory = await fileActionService.chooseDestination(title: title) else { return }
            performDestination(directory, for: item, page: page)
        }
    }

    private func performDestination(
        _ directory: URL,
        for item: FileSearchItem,
        page: FileSearchActionPage? = nil
    ) {
        let operation = page ?? actionPage
        switch operation {
        case .move:
            runAction(success: "File moved.", removeTarget: true) { [fileActionService] in
                _ = try await fileActionService.move(item.url, to: directory)
            }
        case .copy:
            runAction(success: "File copied.") { [fileActionService] in
                _ = try await fileActionService.copy(item.url, to: directory)
            }
        case .shortcut:
            runAction(success: "Commandly shortcut created.") { [fileActionService] in
                _ = try await fileActionService.createShortcut(for: item.url, in: directory)
            }
        default:
            break
        }
    }

    private func copyText(_ value: String, message: String) {
        Task { [weak self] in
            await self?.pasteboard.writeString(value)
            self?.statusMessage = message
            self?.dismissActionPanel()
        }
    }

    private func runAction(
        success: String?,
        removeTarget: Bool = false,
        dismissLauncher: Bool = false,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        let targetID = actionTargetID
        Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                if removeTarget, let targetID {
                    results.removeAll { $0.id == targetID }
                    refreshSelection()
                }
                statusMessage = success
                dismissActionPanel()
                if dismissLauncher { onDismiss() }
            } catch {
                statusMessage = "That file action couldn’t be completed."
            }
        }
    }

    func goBack() {
        stop()
        onGoBack()
    }

    private func refreshSelection() {
        if let selectedID, results.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = results.first?.id
    }

    private func applyResults(_ newResults: [FileSearchItem]) {
        results = newResults
        loadState = .loaded
        refreshSelection()
    }

    private func merge(
        filenameResults: [FileSearchItem],
        contentResults: [FileSearchItem]
    ) -> [FileSearchItem] {
        var seen = Set<String>()
        return (filenameResults + contentResults).filter { seen.insert($0.id).inserted }
    }
}
