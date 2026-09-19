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

private enum InlineFileSearchOutcome: Sendable {
    case results([FileSearchItem])
    case permissionRequired
    case unavailable
}

@Observable
@MainActor
final class LauncherViewModel {
    private let applicationRegistry: LauncherApplicationRegistry
    @ObservationIgnored
    private let clipboardHistoryStore: ClipboardHistoryStore
    @ObservationIgnored
    private let fileSearchService: any FileSearching
    @ObservationIgnored
    private let urlOpener: any URLOpening
    @ObservationIgnored
    private let applicationOpener: any ApplicationOpening
    @ObservationIgnored
    private let commandCoordinator: (any SharedCommandExecutionCoordinating)?
    @ObservationIgnored
    let commandWheelAssignmentStore: (any CommandWheelAssignmentStoring)?
    @ObservationIgnored
    private let invocationContextProvider: @MainActor (CommandInvocationSource) -> CommandInvocationContext
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
    let colorSearch: ColorSearchModel

    var query: String = "" {
        didSet {
            guard oldValue != query, suppressesSearchScheduling == false else { return }
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
    var route: LauncherRoute = .root {
        didSet {
            if oldValue != route {
                cancelPendingRootConfirmation()
                colorSearch.dismissActions()
            }
        }
    }
    private(set) var activeApplication: LauncherApplicationSession?
    var uninstallViewModel: ApplicationUninstallViewModel?
    var applicationAliasEditor: ApplicationAliasEditorModel?
    var installedApplicationShortcutEditor: InstalledApplicationShortcutEditorModel?
    @ObservationIgnored
    let saveInstalledApplicationShortcut: ((String, LauncherHotKey?) -> String?)?
    @ObservationIgnored
    let onInstalledApplicationPreferencesChange: () -> Void
    @ObservationIgnored
    let onInstalledShortcutRecordingChange: (Bool) -> Void
    @ObservationIgnored
    let installedApplicationShortcutIssue: (String) -> String?
    /// When non-nil, the application actions panel is presented for this bundle ID.
    var applicationActionsTargetBundleID: String?
    var applicationActionsQuery: String = ""
    /// A registered command whose contextual launcher actions are visible.
    var registeredCommandActionsTarget: LauncherCommandWheelActionTarget?
    var registeredCommandActionsQuery: String = ""
    /// Item-driven assignment sheet for one exact shared command reference.
    var commandWheelAssignmentModel: CommandWheelAssignmentModel?
    @ObservationIgnored
    private var resultsScrollEndTask: Task<Void, Never>?

    var onDismiss: () -> Void
    var onOpenDocumentation: () -> Void
    var onOpenSettings: () -> Void
    var onOpenAISettings: () -> Void
    var onOpenPermissionsSettings: () -> Void
    var onOpenCommandWheelSettings: (CommandWheelSlotLocation) -> Void
    var onQuit: () -> Void

    @ObservationIgnored
    private var searchTask: Task<Void, Never>?
    @ObservationIgnored
    private var searchRequestID = UUID()
    @ObservationIgnored
    private var publishedSearchRequestID: UUID?
    @ObservationIgnored
    private var rootConfirmationID: UUID?
    @ObservationIgnored
    private var rootConfirmationTask: Task<Void, Never>?
    @ObservationIgnored
    private var rootConfirmationWaiter: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    private var isExecutingRootConfirmation = false
    @ObservationIgnored
    private var suppressesSearchScheduling = false
    @ObservationIgnored
    var commandWheelAssignmentPreparationTask: Task<Void, Never>?
    @ObservationIgnored
    var commandWheelAssignmentPreparationID: UUID?
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
        commandCoordinator: (any SharedCommandExecutionCoordinating)? = nil,
        commandWheelAssignmentStore: (any CommandWheelAssignmentStoring)? = nil,
        invocationContextProvider: @escaping @MainActor (CommandInvocationSource) -> CommandInvocationContext = {
            CommandInvocationContext(source: $0)
        },
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
        onOpenDocumentation: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onOpenAISettings: (() -> Void)? = nil,
        onOpenPermissionsSettings: (() -> Void)? = nil,
        onOpenCommandWheelSettings: @escaping (CommandWheelSlotLocation) -> Void = { _ in },
        onQuit: @escaping () -> Void = {},
        saveInstalledApplicationShortcut: ((String, LauncherHotKey?) -> String?)? = nil,
        onInstalledApplicationPreferencesChange: @escaping () -> Void = {},
        onInstalledShortcutRecordingChange: @escaping (Bool) -> Void = { _ in },
        installedApplicationShortcutIssue: @escaping (String) -> String? = { _ in nil }
    ) {
        self.clipboardHistoryStore = clipboardHistoryStore
        self.fileSearchService = fileSearchService
        self.urlOpener = urlOpener
        self.applicationOpener = applicationOpener
        self.commandCoordinator = commandCoordinator
        self.commandWheelAssignmentStore = commandWheelAssignmentStore
        self.invocationContextProvider = invocationContextProvider
        self.applicationQuery = applicationQuery
        self.applicationPreferencesStore = applicationPreferencesStore
        self.fileRevealer = fileRevealer
        self.bundleManager = bundleManager
        self.finderInfoPresenter = finderInfoPresenter
        self.uninstallDiscoverer = uninstallDiscoverer
        self.pasteboard = pasteboard
        self.colorSearch = ColorSearchModel(pasteboard: pasteboard)
        self.calculator = calculator
        self.calculatorSession = calculatorSession
        self.placeholderItems = placeholderItems
        self.onDismiss = onDismiss
        self.onOpenDocumentation = onOpenDocumentation
        self.onOpenSettings = onOpenSettings
        self.onOpenAISettings = onOpenAISettings ?? onOpenSettings
        self.onOpenPermissionsSettings = onOpenPermissionsSettings ?? onOpenSettings
        self.onOpenCommandWheelSettings = onOpenCommandWheelSettings
        self.onQuit = onQuit
        self.saveInstalledApplicationShortcut = saveInstalledApplicationShortcut
        self.onInstalledApplicationPreferencesChange = onInstalledApplicationPreferencesChange
        self.onInstalledShortcutRecordingChange = onInstalledShortcutRecordingChange
        self.installedApplicationShortcutIssue = installedApplicationShortcutIssue
        self.applicationRegistry = applicationRegistry ?? .makeBuiltIn(
            clipboardHistoryStore: clipboardHistoryStore,
            fileSearchServices: FileSearchApplicationServices(
                searchService: fileSearchService,
                urlOpener: urlOpener,
                fileRevealer: fileRevealer,
                fileActionService: fileActionService,
                finderInfoPresenter: finderInfoPresenter,
                pasteboard: pasteboard
            ),
            calculatorSessionStore: calculatorSession
        )
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
        publishedSearchRequestID = searchRequestID
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
                openAISettings: { [weak self] in
                    self?.dismiss()
                    self?.onOpenAISettings()
                },
                openPermissionsSettings: { [weak self] in
                    self?.dismiss()
                    self?.onOpenPermissionsSettings()
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

    /// Root utility descriptors presented together from the trailing Settings gear menu.
    var appMenuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.settings,
                title: "Settings…",
                keyHint: CommandKeyHint(symbols: ["⌘", ","])
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.documentation,
                title: "Documentation",
                keyHint: CommandKeyHint(symbols: ["⌘", "?"])
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
        if case .colorPrimary = selectedItem?.action { return colorSearch.actions }
        return applicationActions(for: selectedApplicationBundleID).map(\.descriptor)
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
            if case .colorPrimary = selectedItem?.action, colorSearch.result != nil {
                return [
                    CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: "Copy \(colorSearch.selectedFormat.title)", isPrimary: true, keyHint: .return),
                    CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)
                ]
            }
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
        colorSearch.stop()
        cancelPendingRootConfirmation()
        searchTask?.cancel()
        searchTask = nil
        searchRequestID = UUID()
        (fileSearchService as? any FileSearchSessionManaging)?.endFileSearchSession()
        commandWheelAssignmentPreparationTask?.cancel()
        commandWheelAssignmentPreparationTask = nil
        commandWheelAssignmentPreparationID = nil
        resultsScrollEndTask?.cancel()
        resultsScrollEndTask = nil
        suppressesSearchScheduling = true
        query = ""
        suppressesSearchScheduling = false
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
        dismissRegisteredCommandActionsPanel()
        commandWheelAssignmentModel = nil
        applicationAliasEditor = nil
        installedApplicationShortcutEditor?.cancel()
        installedApplicationShortcutEditor = nil
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
        publishedSearchRequestID = searchRequestID
    }

