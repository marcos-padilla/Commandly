import CommandKit
import Foundation
import Observation

enum TimersActionID {
    static let beginNew = CommandActionID(rawValue: "timers.new")
    static let startDraft = CommandActionID(rawValue: "timers.start-draft")
    static let cancelDraft = CommandActionID(rawValue: "timers.cancel-draft")
    static let startFocus = CommandActionID(rawValue: "timers.start-focus")
    static let startBreak = CommandActionID(rawValue: "timers.start-break")
    static let startSelected = CommandActionID(rawValue: "timers.start-selected")
    static let pauseSelected = CommandActionID(rawValue: "timers.pause-selected")
    static let resetSelected = CommandActionID(rawValue: "timers.reset-selected")
    static let deleteSelected = CommandActionID(rawValue: "timers.delete-selected")
    static let toggleSound = CommandActionID(rawValue: "timers.toggle-sound")
}

enum TimerPreset: String, CaseIterable, Identifiable, Sendable {
    case focus
    case shortBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        }
    }

    var minutes: Int {
        switch self {
        case .focus: return 25
        case .shortBreak: return 5
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "scope"
        case .shortBreak: return "cup.and.saucer.fill"
        }
    }
}

enum TimerFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case running
    case paused
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Timers"
        case .running: return "Running"
        case .paused: return "Paused & Ready"
        case .completed: return "Completed"
        }
    }

    func matches(_ phase: CountdownTimerPhase) -> Bool {
        switch self {
        case .all: return true
        case .running: return phase == .running
        case .paused: return phase == .paused || phase == .ready
        case .completed: return phase == .completed
        }
    }
}

@Observable
@MainActor
final class TimersViewModel {
    private let store: TimerStore
    private let onGoBack: () -> Void

    var query = "" {
        didSet { refreshSelection() }
    }
    var filter: TimerFilter = .all {
        didSet { refreshSelection() }
    }
    var selectedID: UUID?
    var showsActionsMenu = false
    var draftName = TimerPreset.focus.title
    var draftMinutes = TimerPreset.focus.minutes
    private(set) var isCreating: Bool
    private(set) var statusMessage: String?

    init(store: TimerStore, onGoBack: @escaping () -> Void) {
        self.store = store
        self.onGoBack = onGoBack
        self.isCreating = store.timers.isEmpty
        self.selectedID = store.timers.first?.id
        store.refresh()
    }

    var allTimers: [CountdownTimer] {
        store.timers
    }

    var filteredTimers: [CountdownTimer] {
        let activeFilter = filter
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.timers.filter { timer in
            guard activeFilter.matches(timer.phase) else { return false }
            guard needle.isEmpty == false else { return true }
            return timer.name.lowercased().contains(needle)
                || phaseTitle(for: timer.phase).lowercased().contains(needle)
        }
    }

    var selectedTimer: CountdownTimer? {
        guard isCreating == false else { return nil }
        return filteredTimers.first(where: { $0.id == selectedID }) ?? filteredTimers.first
    }

    var isCompletionSoundEnabled: Bool {
        store.isCompletionSoundEnabled
    }

