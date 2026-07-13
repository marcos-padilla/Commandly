import CommandKit
import Foundation
import Infrastructure
import Observation

enum CalculatorHistoryActionID {
    static let copyExpression = CommandActionID(rawValue: "calculator-history.copy-expression")
}

@Observable
@MainActor
final class CalculatorHistoryViewModel {
    private let sessionStore: CalculatorSessionStore
    private let pasteboard: any PasteboardAccessing
    private let onGoBack: () -> Void
    @ObservationIgnored private var copyTask: Task<Void, Never>?

    var query = "" {
        didSet { refreshSelection() }
    }
    var selectedID: UUID?
    var showsActionsMenu = false
    private(set) var statusMessage: String?
    private(set) var shouldScrollToSelection = false

    init(
        sessionStore: CalculatorSessionStore,
        pasteboard: any PasteboardAccessing,
        onGoBack: @escaping () -> Void
    ) {
        self.sessionStore = sessionStore
        self.pasteboard = pasteboard
        self.onGoBack = onGoBack
        self.selectedID = filteredEntries.first?.id
    }

    var filteredEntries: [CalculatorHistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.isEmpty == false else { return sessionStore.history }
        return sessionStore.history.filter {
            $0.expression.lowercased().contains(needle)
                || $0.formattedValue.lowercased().contains(needle)
        }
    }

    var selectedEntry: CalculatorHistoryEntry? {
        filteredEntries.first(where: { $0.id == selectedID }) ?? filteredEntries.first
    }

    var footerActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy Result",
                isPrimary: true,
                keyHint: .return,
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy Result",
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: CalculatorHistoryActionID.copyExpression,
                title: "Copy Expression",
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.delete,
                title: "Delete",
                isEnabled: selectedEntry != nil
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.clearHistory,
                title: "Clear Calculation History",
                isEnabled: sessionStore.history.isEmpty == false
            )
        ]
    }

    func select(_ id: UUID) {
        selectedID = id
        shouldScrollToSelection = false
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        guard let nextID = LauncherListSelection.nextID(
            in: filteredEntries,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        ) else { return }
        selectedID = nextID
        shouldScrollToSelection = true
        statusMessage = nil
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case BuiltInCommandActionID.copy:
            copySelected(expressionOnly: false)
        case CalculatorHistoryActionID.copyExpression:
            copySelected(expressionOnly: true)
        case BuiltInCommandActionID.delete:
            guard let id = selectedEntry?.id else { return }
            sessionStore.removeHistoryEntry(id: id)
            refreshSelection()
            statusMessage = "Calculation removed."
            showsActionsMenu = false
        case BuiltInCommandActionID.clearHistory:
            sessionStore.clearHistory()
            selectedID = nil
            statusMessage = "Calculation history cleared."
            showsActionsMenu = false
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            onGoBack()
        default:
            break
        }
    }

    func goBack() {
        onGoBack()
    }

    func handleEscape() -> Bool {
        guard query.isEmpty == false else { return false }
        query = ""
        return true
    }

    func stop() {
        copyTask?.cancel()
        copyTask = nil
    }

    func flushCopyForTesting() async {
        await copyTask?.value
    }

    private func copySelected(expressionOnly: Bool) {
        guard let entry = selectedEntry else { return }
        let value = expressionOnly ? entry.expression : entry.formattedValue
        copyTask?.cancel()
        copyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await pasteboard.writeString(value)
            guard Task.isCancelled == false else { return }
            statusMessage = expressionOnly ? "Expression copied." : "Result copied."
            showsActionsMenu = false
        }
    }

    private func refreshSelection() {
        selectedID = LauncherListSelection.resolvedID(
            in: filteredEntries,
            selectedID: selectedID,
            id: \.id
        )
    }
}