    func select(_ id: String) {
        cancelPendingRootConfirmation()
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
        cancelPendingRootConfirmation()
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
        // One Return intent owns its side effects until execution completes, including a
        // transition into an application. A second Return cannot reuse the pending intent.
        guard rootConfirmationID == nil else { return }
        if case .application = route {
            guard let primaryActionID = activeApplication?.primaryActionID else { return }
            activeApplication?.perform(primaryActionID)
            return
        }
        guard route == .root else { return }
        performWithCurrentRootSelection { [weak self] item in
            await self?.executeRootSelection(item)
        }
    }

    /// Waits for this exact query before an invocation or Actions intent uses its selection.
    /// Repeated presses coalesce, and edits/navigation cancel a not-yet-consumed intent.
    func performWithCurrentRootSelection(_ action: @escaping @MainActor (LauncherItem) async -> Void) {
        guard route == .root, rootConfirmationID == nil else { return }
        let confirmationID = UUID()
        let requestID = searchRequestID
        let submittedQuery = query
        rootConfirmationID = confirmationID
        rootConfirmationTask = Task.immediate { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if rootConfirmationID == confirmationID {
                    rootConfirmationID = nil
                    isExecutingRootConfirmation = false
                }
            }
            if publishedSearchRequestID != requestID {
                await withCheckedContinuation { rootConfirmationWaiter = $0 }
            }
            guard Task.isCancelled == false,
                  rootConfirmationID == confirmationID,
                  searchRequestID == requestID,
                  publishedSearchRequestID == requestID,
                  query == submittedQuery,
                  route == .root,
                  let item = selectedItem else { return }
            isExecutingRootConfirmation = true
            await action(item)
            // Keep rapid submissions in this event-loop turn from applying to the
            // application that the first submission has just presented.
            await Task.yield()
        }
    }

    /// Tests use the same pending-query and execution path as keyboard submission.
    func confirmSelectionAndWaitForTesting() async {
        confirmSelection()
        await waitForConfirmationForTesting()
    }

    /// Observes an already submitted root keyboard intent without submitting another one.
    func waitForConfirmationForTesting() async {
        await rootConfirmationTask?.value
    }

    private func cancelPendingRootConfirmation() {
        // Once execution starts, the press has been consumed. Keep the in-flight guard
        // until it finishes; navigation must not permit a duplicate side effect.
        guard isExecutingRootConfirmation == false else { return }
        rootConfirmationID = nil
        rootConfirmationTask?.cancel()
        let waiter = rootConfirmationWaiter
        rootConfirmationWaiter = nil
        waiter?.resume()
    }

    private func publishSearchReadiness(requestID: UUID, includesFileResults: Bool = false) {
        guard searchRequestID == requestID else { return }
        // If the fast search is empty, a pending Return may still select a file result.
        guard rootItems.isEmpty == false || includesFileResults else { return }
        publishedSearchRequestID = requestID
        let waiter = rootConfirmationWaiter
        rootConfirmationWaiter = nil
        waiter?.resume()
    }

    private func executeRootSelection(_ item: LauncherItem) async {
        switch item.action {
        case .openSettings:
            onDismiss()
            onOpenSettings()
        case .openFileSearchPermissions:
            onDismiss()
            onOpenPermissionsSettings()
        case .dismiss:
            onDismiss()
        case .placeholder(let message):
            statusMessage = message
        case .quitApplication:
            onQuit()
        case .copyText(let value):
            await pasteboard.writeString(value)
            statusMessage = nil
            dismiss()
        case .colorPrimary(let resultID):
            await colorSearch.copyAndWait(resultID: resultID)
        case .calculatorPrimary(let resultID):
            guard let result = activeCalculatorResult, result.id.rawValue == resultID else { return }
            calculatorSession.recordSuccess(result)
            await pasteboard.writeString(result.formattedPrimaryValue)
            statusMessage = "Copied answer."
        case .launchApplication(let applicationID):
            await executeRegisteredApplication(applicationID, source: .search)
        case .executeCommand(let reference):
            await executeRegisteredCommand(reference, source: .search)
        case .openInstalledApplication(let bundleIdentifier):
            await openApplication(bundleIdentifier: bundleIdentifier)
        case .copyClipboardEntry(let id):
            guard let entry = clipboardHistoryStore.entry(id: id) else {
                statusMessage = "That clipboard item is no longer available."
                return
            }
            clipboardHistoryStore.copyToPasteboard(entry)
            dismiss()
        case .openFile(let url):
            do {
                try await urlOpener.openURL(url)
                dismiss()
            } catch {
                statusMessage = "That file couldn’t be opened."
            }
        }
    }

    func performFooterAction(_ id: CommandActionID) {
        if case .application = route {
            activeApplication?.perform(id)
            return
        }
        if CommandlyColorFormat.matching(id) != nil || id == BuiltInCommandActionID.copy {
            performWithCurrentRootSelection { [weak self] item in
                guard let self, case .colorPrimary(let resultID) = item.action else { return }
                if id == BuiltInCommandActionID.copy { colorSearch.copy(resultID: resultID) }
                else { colorSearch.perform(id, resultID: resultID) }
            }
            return
        }
        switch id {
        case BuiltInCommandActionID.documentation:
            onDismiss()
            onOpenDocumentation()
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

    /// Lower-level registered-application presentation used only by the shared executor and
    /// deterministic feature setup. Invocation surfaces should execute a `CommandReference`.
    @discardableResult
    func presentRegisteredApplication(_ applicationID: CommandID) -> CommandResult {
        presentRegisteredCommand(CommandReference(commandID: applicationID))
    }

    /// Presents an application or one of its tools while preserving typed invocation arguments.
    @discardableResult
    func presentRegisteredCommand(_ reference: CommandReference) -> CommandResult {
        guard let applicationID = applicationRegistry.owningApplicationID(
            for: reference.commandID
        ),
        applicationRegistry.isEffectivelyEnabled(reference.commandID),
        let application = applicationRegistry.enabledApplication(for: applicationID) else {
            let message = applicationRegistry.owningApplication(for: reference.commandID) == nil
                ? "Application or tool is not registered."
                : "Application or tool is disabled."
            statusMessage = message
            return .failure(message: message)
        }
        guard let context = applicationContext(for: applicationID) else {
            let message = "Application settings are unavailable."
            statusMessage = message
            return .failure(message: message)
        }
        let launch: LauncherApplicationLaunch
        if reference.commandID == applicationID {
            launch = application.launch(in: context)
        } else {
            launch = application.launch(
                toolID: reference.commandID,
                arguments: reference.arguments,
                in: context
            )
        }
        switch launch {
        case .present(let session):
            activeApplication?.stop()
            activeApplication = session
            route = .application(applicationID)
            statusMessage = nil
            return .success(message: nil)
        case .openSettings:
            onDismiss()
            onOpenSettings()
            return .success(message: nil)
        case .dismiss:
            dismiss()
            return .success(message: nil)
        case .message(let message):
            statusMessage = message
            return .failure(message: message)
        }
    }

    /// Compatibility entry point for feature setup that intentionally bypasses invocation history.
    func launch(_ applicationID: CommandID) {
        _ = presentRegisteredApplication(applicationID)
    }

    /// Executes a registered launcher application through the shared engine.
    func executeRegisteredApplication(
        _ applicationID: CommandID,
        source: CommandInvocationSource
    ) async {
        await executeRegisteredCommand(
            CommandReference(commandID: applicationID),
            source: source
        )
    }

    func executeRegisteredCommand(
        _ reference: CommandReference,
        source: CommandInvocationSource
    ) async {
        guard commandCoordinator != nil else {
            _ = presentRegisteredCommand(reference)
            return
        }
        await executeSharedCommand(
            reference: reference,
            source: source,
            dismissOnSuccess: false
        )
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
        cancelPendingRootConfirmation()
        onDismiss()
    }

    /// Handles Escape for the launcher shell.
    ///
    /// Priority: close overlays → let the active application consume Escape →
    /// leave the application for home → otherwise signal the caller to hide the
    /// launcher window. Returns `true` when the key was consumed inside the
    /// launcher; `false` when the window should hide.
    func handleEscape() -> Bool {
        cancelPendingRootConfirmation()
        if colorSearch.showsActions {
            colorSearch.dismissActions()
            requestSearchFocus()
            return true
        }
        if let editor = installedApplicationShortcutEditor {
            editor.cancel()
            return true
        }
        if applicationAliasEditor != nil {
            applicationAliasEditor = nil
            requestSearchFocus()
            return true
        }
        if showsRegisteredCommandActionsPanel {
            dismissRegisteredCommandActionsPanel()
            return true
        }
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
        let queryText = query
        let requestID = searchRequestID
        let pendingSearch = searchTask
        searchTask = nil
        pendingSearch?.cancel()
        await pendingSearch?.value
        guard searchRequestID == requestID, query == queryText else { return }
        await performSearch(queryText: queryText, requestID: requestID, loadApplicationsIfNeeded: true)
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
        if commandCoordinator != nil {
            await executeSharedCommand(
                reference: BuiltInCommandReference.openInstalledApplication(
                    bundleIdentifier: bundleIdentifier
                ),
                source: .search,
                dismissOnSuccess: true
            )
            return
        }

        do {
            try await applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
            recordApplicationOpen(bundleIdentifier: bundleIdentifier)
            dismiss()
        } catch {
            statusMessage = "Couldn’t open that application."
        }
    }

    private func executeSharedCommand(
        reference: CommandReference,
        source: CommandInvocationSource,
        dismissOnSuccess: Bool
    ) async {
        guard let commandCoordinator else {
            statusMessage = "Command execution is unavailable."
            return
        }

        do {
            let result = try await commandCoordinator.execute(
                reference: reference,
                context: invocationContextProvider(source)
            )
            switch result {
            case .success(let message):
                statusMessage = message
                if dismissOnSuccess { dismiss() }
            case .failure(let message):
                statusMessage = message
            case .cancelled:
                statusMessage = "Command cancelled."
            }
        } catch is CancellationError {
            statusMessage = "Command cancelled."
        } catch let error as SharedCommandExecutionCoordinatorError {
            statusMessage = error.userFacingMessage
        } catch {
            statusMessage = "Command couldn’t be completed."
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
        colorSearch.update(query: query)
        cancelPendingRootConfirmation()
        searchTask?.cancel()
        searchRequestID = UUID()
        let requestID = searchRequestID
        calculatorSuggestion = nil
        autocompleteCompletion = nil
        autocompleteActionLabel = nil
        autocompleteSuffix = ""
        let queryText = query
        searchTask = Task { @MainActor [weak self] in
            await self?.performSearch(
                queryText: queryText,
                requestID: requestID,
                loadApplicationsIfNeeded: loadApplicationsIfNeeded
            )
        }
    }

    private func performSearch(queryText: String, requestID: UUID, loadApplicationsIfNeeded: Bool) async {
        if loadApplicationsIfNeeded || didLoadApplications == false {
            let apps = await applicationQuery.installedApplications()
            guard Task.isCancelled == false, searchRequestID == requestID else { return }
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
        let clipboardEntries = clipboardHistoryStore.searchEntries(
            matching: queryText,
            limit: 6
        )
        let commandMatches = applicationRegistry.commandMatches(queryText)
        do {
            async let calcOutcome = calculator.evaluate(queryText, context: calcContext)
            async let calcSuggestion = calculator.suggestion(for: queryText, context: calcContext)
            async let searchResult = service.search(searchQuery)
            async let fileResults = searchInlineFiles(queryText)

            let outcome = await calcOutcome
            let suggestion = await calcSuggestion
            let result = try await searchResult
            guard Task.isCancelled == false,
                  searchRequestID == requestID,
                  SearchQuery(text: self.query).text == searchQuery.text else {
                return
            }
            calculatorSuggestion = colorSearch.result == nil ? suggestion : nil

            var mapped = result.items.compactMap { mapSearchItem($0) }
            mapped.append(contentsOf: commandMatches.map(mapCommandMatch))
            mapped.append(contentsOf: clipboardEntries.map(mapClipboardEntry))
            let previousSelected = selectedID
            if colorSearch.result == nil, let calcItem = mapCalculatorOutcome(outcome, queryText: queryText) {
                mapped.insert(calcItem, at: 0)
            } else {
                activeCalculatorResult = nil
            }
            if let colorItem = colorSearchItem { mapped.insert(colorItem, at: 0) }
            applySearchResult(items: mapped, queryText: queryText)
            // Prefer keeping selection when the calculator card appears/disappears.
            if let previousSelected, mapped.contains(where: { $0.id == previousSelected }) {
                selectedID = previousSelected
            } else if mapped.first?.section == .calculator || mapped.first?.section == .color {
                selectedID = mapped.first?.id
            }
            publishSearchReadiness(requestID: requestID)

            // File lookup is deliberately debounced, so publish the low-latency command,
            // application, calculator, and clipboard results before waiting for it.
            let fileOutcome = await fileResults
            guard Task.isCancelled == false,
                  searchRequestID == requestID,
                  SearchQuery(text: self.query).text == searchQuery.text else {
                return
            }
            switch fileOutcome {
            case .results(let files):
                guard files.isEmpty == false else {
                    publishSearchReadiness(requestID: requestID, includesFileResults: true)
                    return
                }
                mapped.append(contentsOf: files.map(mapFileSearchItem))
            case .permissionRequired:
                mapped.append(
                    LauncherItem(
                        id: "file-search-permission-required",
                        section: .files,
                        title: "Choose folders for File Search",
                        subtitle: "Grant access in Settings → Permissions",
                        systemImage: "folder.badge.questionmark",
                        badge: .file,
                        keywords: [],
                        action: .openFileSearchPermissions
                    )
                )
            case .unavailable:
                mapped.append(
                    LauncherItem(
                        id: "file-search-unavailable",
                        section: .files,
                        title: "File Search is unavailable",
                        subtitle: "Open File Search to inspect or rebuild its local index",
                        systemImage: "exclamationmark.magnifyingglass",
                        badge: .file,
                        keywords: [],
                        action: .launchApplication(BuiltInCommandID.searchFiles)
                    )
                )
            }
            applySearchResult(items: mapped, queryText: queryText)
            publishSearchReadiness(requestID: requestID, includesFileResults: true)
        } catch is CancellationError {
            if searchRequestID == requestID { cancelPendingRootConfirmation() }
            return
        } catch {
            guard Task.isCancelled == false, searchRequestID == requestID else { return }
            calculatorSuggestion = nil
            var fallback = fallbackItems(matching: queryText)
            if let colorItem = colorSearchItem { fallback.insert(colorItem, at: 0) }
            applySearchResult(items: fallback, queryText: queryText)
            publishSearchReadiness(requestID: requestID, includesFileResults: true)
        }
    }

    private func searchInlineFiles(_ queryText: String) async -> InlineFileSearchOutcome {
        let query = SearchQuery(text: queryText, limit: 10)
        guard query.isEmpty == false else { return .results([]) }
        do {
            try await ContinuousClock().sleep(for: .milliseconds(80))
            try Task.checkCancellation()
            return .results(
                try await fileSearchService.search(
                    FileSearchRequest(query: query, category: .all)
                )
            )
        } catch is CancellationError {
            return .results([])
        } catch FileSearchError.noAuthorizedScopes {
            return .permissionRequired
        } catch {
            return .unavailable
        }
    }

    private var colorSearchItem: LauncherItem? {
        guard let result = colorSearch.result else { return nil }
        return LauncherItem(
            id: result.id, section: .color, title: result.color.formatted(colorSearch.selectedFormat),
            subtitle: "Convert and copy a color", systemImage: "paintpalette", badge: .color,
            keywords: [], action: .colorPrimary(resultID: result.id)
        )
    }

    private func mapCommandMatch(_ match: LauncherApplicationCommandMatch) -> LauncherItem {
        LauncherItem(
            id: "typed-command:\(match.id)",
            section: .commands,
            title: match.title,
            subtitle: match.subtitle,
            systemImage: match.systemImage,
            badge: .command,
            keywords: [],
            action: .executeCommand(match.reference)
        )
    }

    private func mapClipboardEntry(_ entry: ClipboardHistoryEntry) -> LauncherItem {
        LauncherItem(
            id: "clipboard:\(entry.id.uuidString.lowercased())",
            section: .clipboard,
            title: entry.displayTitle,
            subtitle: entry.sourceAppName ?? entry.contentType.title,
            systemImage: entry.contentType.systemImage,
            badge: .clipboard,
            keywords: [],
            action: .copyClipboardEntry(entry.id)
        )
    }

    private func mapFileSearchItem(_ item: FileSearchItem) -> LauncherItem {
        LauncherItem(
            id: "file:\(item.id)",
            section: .files,
            title: item.name,
            subtitle: item.parentPath,
            systemImage: item.kind == .folder ? "folder" : "doc",
            badge: .file,
            keywords: item.tags,
            action: .openFile(item.url)
        )
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
                    ranking: preferences.ranking,
                    aliases: preferences.aliases
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
            let definition = applicationRegistry.definition(for: manifest.id)
            let isTool = definition?.kind == .tool
            let badge: LauncherItemBadge
            if manifest.id == BuiltInCommandID.openSettings {
                badge = .settings
            } else {
                badge = isTool ? .tool : .command
            }
            return LauncherItem(
                id: item.id,
                section: isTool ? .tools : .suggestions,
                title: manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                badge: badge,
                keywords: manifest.keywords,
                action: isTool
                    ? .executeCommand(CommandReference(commandID: manifest.id))
                    : .launchApplication(manifest.id)
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
            // Rebuilt from the catalog rather than from the search snapshot, so a row that is
            // backed by a real action does not come back as a placeholder.
            return LauncherPlaceholderCatalog.item(id: item.id)
        default:
            return nil
        }
    }

    private func fallbackItems(matching queryText: String) -> [LauncherItem] {
        let commandItems = applicationRegistry.allManifests().map { manifest -> LauncherItem in
            let isTool = applicationRegistry.definition(for: manifest.id)?.kind == .tool
            let badge: LauncherItemBadge = manifest.id == BuiltInCommandID.openSettings
                ? .settings
                : (isTool ? .tool : .command)
            return LauncherItem(
                id: manifest.id.rawValue,
                section: isTool ? .tools : .suggestions,
                title: manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                badge: badge,
                keywords: manifest.keywords,
                action: isTool
                    ? .executeCommand(CommandReference(commandID: manifest.id))
                    : .launchApplication(manifest.id)
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
        guard let match = rootItems.first(where: {
            $0.section != .clipboard
                && $0.section != .color
                && $0.section != .files
                && $0.title.lowercased().hasPrefix(needle)
                && $0.title.count > trimmed.count
        }) else {
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
