import Foundation
import Observation
import CommandKit
import SearchKit
import Infrastructure
import CalculatorKit
import SwiftUI
import AppKit

/// Navigation stack inside the launcher window.
enum LauncherRoute: Equatable {
    case root
    case command(CommandID)
    case uninstallReview(bundleIdentifier: String)
}

/// Tracks whether the user is navigating with keyboard or pointer.
enum LauncherInputDevice: Equatable {
    case keyboard
    case pointer
}

@Observable
@MainActor
final class LauncherViewModel {
    private let catalog: CommandCatalog
    @ObservationIgnored
    private let clipboardHistoryStore: ClipboardHistoryStore
    @ObservationIgnored
    private let fileSearchService: any FileSearching
    @ObservationIgnored
    private let urlOpener: any URLOpening
    @ObservationIgnored
    private let applicationOpener: any ApplicationOpening
    @ObservationIgnored
    private let applicationQuery: any InstalledApplicationQuerying
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    let fileRevealer: any FileRevealing
    @ObservationIgnored
    let fileActionService: any FileActionServicing
    @ObservationIgnored
    let bundleManager: any ApplicationBundleManaging
    @ObservationIgnored
    let finderInfoPresenter: any FinderInfoPresenting
    @ObservationIgnored
    let pasteboard: any PasteboardAccessing
    @ObservationIgnored
    let uninstallDiscoverer: any ApplicationUninstallDiscovering
    @ObservationIgnored
    private let calculator: any CalculatorEvaluating
    @ObservationIgnored
    private let calculatorSession: CalculatorSessionStore

    private(set) var placeholderItems: [LauncherItem]
    private(set) var rootItems: [LauncherItem] = []
    private(set) var autocompleteSuffix: String = ""
    private(set) var autocompleteCompletion: String?
    private(set) var autocompleteActionLabel: String?
    /// Bumped on each presentation so the search field can reclaim focus.
    private(set) var searchFocusEpoch: Int = 0
    private(set) var activeCalculatorResult: CalculatorResult?

