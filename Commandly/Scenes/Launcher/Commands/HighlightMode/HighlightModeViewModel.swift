import CommandKit
import Infrastructure
import Observation

enum HighlightModeActionID {
    static let toggle = CommandActionID(rawValue: "highlight-mode.toggle")
    static let openPermissions = CommandActionID(rawValue: "highlight-mode.open-permissions")
}

@Observable
@MainActor
final class HighlightModeViewModel {
    var showsActionsMenu = false
    private(set) var state: HighlightModeState
    private(set) var isChanging = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    @ObservationIgnored
    private let service: any HighlightModeControlling
    @ObservationIgnored
    private let configuration: HighlightModeConfiguration
    @ObservationIgnored
    private let onOpenPermissions: () -> Void
    @ObservationIgnored
    private let onGoBack: () -> Void
    @ObservationIgnored
    private var operationTask: Task<Void, Never>?

    init(
        service: any HighlightModeControlling,
        configuration: HighlightModeConfiguration,
        onOpenPermissions: @escaping () -> Void,
        onGoBack: @escaping () -> Void
    ) {
        self.service = service
        self.configuration = configuration
        self.onOpenPermissions = onOpenPermissions
        self.onGoBack = onGoBack
        self.state = service.state
    }

    var primaryActionTitle: String {
        state.isEnabled ? "Turn Highlight Mode Off" : "Turn Highlight Mode On"
    }

    var footerActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: HighlightModeActionID.toggle,
                title: isChanging ? "Changing…" : primaryActionTitle,
                isPrimary: true,
                keyHint: .return,
                isEnabled: isChanging == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isChanging == false
            ),
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: HighlightModeActionID.toggle,
                title: primaryActionTitle,
                isEnabled: isChanging == false
            ),
            CommandActionDescriptor(
                id: HighlightModeActionID.openPermissions,
                title: "Open Permission Settings"
            ),
        ]
    }

    func start() {
        service.updateConfiguration(configuration)
        state = service.state
    }

    func toggle() {
        guard isChanging == false else { return }
        operationTask?.cancel()
        isChanging = true
        errorMessage = nil
        statusMessage = nil
        let shouldEnable = state.isEnabled == false

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                state = try await service.setEnabled(
                    shouldEnable,
                    configuration: configuration
                )
                statusMessage = state.isEnabled
                    ? "Click, keyboard, and cursor feedback is active."
                    : "Highlight Mode is off."
                isChanging = false
            } catch is CancellationError {
                isChanging = false
            } catch HighlightModeError.accessibilityDenied {
                errorMessage = "Allow Commandly in Privacy & Security → Accessibility, then try again."
                statusMessage = errorMessage
                isChanging = false
            } catch {
                errorMessage = "Commandly couldn’t start global input monitoring."
                statusMessage = errorMessage
                isChanging = false
            }
        }
    }

    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        switch actionID {
        case HighlightModeActionID.toggle:
            toggle()
        case HighlightModeActionID.openPermissions:
            onOpenPermissions()
        default:
            break
        }
    }

    func moveSelection(offset: Int) {
        _ = offset
    }

    func stop() {
        operationTask?.cancel()
        operationTask = nil
        isChanging = false
    }

    func goBack() {
        onGoBack()
    }

    func openPermissions() {
        onOpenPermissions()
    }

    func waitForOperationForTesting() async {
        await operationTask?.value
    }
}
