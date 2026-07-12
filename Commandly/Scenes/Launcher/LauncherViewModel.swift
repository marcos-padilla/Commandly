import Foundation
import Observation
import CommandKit
import SearchKit
import Infrastructure
import CalculatorKit
import SwiftUI

/// Navigation stack inside the launcher window.
enum LauncherRoute: Equatable {
    case root
    case command(CommandID)
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
    private let applicationOpener: any ApplicationOpening
    @ObservationIgnored
    private let applicationQuery: any InstalledApplicationQuerying
    @ObservationIgnored
    private let pasteboard: any PasteboardAccessing
    @ObservationIgnored
    private let calculator: any CalculatorEvaluating
    @ObservationIgnored
    private let calculatorSession: CalculatorSessionStore

    private(set) var placeholderItems: [LauncherItem]
    private(set) var rootItems: [LauncherItem] = []
    private(set) var autocompleteSuffix: String = ""
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
    private(set) var statusMessage: String?
    private(set) var shouldScrollToSelection = false
    private(set) var inputDevice: LauncherInputDevice = .pointer
    private var hoveredID: String?
    var route: LauncherRoute = .root
    var clipboardViewModel: ClipboardHistoryViewModel?

    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    @ObservationIgnored
    private var searchTask: Task<Void, Never>?
    @ObservationIgnored
    private var cachedApplications: [InstalledApplicationSnapshot] = []
    @ObservationIgnored
    private var didLoadApplications = false