    var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            scheduleSearch()
        }
    }
    var selectedID: String?
    var statusMessage: String?
    private(set) var shouldScrollToSelection = false
    private(set) var inputDevice: LauncherInputDevice = .pointer
    /// True while the results list is scrolling; pointer hover must not move selection.
    private(set) var isResultsScrolling = false
    private var hoveredID: String?
    var route: LauncherRoute = .root
    var clipboardViewModel: ClipboardHistoryViewModel?
    var fileSearchViewModel: FileSearchViewModel?
    var uninstallViewModel: ApplicationUninstallViewModel?
    /// When non-nil, the application actions panel is presented for this bundle ID.
    var applicationActionsTargetBundleID: String?
    var applicationActionsQuery: String = ""
    @ObservationIgnored
    private var resultsScrollEndTask: Task<Void, Never>?

    var onDismiss: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @ObservationIgnored
    private var searchTask: Task<Void, Never>?
    @ObservationIgnored
    var cachedApplications: [InstalledApplicationSnapshot] = []
    @ObservationIgnored
    private var didLoadApplications = false
    private var calculatorSuggestion: CalculatorSuggestion?

    init(
        catalog: CommandCatalog = .makeBuiltIn(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        fileSearchService: any FileSearching = InMemoryFileSearchService(),
        urlOpener: any URLOpening = NoOpURLOpener(),
        applicationOpener: any ApplicationOpening = NoOpApplicationOpener(),
        applicationQuery: any InstalledApplicationQuerying = InMemoryInstalledApplicationQuery(),
        applicationPreferencesStore: any ApplicationPreferencesStoring = InMemoryApplicationPreferencesStore(),
        fileRevealer: any FileRevealing = InMemoryFileRevealer(),
        fileActionService: any FileActionServicing = InMemoryFileActionService(),
        bundleManager: any ApplicationBundleManaging = InMemoryApplicationBundleManager(),
        finderInfoPresenter: any FinderInfoPresenting = InMemoryFinderInfoPresenter(),
        uninstallDiscoverer: any ApplicationUninstallDiscovering = InMemoryApplicationUninstallDiscoverer(),
        pasteboard: any PasteboardAccessing = SystemPasteboard(),
        calculator: any CalculatorEvaluating = CalculatorService(),
        calculatorSession: CalculatorSessionStore = CalculatorSessionStore(),
        placeholderItems: [LauncherItem] = LauncherPlaceholderCatalog.nonCommandItems,
        onDismiss: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.catalog = catalog
        self.clipboardHistoryStore = clipboardHistoryStore
        self.fileSearchService = fileSearchService
        self.urlOpener = urlOpener
        self.applicationOpener = applicationOpener
        self.applicationQuery = applicationQuery
        self.applicationPreferencesStore = applicationPreferencesStore
        self.fileRevealer = fileRevealer
        self.fileActionService = fileActionService
        self.bundleManager = bundleManager
        self.finderInfoPresenter = finderInfoPresenter
        self.uninstallDiscoverer = uninstallDiscoverer
        self.pasteboard = pasteboard
        self.calculator = calculator
        self.calculatorSession = calculatorSession
        self.placeholderItems = placeholderItems
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
    }

    var runtime: CommandRuntime {
        CommandRuntime(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchService: fileSearchService,
            urlOpener: urlOpener,
            fileRevealer: fileRevealer,
            fileActionService: fileActionService,
            finderInfoPresenter: finderInfoPresenter,
            pasteboard: pasteboard,
            dismissLauncher: { [weak self] in self?.dismiss() },
            openSettings: { [weak self] in
                self?.dismiss()
                self?.onOpenSettings()
            },
            goBack: { [weak self] in self?.goBack() }
        )
    }

    var sections: [(kind: LauncherSectionKind, items: [LauncherItem])] {
        LauncherSectionKind.allCases.compactMap { kind in
            let sectionItems = rootItems.filter { $0.section == kind }
            guard sectionItems.isEmpty == false else { return nil }
            return (kind, sectionItems)
        }
    }

    var selectedItem: LauncherItem? {
        rootItems.first { $0.id == selectedID } ?? rootItems.first
    }

    var isRoot: Bool { route == .root }

    var contextTitle: String {
        switch route {
        case .root:
            return "Commandly"
        case .command(let id):
            return catalog.command(for: id)?.manifest.title ?? "Command"
        case .uninstallReview:
            return uninstallViewModel?.applicationName ?? "Uninstall"
        }
    }

    var contextSystemImage: String {
        switch route {
        case .root:
            return "command"
        case .command(let id):
            return catalog.command(for: id)?.manifest.systemImage ?? "command"
        case .uninstallReview:
            return "trash"
        }
    }

    /// App-icon dropdown on the root footer (Settings, Quit).
    var appMenuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.settings,
                title: "Settings…",
                keyHint: CommandKeyHint(symbols: ["⌘", ","])
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.quit,
                title: "Quit Commandly",
                keyHint: CommandKeyHint(symbols: ["⌘", "Q"])
            )
        ]
    }

    /// Root footer Actions: application actions when an app is selected; otherwise empty.
    var rootActionsMenuItems: [CommandActionDescriptor] {
        applicationActions(for: selectedApplicationBundleID).map(\.descriptor)
    }

    var showsApplicationActionsPanel: Bool {
        applicationActionsTargetBundleID != nil
    }

    var applicationActionsPanelTitle: String {
        guard let bundleID = applicationActionsTargetBundleID,
              let app = cachedApplications.first(where: { $0.bundleIdentifier == bundleID })
        else {
            return "Actions"
        }
        return app.name
    }

    var filteredApplicationActions: [LauncherApplicationAction] {
        let actions = applicationActions(for: applicationActionsTargetBundleID)
        let trimmed = applicationActionsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var selectedApplicationBundleID: String? {
        guard case .openApplication(let bundleID) = selectedItem?.action else { return nil }
        return bundleID
    }

    var footerActions: [CommandActionDescriptor] {
        switch route {
        case .root:
            return [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK
                )
            ]
        case .command:
            return clipboardViewModel?.footerActions
                ?? fileSearchViewModel?.footerActions
                ?? []
        case .uninstallReview:
            return []
        }
    }

    var menuActions: [CommandActionDescriptor] {
        if let result = activeCalculatorResult, case .root = route {
            var actions = [
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "copyAnswer"),
                    title: "Copy Answer"
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "copyUnformatted"),
                    title: "Copy Without Formatting"
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "openCalculator"),
                    title: "Open in Calculator"
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "addToNote"),
                    title: "Copy and Open Notes"
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "insertResult"),
                    title: "Insert Result into Search"
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "copyExpression"),
                    title: "Copy Expression and Result"
                )
            ]
            if result.actionHints.contains(.copyResultUnformatted) == false {
                actions.removeAll { $0.id.rawValue == "copyUnformatted" }
            }
            if supportsOpenInCalculator(result.primaryValue) == false {
                actions.removeAll { $0.id.rawValue == "openCalculator" }
            }
            return actions
        }
        return clipboardViewModel?.menuActions ?? fileSearchViewModel?.menuActions ?? []
    }

    var showsActionsMenu: Bool {
        get { clipboardViewModel?.showsActionsMenu ?? fileSearchViewModel?.showsActionsMenu ?? false }
        set {
            clipboardViewModel?.showsActionsMenu = newValue
            fileSearchViewModel?.showsActionsMenu = newValue
        }
    }

    func prepareForPresentation() {
        resetAfterDismiss()
        clipboardHistoryStore.startMonitoring()
        requestSearchFocus()
        scheduleSearch(loadApplicationsIfNeeded: true)
    }

    /// Bumps ``searchFocusEpoch`` so the search field reclaims first responder.
    /// Used when the launcher window is raised again without a full view remount.
    func requestSearchFocus() {
        searchFocusEpoch += 1
    }

    /// Clears navigation / command-surface state when the launcher is hidden.
    func resetAfterDismiss() {
        searchTask?.cancel()
        searchTask = nil
        resultsScrollEndTask?.cancel()
        resultsScrollEndTask = nil
        query = ""
        statusMessage = nil
        shouldScrollToSelection = false
        isResultsScrolling = false
        hoveredID = nil
        inputDevice = .pointer
        route = .root
        clipboardViewModel = nil
        fileSearchViewModel?.stop()
        fileSearchViewModel = nil
        uninstallViewModel = nil
        activeCalculatorResult = nil
        dismissApplicationActionsPanel()
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
    }

    func select(_ id: String) {
        shouldScrollToSelection = false
        selectedID = id
        statusMessage = nil
        refreshAutocomplete()
    }

    func setHovered(_ id: String?) {
        hoveredID = id
        guard isResultsScrolling == false else { return }
        guard let id, inputDevice == .pointer else { return }
        select(id)
    }

    func clearHovered(_ id: String) {
        if hoveredID == id {
            hoveredID = nil
        }
    }

    /// Marks the results list as scrolling so pointer hover cannot steal selection.
    ///
    /// Call on each scroll-offset change. Clears the hovered row on begin, keeps
    /// tracking subsequent hover IDs without applying them, then after a short
    /// debounce reapplies hover selection if the pointer is still the active input.
    /// The delay is only for hover resume — keyboard selection stays active throughout.
    func beginResultsScrolling() {
        if isResultsScrolling == false {
            isResultsScrolling = true
            hoveredID = nil
        }
        resultsScrollEndTask?.cancel()
        resultsScrollEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, Task.isCancelled == false else { return }
            self.isResultsScrolling = false
            if self.inputDevice == .pointer, let hoveredID = self.hoveredID {
                self.select(hoveredID)
            }
        }
    }

    func beginPointerInput() {
        guard isResultsScrolling == false else { return }
        guard inputDevice != .pointer else { return }
        inputDevice = .pointer
        if let hoveredID {
            select(hoveredID)
        }
    }

    func moveSelection(offset: Int) {
        if case .command = route {
            if let clipboardViewModel {
                clipboardViewModel.moveSelection(offset: offset)
            } else {
                fileSearchViewModel?.moveSelection(offset: offset)
            }
            return
        }
        let list = rootItems
        guard list.isEmpty == false else { return }
        let currentIndex = list.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = (currentIndex + offset + list.count) % list.count
        inputDevice = .keyboard
        shouldScrollToSelection = true
        selectedID = list[nextIndex].id
        statusMessage = nil
        refreshAutocomplete()
    }

    func acceptAutocomplete() {
        guard let autocompleteCompletion else { return }
        query = autocompleteCompletion
    }

    func confirmSelection() {
        if case .command = route {
            if let clipboardViewModel {
                clipboardViewModel.perform(BuiltInCommandActionID.copy)
            } else {
                fileSearchViewModel?.perform(BuiltInCommandActionID.openFile)
            }
            return
        }
        guard let item = selectedItem else { return }
        switch item.action {
        case .openSettings:
            onDismiss()
            onOpenSettings()
        case .dismiss:
            onDismiss()
        case .placeholder(let message):
            statusMessage = message
        case .openCommand(let commandID):
            activate(commandID)
        case .openApplication(let bundleIdentifier):
            Task { @MainActor [weak self] in
                await self?.openApplication(bundleIdentifier: bundleIdentifier)
            }
        case .copyText(let value):
            Task { @MainActor [weak self] in
                await self?.pasteboard.writeString(value)
                self?.statusMessage = nil
                self?.dismiss()
            }
        case .calculatorPrimary(let resultID):
            performCalculatorPrimary(resultID: resultID)
        }
    }

    /// Test helper: awaits primary confirm side effects (copy / open).
    func confirmSelectionAndWaitForTesting() async {
        if case .command = route {
            clipboardViewModel?.perform(BuiltInCommandActionID.copy)
            return
        }
        guard let item = selectedItem else { return }
        switch item.action {
        case .copyText(let value):
            await pasteboard.writeString(value)
            statusMessage = nil
            dismiss()
        case .calculatorPrimary(let resultID):
            guard let result = activeCalculatorResult, result.id.rawValue == resultID else { return }
            calculatorSession.recordSuccess(result)
            await pasteboard.writeString(result.formattedPrimaryValue)
            statusMessage = "Copied answer."
        default:
            confirmSelection()
        }
    }

    func performFooterAction(_ id: CommandActionID) {
        if case .command = route {
            if let clipboardViewModel {
                clipboardViewModel.perform(id)
            } else {
                fileSearchViewModel?.perform(id)
            }
            return
        }
        switch id {
        case BuiltInCommandActionID.settings:
            onDismiss()
            onOpenSettings()
        case BuiltInCommandActionID.quit:
            onQuit()
        case BuiltInCommandActionID.openActions:
            presentApplicationActionsForSelection()
        default:
            switch id.rawValue {
            case "copyAnswer":
                if let result = activeCalculatorResult {
                    copyCalculatorAnswer(resultID: result.id.rawValue)
                }
            case "copyUnformatted":
                if let result = activeCalculatorResult {
                    Task { @MainActor [weak self] in
                        await self?.pasteboard.writeString(result.formattedPrimaryValue.replacingOccurrences(of: ",", with: ""))
                        self?.statusMessage = "Copied without formatting."
                    }
                }
            case "insertResult":
                if let result = activeCalculatorResult {
                    query = result.formattedPrimaryValue
                    requestSearchFocus()
                }
            case "copyExpression":
                if let result = activeCalculatorResult {
                    let combined = "\(result.displayExpression) = \(result.formattedPrimaryValue)"
                    Task { @MainActor [weak self] in
                        await self?.pasteboard.writeString(combined)
                        self?.statusMessage = "Copied expression and answer."
                    }
                }
            case "openCalculator":
                guard let result = activeCalculatorResult else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await pasteboard.writeString(result.formattedPrimaryValue)
                    await openCompanionApplication(
                        bundleIdentifier: "com.apple.calculator",
                        failureMessage: "Couldn’t open Calculator."
                    )
                }
            case "addToNote":
                guard let result = activeCalculatorResult else { return }
                let combined = "\(result.displayExpression) = \(result.formattedPrimaryValue)"
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await pasteboard.writeString(combined)
                    await openCompanionApplication(
                        bundleIdentifier: "com.apple.Notes",
                        failureMessage: "Couldn’t open Notes."
                    )
                }
            default:
                break
            }
        }
    }

    private func performCalculatorPrimary(resultID: String) {
        guard let result = activeCalculatorResult, result.id.rawValue == resultID else {
            if case .copyText(let value) = selectedItem?.action {
                Task { @MainActor [weak self] in
                    await self?.pasteboard.writeString(value)
                    self?.dismiss()
                }
            }
            return
        }
        calculatorSession.recordSuccess(result)
        Task { @MainActor [weak self] in
            await self?.pasteboard.writeString(result.formattedPrimaryValue)
            self?.statusMessage = "Copied answer."
        }
    }

    func editCalculatorQuestion(resultID: String) {
        guard let result = activeCalculatorResult, result.id.rawValue == resultID else { return }
        query = result.originalInput
        requestSearchFocus()
    }

    func copyCalculatorAnswer(resultID: String) {
        guard let result = activeCalculatorResult, result.id.rawValue == resultID else { return }
        calculatorSession.recordSuccess(result)
        Task { @MainActor [weak self] in
            await self?.pasteboard.writeString(result.formattedPrimaryValue)
            self?.statusMessage = "Copied answer."
        }
    }

    private func supportsOpenInCalculator(_ value: CalculatorValue) -> Bool {
        switch value {
        case .decimal, .double, .measurement, .currency:
            return true
        case .date, .timeZoneInstant, .text:
            return false
        }
    }

    func activate(_ commandID: CommandID) {
        guard let command = catalog.command(for: commandID) else {
            statusMessage = "Command is not registered."
            return
        }
        switch command.activate(runtime: runtime) {
        case .pushView(let id):
            push(commandID: id)
        case .openSettings:
            onDismiss()
            onOpenSettings()
        case .dismiss:
            dismiss()
        case .message(let message):
            statusMessage = message
        }
    }

    func push(commandID: CommandID) {
        guard let command = catalog.command(for: commandID) else { return }
        route = .command(commandID)
        if commandID == BuiltInCommandID.clipboardHistory {
            clipboardViewModel = ClipboardHistoryViewModel(
                store: clipboardHistoryStore,
                onGoBack: { [weak self] in self?.goBack() },
                onDismiss: { [weak self] in self?.dismiss() }
            )
        } else if commandID == BuiltInCommandID.searchFiles {
            fileSearchViewModel = FileSearchViewModel(
                searchService: fileSearchService,
                urlOpener: urlOpener,
                fileRevealer: fileRevealer,
                fileActionService: fileActionService,
                finderInfoPresenter: finderInfoPresenter,
                pasteboard: pasteboard,
                onGoBack: { [weak self] in self?.goBack() },
                onDismiss: { [weak self] in self?.dismiss() },
                onOpenSettings: { [weak self] in
                    self?.dismiss()
                    self?.onOpenSettings()
                }
            )
        }
        statusMessage = nil
        _ = command
    }

    func goBack() {
        fileSearchViewModel?.stop()
        route = .root
        clipboardViewModel = nil
        fileSearchViewModel = nil
        uninstallViewModel = nil
        statusMessage = nil
        requestSearchFocus()
    }

    func dismiss() {
        onDismiss()
    }

    func handleEscape() -> Bool {
        if showsApplicationActionsPanel {
            dismissApplicationActionsPanel()
            return true
        }
        switch route {
        case .command, .uninstallReview:
            goBack()
            return true
        case .root:
            return false
        }
    }

    /// Awaits the in-flight search task (tests).
    func flushSearchForTesting() async {
        searchTask?.cancel()
        await performSearch(queryText: query, loadApplicationsIfNeeded: true)
    }

    /// Ends results-scroll hover suppression immediately (tests).
    func flushResultsScrollingForTesting() {
        resultsScrollEndTask?.cancel()
        resultsScrollEndTask = nil
        isResultsScrolling = false
        if inputDevice == .pointer, let hoveredID {
            select(hoveredID)
        }
    }

    func openApplication(bundleIdentifier: String) async {
        do {
            try await applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
            recordApplicationOpen(bundleIdentifier: bundleIdentifier)
            dismiss()
        } catch {
            statusMessage = "Couldn’t open that application."
        }
    }

    private func openCompanionApplication(bundleIdentifier: String, failureMessage: String) async {
        do {
            try await applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
            statusMessage = "Copied."
        } catch {
            statusMessage = failureMessage
        }
    }

    func scheduleSearch(loadApplicationsIfNeeded: Bool = false) {
        searchTask?.cancel()
        calculatorSuggestion = nil
        autocompleteCompletion = nil
        autocompleteActionLabel = nil
        autocompleteSuffix = ""
        let queryText = query
        searchTask = Task { @MainActor [weak self] in
            await self?.performSearch(
                queryText: queryText,
                loadApplicationsIfNeeded: loadApplicationsIfNeeded
            )
        }
    }

    private func performSearch(queryText: String, loadApplicationsIfNeeded: Bool) async {
        if loadApplicationsIfNeeded || didLoadApplications == false {
            let apps = await applicationQuery.installedApplications()
            guard Task.isCancelled == false else { return }
            cachedApplications = apps.map {
                InstalledApplicationSnapshot(
                    bundleIdentifier: $0.bundleIdentifier,
                    name: $0.name,
                    path: $0.path
                )
            }
            didLoadApplications = true
        }

        let service = makeSearchService()
        let searchQuery = SearchQuery(text: queryText, limit: nil)
        let calcContext = calculatorSession.makeContext()
        do {
            async let calcOutcome = calculator.evaluate(queryText, context: calcContext)
            async let calcSuggestion = calculator.suggestion(for: queryText, context: calcContext)
            async let searchResult = service.search(searchQuery)

            let outcome = await calcOutcome
            let suggestion = await calcSuggestion
            let result = try await searchResult
            guard Task.isCancelled == false else { return }
            calculatorSuggestion = suggestion

            var mapped = result.items.compactMap { mapSearchItem($0) }
            let previousSelected = selectedID
            if let calcItem = mapCalculatorOutcome(outcome, queryText: queryText) {
                mapped.insert(calcItem, at: 0)
            } else {
                activeCalculatorResult = nil
            }
            applySearchResult(items: mapped, queryText: queryText)
            // Prefer keeping selection when the calculator card appears/disappears.
            if let previousSelected, mapped.contains(where: { $0.id == previousSelected }) {
                selectedID = previousSelected
            } else if mapped.first?.section == .calculator {
                selectedID = mapped.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false else { return }
            calculatorSuggestion = nil
            applySearchResult(items: fallbackItems(matching: queryText), queryText: queryText)
        }
    }

    private func mapCalculatorOutcome(
        _ outcome: CalculatorEvaluationOutcome,
        queryText: String
    ) -> LauncherItem? {
        switch outcome {
        case .notCalculator, .incomplete:
            activeCalculatorResult = nil
            return nil
        case .failure(let error):
            activeCalculatorResult = nil
            // Only show failure rows when the query clearly looks calculator-shaped.
            guard queryText.contains(where: { "+-*/^%".contains($0) })
                || queryText.lowercased().contains("sqrt")
                || queryText.lowercased().contains("sin")
            else {
                return nil
            }
            return LauncherItem(
                id: "calculator-error",
                section: .calculator,
                title: error.message,
                subtitle: queryText,
                systemImage: "function",
                badge: .calculator,
                keywords: [],
                action: .placeholder(message: error.message)
            )
        case .success(let result):
            activeCalculatorResult = result
            return LauncherItem(
                id: "calculator:\(result.id.rawValue)",
                section: .calculator,
                title: result.formattedPrimaryValue,
                subtitle: result.displayExpression.isEmpty ? result.originalInput : result.displayExpression,
                systemImage: "function",
                badge: .calculator,
                keywords: [],
                action: .calculatorPrimary(resultID: result.id.rawValue)
            )
        }
    }

    private func makeSearchService() -> CompositeSearchService {
        let preferences = applicationPreferencesStore.load()
        return CompositeSearchService(
            providers: [
                CommandSearchProvider(manifests: catalog.allManifests()),
                ApplicationSearchProvider(
                    applications: cachedApplications,
                    favoriteBundleIDs: preferences.favoriteBundleIDs,
                    disabledBundleIDs: preferences.disabledBundleIDs,
                    ranking: preferences.ranking
                ),
                PlaceholderSearchProvider(placeholders: LauncherPlaceholderCatalog.searchRecords)
            ]
        )
    }

    private func mapSearchItem(_ item: SearchItem) -> LauncherItem? {
        switch item.providerID {
        case BuiltInSearchProviderID.commands:
            guard let manifest = catalog.allManifests().first(where: { $0.id.rawValue == item.id }) else {
                return nil
            }
            let badge: LauncherItemBadge = manifest.id == BuiltInCommandID.openSettings ? .settings : .command
            return LauncherItem(
                id: item.id,
                section: .suggestions,
                title: manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                badge: badge,
                keywords: manifest.keywords,
                action: .openCommand(manifest.id)
            )
        case BuiltInSearchProviderID.applications:
            let path = cachedApplications.first(where: { $0.bundleIdentifier == item.id })?.path
            let icon: LauncherItemIcon
            if let path, path.isEmpty == false {
                icon = .application(path: path)
            } else {
                icon = .system("app.fill")
            }
            let preferences = applicationPreferencesStore.load()
            let badge: LauncherItemBadge
            if preferences.isDisabled(item.id) {
                badge = .disabled
            } else if preferences.isFavorite(item.id) {
                badge = .favorite
            } else {
                badge = .application
            }
            return LauncherItem(
                id: "app:\(item.id)",
                section: .applications,
                title: item.title,
                subtitle: item.subtitle,
                icon: icon,
                badge: badge,
                keywords: [item.title],
                action: .openApplication(bundleIdentifier: item.id)
            )
        case BuiltInSearchProviderID.placeholders:
            guard let record = LauncherPlaceholderCatalog.searchRecords.first(where: { $0.id == item.id }) else {
                return nil
            }
            return LauncherItem(
                id: record.id,
                section: record.section,
                title: record.title,
                subtitle: record.subtitle,
                systemImage: record.systemImage,
                badge: record.badge,
                keywords: record.keywords,
                action: .placeholder(message: record.message)
            )
        default:
            return nil
        }
    }

    private func fallbackItems(matching queryText: String) -> [LauncherItem] {
        let commandItems = catalog.allManifests().map { manifest -> LauncherItem in
            let badge: LauncherItemBadge = manifest.id == BuiltInCommandID.openSettings ? .settings : .command
            return LauncherItem(
                id: manifest.id.rawValue,
                section: .suggestions,
                title: manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                badge: badge,
                keywords: manifest.keywords,
                action: .openCommand(manifest.id)
            )
        }
        return (commandItems + placeholderItems).filter { $0.matches(query: queryText) }
    }

    private func applySearchResult(items: [LauncherItem], queryText: String) {
        rootItems = items
        if items.isEmpty {
            selectedID = nil
        } else if items.contains(where: { $0.id == selectedID }) == false {
            selectedID = items.first?.id
        }
        refreshAutocomplete(queryText: queryText)
    }

    private func refreshAutocomplete(queryText: String? = nil) {
        let trimmed = (queryText ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            autocompleteSuffix = ""
            autocompleteCompletion = nil
            autocompleteActionLabel = nil
            return
        }
        if let suggestion = calculatorSuggestion,
           suggestion.completedInput.caseInsensitiveCompare(trimmed) != .orderedSame {
            autocompleteCompletion = suggestion.completedInput
            autocompleteSuffix = suggestion.suffix(after: trimmed) ?? ""
            autocompleteActionLabel = suggestion.kind == .unitConversion ? "Tab to convert" : "Tab to complete"
            return
        }
        let needle = trimmed.lowercased()
        guard let match = rootItems.first(where: { $0.title.lowercased().hasPrefix(needle) && $0.title.count > trimmed.count }) else {
            autocompleteSuffix = ""
            autocompleteCompletion = nil
            autocompleteActionLabel = nil
            return
        }
        let suffix = String(match.title.dropFirst(trimmed.count))
        autocompleteSuffix = suffix
        autocompleteCompletion = match.title
        autocompleteActionLabel = "Tab to complete"
    }
}