    var isDraftValid: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (1...1_440).contains(draftMinutes)
    }

    var footerActions: [CommandActionDescriptor] {
        if isCreating {
            var actions = [
                CommandActionDescriptor(
                    id: TimersActionID.startDraft,
                    title: "Start Timer",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: isDraftValid
                )
            ]
            if store.timers.isEmpty == false {
                actions.append(
                    CommandActionDescriptor(
                        id: TimersActionID.cancelDraft,
                        title: "Cancel",
                        keyHint: .escape
                    )
                )
            }
            return actions
        }

        guard let timer = selectedTimer else {
            return [
                CommandActionDescriptor(
                    id: TimersActionID.beginNew,
                    title: "New Timer",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        }

        return [
            primaryAction(for: timer),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(id: TimersActionID.beginNew, title: "New Timer"),
            CommandActionDescriptor(id: TimersActionID.startFocus, title: "Start 25-minute Focus"),
            CommandActionDescriptor(id: TimersActionID.startBreak, title: "Start 5-minute Break")
        ]

        if let timer = selectedTimer {
            actions.append(primaryAction(for: timer))
            actions.append(
                CommandActionDescriptor(
                    id: TimersActionID.resetSelected,
                    title: "Reset Timer",
                    isEnabled: timer.phase != .ready
                )
            )
            actions.append(
                CommandActionDescriptor(
                    id: TimersActionID.deleteSelected,
                    title: "Delete Timer"
                )
            )
        }

        actions.append(
            CommandActionDescriptor(
                id: TimersActionID.toggleSound,
                title: isCompletionSoundEnabled ? "Turn Completion Sound Off" : "Turn Completion Sound On"
            )
        )
        return actions
    }

    func select(_ id: UUID) {
        guard store.timer(id: id) != nil else { return }
        isCreating = false
        selectedID = id
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        guard let nextID = LauncherListSelection.nextID(
            in: filteredTimers,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        ) else { return }
        isCreating = false
        selectedID = nextID
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
        case TimersActionID.beginNew:
            beginCreating()
        case TimersActionID.startDraft:
            startDraftTimer()
        case TimersActionID.cancelDraft:
            cancelCreating()
        case TimersActionID.startFocus:
            startPreset(.focus)
        case TimersActionID.startBreak:
            startPreset(.shortBreak)
        case TimersActionID.startSelected:
            startSelected()
        case TimersActionID.pauseSelected:
            pauseSelected()
        case TimersActionID.resetSelected:
            resetSelected()
        case TimersActionID.deleteSelected:
            deleteSelected()
        case TimersActionID.toggleSound:
            toggleCompletionSound()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        default:
            break
        }
    }

    func beginCreating(preset: TimerPreset = .focus) {
        applyPreset(preset)
        isCreating = true
        selectedID = nil
        query = ""
        showsActionsMenu = false
        statusMessage = nil
    }

    func applyPreset(_ preset: TimerPreset) {
        draftName = preset.title
        draftMinutes = preset.minutes
        statusMessage = nil
    }

    func cancelCreating() {
        guard store.timers.isEmpty == false else { return }
        isCreating = false
        selectedID = filteredTimers.first?.id ?? store.timers.first?.id
        statusMessage = nil
    }

    func startDraftTimer() {
        let normalizedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false, (1...1_440).contains(draftMinutes) else {
            statusMessage = "Enter a name and a duration from 1 to 1,440 minutes."
            return
        }
        let id = store.createTimer(
            name: normalizedName,
            duration: TimeInterval(draftMinutes * 60)
        )
        isCreating = false
        selectedID = id
        filter = .all
        query = ""
        statusMessage = "\(normalizedName) started."
    }

    func startPreset(_ preset: TimerPreset) {
        let id = store.createTimer(
            name: preset.title,
            duration: TimeInterval(preset.minutes * 60)
        )
        isCreating = false
        selectedID = id
        filter = .all
        query = ""
        showsActionsMenu = false
        statusMessage = "\(preset.title) started."
    }

    func startSelected() {
        guard let timer = selectedTimer, store.start(id: timer.id) else { return }
        statusMessage = timer.phase == .paused ? "Resumed." : "Started."
        showsActionsMenu = false
    }

    func pauseSelected() {
        guard let id = selectedTimer?.id, store.pause(id: id) else { return }
        statusMessage = "Paused."
        showsActionsMenu = false
    }

    func resetSelected() {
        guard let id = selectedTimer?.id, store.reset(id: id) else { return }
        statusMessage = "Reset and ready."
        showsActionsMenu = false
    }

    func deleteSelected() {
        guard let id = selectedTimer?.id, store.delete(id: id) else { return }
        selectedID = filteredTimers.first?.id ?? store.timers.first?.id
        if store.timers.isEmpty {
            beginCreating()
        } else {
            isCreating = false
            statusMessage = "Timer deleted."
        }
        showsActionsMenu = false
    }

    func toggleCompletionSound() {
        store.setCompletionSoundEnabled(isCompletionSoundEnabled == false)
        statusMessage = store.isCompletionSoundEnabled
            ? "Completion sound enabled."
            : "Completion sound disabled."
        showsActionsMenu = false
    }

    func remainingText(for timer: CountdownTimer) -> String {
        Self.durationText(store.remainingTime(for: timer))
    }

    func durationText(for timer: CountdownTimer) -> String {
        Self.durationText(timer.totalDuration)
    }

    func elapsedProgress(for timer: CountdownTimer) -> Double {
        store.elapsedProgress(for: timer)
    }

    func phaseTitle(for phase: CountdownTimerPhase) -> String {
        switch phase {
        case .ready: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Complete"
        }
    }

    func goBack() {
        onGoBack()
    }

    /// The shared store intentionally outlives this launcher session.
    func stop() {}

    func handleEscape() -> Bool {
        if isCreating, store.timers.isEmpty == false {
            cancelCreating()
            return true
        }
        if isCreating {
            return false
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func refreshSelection() {
        guard isCreating == false else { return }
        selectedID = LauncherListSelection.resolvedID(
            in: filteredTimers,
            selectedID: selectedID,
            id: \.id
        )
    }

    private func primaryAction(for timer: CountdownTimer) -> CommandActionDescriptor {
        switch timer.phase {
        case .ready:
            return CommandActionDescriptor(
                id: TimersActionID.startSelected,
                title: "Start",
                isPrimary: true,
                keyHint: .return
            )
        case .running:
            return CommandActionDescriptor(
                id: TimersActionID.pauseSelected,
                title: "Pause",
                isPrimary: true,
                keyHint: .return
            )
        case .paused:
            return CommandActionDescriptor(
                id: TimersActionID.startSelected,
                title: "Resume",
                isPrimary: true,
                keyHint: .return
            )
        case .completed:
            return CommandActionDescriptor(
                id: TimersActionID.resetSelected,
                title: "Reset",
                isPrimary: true,
                keyHint: .return
            )
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.up)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension TimersViewModel: LauncherApplicationModel {}