    init(
        catalog: CommandCatalog = .makeBuiltIn(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        applicationOpener: any ApplicationOpening = NoOpApplicationOpener(),
        applicationQuery: any InstalledApplicationQuerying = InMemoryInstalledApplicationQuery(),
        pasteboard: any PasteboardAccessing = SystemPasteboard(),
        calculator: any CalculatorEvaluating = CalculatorService(),
        calculatorSession: CalculatorSessionStore = CalculatorSessionStore(),
        placeholderItems: [LauncherItem] = LauncherPlaceholderCatalog.nonCommandItems,
        onDismiss: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.catalog = catalog
        self.clipboardHistoryStore = clipboardHistoryStore
        self.applicationOpener = applicationOpener
        self.applicationQuery = applicationQuery
        self.pasteboard = pasteboard
        self.calculator = calculator
        self.calculatorSession = calculatorSession
        self.placeholderItems = placeholderItems
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        applySearchResult(items: fallbackItems(matching: ""), queryText: "")
    }

    var runtime: CommandRuntime {
        CommandRuntime(
            clipboardHistoryStore: clipboardHistoryStore,
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
        }
    }

    var contextSystemImage: String {
        switch route {
        case .root:
            return "command"
        case .command(let id):
            return catalog.command(for: id)?.manifest.systemImage ?? "command"
        }
    }

    var footerActions: [CommandActionDescriptor] {
        switch route {
        case .root:
            let title: String
            switch selectedItem?.action {
            case .openSettings: title = "Open Settings"
            case .openCommand: title = "Open"
            case .openApplication: title = "Open"
            case .dismiss: title = "Close"
            case .placeholder: title = "Preview"
            case .copyText, .calculatorPrimary: title = "Copy"
            case .none: title = "Select"
            }
            return [
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "confirm"),
                    title: title,
                    isPrimary: true,
                    keyHint: .return
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "settings"),
                    title: "Settings",
                    keyHint: CommandKeyHint(symbols: ["⌘", ","])
                ),
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "close"),
                    title: "Close",
                    keyHint: .escape
                )
            ] + calculatorFooterExtras
        case .command:
            return clipboardViewModel?.footerActions
                ?? catalog.command(for: BuiltInCommandID.clipboardHistory)?.manifest.defaultActions
                ?? []
        }
    }

    var menuActions: [CommandActionDescriptor] {
        if activeCalculatorResult != nil, case .root = route {
            return [
                CommandActionDescriptor(
                    id: CommandActionID(rawValue: "copyUnformatted"),
                    title: "Copy Without Formatting"
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
        }
        return clipboardViewModel?.menuActions ?? []
    }

    private var calculatorFooterExtras: [CommandActionDescriptor] {
        guard activeCalculatorResult != nil else { return [] }
        return [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: "insertResult"),
                title: "Insert"
            )
        ]
    }

    var showsActionsMenu: Bool {
        get { clipboardViewModel?.showsActionsMenu ?? false }
        set { clipboardViewModel?.showsActionsMenu = newValue }
    }

    func prepareForPresentation() {
        resetAfterDismiss()
        clipboardHistoryStore.startMonitoring()
        searchFocusEpoch += 1
        scheduleSearch(loadApplicationsIfNeeded: true)
    }

    /// Clears navigation / command-surface state when the launcher is hidden.
    func resetAfterDismiss() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        statusMessage = nil
        shouldScrollToSelection = false
        inputDevice = .pointer
        route = .root
        clipboardViewModel = nil
        activeCalculatorResult = nil
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
        guard let id, inputDevice == .pointer else { return }
        select(id)
    }

    func clearHovered(_ id: String) {
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
        if case .command = route {
            clipboardViewModel?.moveSelection(offset: offset)
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autocompleteSuffix.isEmpty == false else { return }
        query = trimmed + autocompleteSuffix
    }

    func confirmSelection() {
        if case .command = route {
            clipboardViewModel?.perform(BuiltInCommandActionID.copy)
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
            dismiss()
        default:
            confirmSelection()
        }
    }

    func performFooterAction(_ id: CommandActionID) {
        if case .command = route {
            clipboardViewModel?.perform(id)
            return
        }
        switch id.rawValue {
        case "confirm":
            confirmSelection()
        case "settings":
            onDismiss()
            onOpenSettings()
        case "close":
            dismiss()
        case "copyUnformatted":
            if let result = activeCalculatorResult {
                Task { @MainActor [weak self] in
                    await self?.pasteboard.writeString(result.formattedPrimaryValue.replacingOccurrences(of: ",", with: ""))
                    self?.dismiss()
                }
            }
        case "insertResult":
            if let result = activeCalculatorResult {
                query = result.formattedPrimaryValue
            }
        case "copyExpression":
            if let result = activeCalculatorResult {
                let combined = "\(result.displayExpression) = \(result.formattedPrimaryValue)"
                Task { @MainActor [weak self] in
                    await self?.pasteboard.writeString(combined)
                    self?.dismiss()
                }
            }
        default:
            break
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
            self?.dismiss()
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
        }
        statusMessage = nil
        _ = command
    }

    func goBack() {
        route = .root
        clipboardViewModel = nil
        statusMessage = nil
        searchFocusEpoch += 1
    }

    func dismiss() {
        onDismiss()
    }

    func handleEscape() -> Bool {
        if case .command = route {
            goBack()
            return true
        }
        return false
    }

    /// Awaits the in-flight search task (tests).
    func flushSearchForTesting() async {
        searchTask?.cancel()
        await performSearch(queryText: query, loadApplicationsIfNeeded: true)
    }

    private func openApplication(bundleIdentifier: String) async {
        do {
            try await applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
            dismiss()
        } catch {
            statusMessage = "Couldn’t open that application."
        }
    }

    private func scheduleSearch(loadApplicationsIfNeeded: Bool = false) {
        searchTask?.cancel()
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
            async let searchResult = service.search(searchQuery)

            let outcome = await calcOutcome
            let result = try await searchResult
            guard Task.isCancelled == false else { return }

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
        CompositeSearchService(
            providers: [
                CommandSearchProvider(manifests: catalog.allManifests()),
                ApplicationSearchProvider(applications: cachedApplications),
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
            return LauncherItem(
                id: "app:\(item.id)",
                section: .applications,
                title: item.title,
                subtitle: item.subtitle,
                icon: icon,
                badge: .application,
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
            return
        }
        let needle = trimmed.lowercased()
        guard let match = rootItems.first(where: { $0.title.lowercased().hasPrefix(needle) && $0.title.count > trimmed.count }) else {
            autocompleteSuffix = ""
            return
        }
        let suffix = String(match.title.dropFirst(trimmed.count))
        autocompleteSuffix = suffix
    }
}
