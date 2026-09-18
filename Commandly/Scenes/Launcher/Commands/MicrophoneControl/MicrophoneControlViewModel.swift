import CommandKit
import Foundation
import Infrastructure
import Observation

enum MicrophoneControlActionID {
    static let toggle = CommandActionID(rawValue: "microphone.toggle")
    static let refresh = CommandActionID(rawValue: "microphone.refresh")
}

@Observable
@MainActor
final class MicrophoneControlViewModel {
    static let automaticRefreshInterval: Duration = .seconds(1)

    var showsActionsMenu = false
    private(set) var state: MicrophoneControlState?
    private(set) var isRefreshing = false
    private(set) var isChanging = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    @ObservationIgnored
    private let service: any MicrophoneControlling
    @ObservationIgnored
    private let onGoBack: () -> Void
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var operationTask: Task<Void, Never>?
    @ObservationIgnored
    private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var refreshGeneration = 0

    init(
        service: any MicrophoneControlling,
        onGoBack: @escaping () -> Void
    ) {
        self.service = service
        self.onGoBack = onGoBack
    }

    var isMuted: Bool? { state?.isMuted }

    var canChangeMute: Bool {
        state?.canChangeMute == true && state?.isMuted != nil && isChanging == false
    }

    var primaryActionTitle: String {
        guard let state, let isMuted = state.isMuted, state.canChangeMute else {
            return errorMessage == nil ? "Refresh" : "Try Again"
        }
        return isMuted ? "Turn Microphone On" : "Turn Microphone Off"
    }

    var footerActions: [CommandActionDescriptor] {
        let primaryID = canChangeMute ? MicrophoneControlActionID.toggle : MicrophoneControlActionID.refresh
        return [
            CommandActionDescriptor(
                id: primaryID,
                title: isChanging ? "Changing…" : primaryActionTitle,
                isPrimary: true,
                keyHint: .return,
                isEnabled: isRefreshing == false && isChanging == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isChanging == false
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        var actions: [CommandActionDescriptor] = []
        if state?.canChangeMute == true, state?.isMuted != nil {
            actions.append(
                CommandActionDescriptor(
                    id: MicrophoneControlActionID.toggle,
                    title: primaryActionTitle,
                    isEnabled: isRefreshing == false && isChanging == false
                )
            )
        }
        actions.append(
            CommandActionDescriptor(
                id: MicrophoneControlActionID.refresh,
                title: "Refresh Microphone Status",
                isEnabled: isRefreshing == false && isChanging == false
            )
        )
        return actions
    }

    func start() {
        guard automaticRefreshTask == nil else { return }
        refresh(showSuccessMessage: false)
        automaticRefreshTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: Self.automaticRefreshInterval)
                } catch {
                    return
                }
                guard let self, Task.isCancelled == false else { return }
                if self.isRefreshing == false && self.isChanging == false {
                    self.refresh(showSuccessMessage: false)
                }
            }
        }
    }

    func stop() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        operationTask?.cancel()
        operationTask = nil
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        isRefreshing = false
        isChanging = false
    }

    func refresh(showSuccessMessage: Bool = true) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        isRefreshing = true
        if showSuccessMessage {
            statusMessage = nil
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updatedState = try await service.state()
                guard Task.isCancelled == false, refreshGeneration == generation else { return }
                state = updatedState
                if showSuccessMessage == false, errorMessage != nil {
                    statusMessage = nil
                }
                errorMessage = nil
                if showSuccessMessage {
                    statusMessage = "Microphone status updated."
                }
                isRefreshing = false
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false, refreshGeneration == generation else { return }
                state = nil
                errorMessage = Self.readErrorMessage(for: error)
                statusMessage = errorMessage
                isRefreshing = false
            }
        }
    }

    func toggleMute() {
        guard let currentState = state,
              let isMuted = currentState.isMuted,
              currentState.canChangeMute,
              isChanging == false else { return }

        refreshGeneration += 1
        refreshTask?.cancel()
        isRefreshing = false
        operationTask?.cancel()
        isChanging = true
        errorMessage = nil
        statusMessage = nil

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let updatedState = try await service.setMuted(isMuted == false)
                guard Task.isCancelled == false else { return }
                state = updatedState
                let nowMuted = updatedState.isMuted ?? (isMuted == false)
                statusMessage = nowMuted
                    ? "Microphone turned off for the current input device."
                    : "Microphone turned on for the current input device."
                isChanging = false
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                errorMessage = Self.writeErrorMessage(for: error)
                statusMessage = errorMessage
                isChanging = false
            }
        }
    }

    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        switch actionID {
        case MicrophoneControlActionID.toggle:
            toggleMute()
        case MicrophoneControlActionID.refresh:
            refresh()
        default:
            break
        }
    }

    func moveSelection(offset: Int) {
        _ = offset
    }

    func goBack() {
        onGoBack()
    }

    func waitForRefreshForTesting() async {
        await refreshTask?.value
    }

    func waitForOperationForTesting() async {
        await operationTask?.value
    }

    private static func readErrorMessage(for error: Error) -> String {
        if case MicrophoneControlError.noDefaultInputDevice = error {
            return "No default microphone is available."
        }
        return "Couldn’t read the microphone status."
    }

    private static func writeErrorMessage(for error: Error) -> String {
        if case MicrophoneControlError.muteControlUnavailable = error {
            return "This microphone does not provide a writable system mute control."
        }
        return "Couldn’t change the microphone status."
    }
}
