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
    case application(CommandID)
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
    private let applicationRegistry: LauncherApplicationRegistry
    @ObservationIgnored
    private let clipboardHistoryStore: ClipboardHistoryStore
    @ObservationIgnored
    private let applicationOpener: any ApplicationOpening
    @ObservationIgnored
    private let applicationQuery: any InstalledApplicationQuerying
    @ObservationIgnored
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored
    let fileRevealer: any FileRevealing
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
    private(set) var activeApplication: LauncherApplicationSession?
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
        applicationRegistry: LauncherApplicationRegistry? = nil,
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
        self.clipboardHistoryStore = clipboardHistoryStore
        self.applicationOpener = applicationOpener
        self.applicationQuery = applicationQuery
        self.applicationPreferencesStore = applicationPreferencesStore
        self.fileRevealer = fileRevealer
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
        self.applicationRegistry = applicationRegistry ?? .makeBuiltIn(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchServices: FileSearchApplicationServices(
                searchService: fileSearchService,
                urlOpener: urlOpener,
                fileRevealer: fileRevealer,
                fileActionService: fileActionService,
                finderInfoPresenter: finderInfoPresenter,
                pasteboard: pasteboard
            )
        )
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
    }

    private func applicationContext(for applicationID: CommandID) -> LauncherApplicationContext? {
        guard let settings = applicationRegistry.resolvedSettings(for: applicationID) else {
            return nil
        }
        return LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: { [weak self] in self?.dismiss() },
                openSettings: { [weak self] in
                    self?.dismiss()
                    self?.onOpenSettings()
                },
                goBack: { [weak self] in self?.goBack() }
            ),
            settings: settings
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
        case .application(let id):
            return applicationRegistry.definition(for: id)?.title ?? "Application"
        case .uninstallReview:
            return uninstallViewModel?.applicationName ?? "Uninstall"
        }
    }

    var contextSystemImage: String {
        switch route {
        case .root:
            return "command"
        case .application(let id):
            return applicationRegistry.definition(for: id)?.systemImage ?? "square.grid.2x2"
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
        guard case .openInstalledApplication(let bundleID) = selectedItem?.action else { return nil }
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
        case .application:
            return activeApplication?.footerActions ?? []
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
        return activeApplication?.menuActions ?? []
    }

    var showsActionsMenu: Bool {
        get { activeApplication?.showsActionsMenu ?? false }
        set {
            activeApplication?.showsActionsMenu = newValue
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
        activeApplication?.stop()
        activeApplication = nil
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
        if case .application = route {
            activeApplication?.moveSelection(offset: offset)
            return
        }
        let list = rootItems
        guard let nextID = LauncherListSelection.nextID(
            in: list,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        ) else { return }
        inputDevice = .keyboard
        shouldScrollToSelection = true
        selectedID = nextID
        statusMessage = nil
        refreshAutocomplete()
    }

    func acceptAutocomplete() {
        guard let autocompleteCompletion else { return }
        query = autocompleteCompletion
    }

    func confirmSelection() {
        if case .application = route {
            guard let primaryActionID = activeApplication?.primaryActionID else { return }
            activeApplication?.perform(primaryActionID)
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
        case .launchApplication(let applicationID):
            launch(applicationID)
        case .openInstalledApplication(let bundleIdentifier):
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
        if case .application = route {
            guard let primaryActionID = activeApplication?.primaryActionID else { return }
            activeApplication?.perform(primaryActionID)
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
        if case .application = route {
            activeApplication?.perform(id)
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

    func launch(_ applicationID: CommandID) {
        guard let application = applicationRegistry.enabledApplication(for: applicationID) else {
            statusMessage = applicationRegistry.application(for: applicationID) == nil
                ? "Application is not registered."
                : "Application is disabled."
            return
        }
        guard let context = applicationContext(for: applicationID) else {
            statusMessage = "Application settings are unavailable."
            return
        }
        switch application.launch(in: context) {
        case .present(let session):
            activeApplication?.stop()
            activeApplication = session
            route = .application(applicationID)
            statusMessage = nil
        case .openSettings:
            onDismiss()
            onOpenSettings()
        case .dismiss:
            dismiss()
        case .message(let message):
            statusMessage = message
        }
    }

    /// Rebuilds root discovery after application preferences change.
    func applicationPreferencesDidChange() {
        guard route == .root else {
            if case .application(let id) = route,
               applicationRegistry.isEffectivelyEnabled(id) == false {
                goBack()
            }
            return
        }
        scheduleSearch(loadApplicationsIfNeeded: false)
    }

    /// Returns the active application's strongly typed model when a caller needs feature-specific
    /// setup, such as deterministic UI validation.
    func activeApplicationModel<Model>(as type: Model.Type = Model.self) -> Model? {
        activeApplication?.model(as: type)
    }

    func goBack() {
        activeApplication?.stop()
        route = .root
        activeApplication = nil
        uninstallViewModel = nil
        statusMessage = nil
        // Clear residual root search so Esc on home can hide immediately
        // (instead of only clearing the query that launched the application).
        query = ""
        requestSearchFocus()
    }

    func dismiss() {
        onDismiss()
    }

    /// Handles Escape for the launcher shell.
    ///
    /// Priority: close overlays → let the active application consume Escape →
    /// leave the application for home → otherwise signal the caller to hide the
    /// launcher window. Returns `true` when the key was consumed inside the
    /// launcher; `false` when the window should hide.
    func handleEscape() -> Bool {
        if showsApplicationActionsPanel {
            dismissApplicationActionsPanel()
            return true
        }
        if showsActionsMenu {
            showsActionsMenu = false
            return true
        }
        switch route {
        case .application:
            if activeApplication?.handleEscape() == true {
                return true
            }
            goBack()
            return true
        case .uninstallReview:
            goBack()
            return true
        case .root:
            if query.isEmpty == false {
                query = ""
                return true
            }
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
                CommandSearchProvider(manifests: applicationRegistry.allManifests()),
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
            guard let manifest = applicationRegistry.allManifests().first(where: { $0.id.rawValue == item.id }) else {
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
                action: .launchApplication(manifest.id)
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
                action: .openInstalledApplication(bundleIdentifier: item.id)
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
        let commandItems = applicationRegistry.allManifests().map { manifest -> LauncherItem in
            let badge: LauncherItemBadge = manifest.id == BuiltInCommandID.openSettings ? .settings : .command
            return LauncherItem(
                id: manifest.id.rawValue,
                section: .suggestions,
                title: manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                badge: badge,
                keywords: manifest.keywords,
                action: .launchApplication(manifest.id)
            )
        }
        return (commandItems + placeholderItems).filter { $0.matches(query: queryText) }
    }

    private func applySearchResult(items: [LauncherItem], queryText: String) {
        rootItems = items
        selectedID = LauncherListSelection.resolvedID(
            in: items,
            selectedID: selectedID,
            id: \.id
        )
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
