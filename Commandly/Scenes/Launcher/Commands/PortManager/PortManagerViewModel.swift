import CommandKit
import Foundation
import Observation

nonisolated enum PortManagerActionID {
    static let refresh = CommandActionID(rawValue: "port-manager.refresh")
    static let terminate = CommandActionID(rawValue: "port-manager.terminate")
    static let confirm = CommandActionID(rawValue: "port-manager.confirm")
    static let cancel = CommandActionID(rawValue: "port-manager.cancel")
}

@Observable
@MainActor
final class PortManagerViewModel {
    var query = "" { didSet { refreshSelection() } }
    var selectedListenerID: String?
    var showsActionsMenu = false
    private(set) var listeners: [ListeningPort] = []
    private(set) var isRefreshing = false
    private(set) var isTerminating = false
    private(set) var statusMessage: String?
    private(set) var pendingTermination: ListeningPort?

    @ObservationIgnored private let service: any PortManaging
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var terminationTask: Task<Void, Never>?
    private var requestedPort: UInt16?

    init(
        service: any PortManaging,
        initialPort: UInt16? = nil,
        onGoBack: @escaping () -> Void
    ) {
        self.service = service
        self.requestedPort = initialPort
        self.onGoBack = onGoBack
        if let initialPort {
            self.query = String(initialPort)
        }
    }

    var filteredListeners: [ListeningPort] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return listeners }
        return listeners.filter {
            String($0.port).contains(query)
                || $0.processName.localizedCaseInsensitiveContains(query)
                || String($0.processIdentifier).contains(query)
                || $0.transport.title.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedListener: ListeningPort? {
        filteredListeners.first { $0.id == selectedListenerID } ?? filteredListeners.first
    }

    var footerActions: [CommandActionDescriptor] {
        if pendingTermination != nil {
            return [
                CommandActionDescriptor(id: PortManagerActionID.confirm, title: "Stop Process", isPrimary: true, keyHint: .return, isEnabled: isTerminating == false),
                CommandActionDescriptor(id: PortManagerActionID.cancel, title: "Cancel", keyHint: .escape, isEnabled: isTerminating == false)
            ]
        }
        return [
            CommandActionDescriptor(id: PortManagerActionID.terminate, title: "Stop Listener…", isPrimary: true, keyHint: .return, isEnabled: selectedListener != nil && isTerminating == false),
            CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(id: PortManagerActionID.refresh, title: "Refresh Ports", isEnabled: isRefreshing == false && isTerminating == false),
            CommandActionDescriptor(id: PortManagerActionID.terminate, title: "Stop Listener…", isEnabled: selectedListener != nil && isTerminating == false)
        ]
    }

    func start() { refresh() }
    func stop() { refreshTask?.cancel(); terminationTask?.cancel() }
    func goBack() { onGoBack() }
    func select(_ listener: ListeningPort) { selectedListenerID = listener.id }

    func refresh() {
        guard isRefreshing == false else { return }
        refreshTask?.cancel()
        isRefreshing = true
        statusMessage = nil
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let listeners = try await service.listeningPorts()
                guard Task.isCancelled == false else { return }
                self.listeners = listeners
                self.refreshSelection()
                self.prepareRequestedPortIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to inspect listening ports."
            }
            self.isRefreshing = false
        }
    }

    func perform(_ action: CommandActionID) {
        if pendingTermination != nil {
            switch action {
            case PortManagerActionID.confirm:
                confirmTermination()
            case PortManagerActionID.cancel, BuiltInCommandActionID.goBack:
                pendingTermination = nil
            default:
                break
            }
            return
        }
        switch action {
        case PortManagerActionID.refresh: refresh()
        case PortManagerActionID.terminate: pendingTermination = selectedListener
        case PortManagerActionID.confirm: confirmTermination()
        case PortManagerActionID.cancel: pendingTermination = nil
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack: goBack()
        default: break
        }
    }

    func moveSelection(offset: Int) {
        guard filteredListeners.isEmpty == false else { return }
        let current = filteredListeners.firstIndex { $0.id == selectedListener?.id } ?? 0
        let next = (current + offset + filteredListeners.count) % filteredListeners.count
        selectedListenerID = filteredListeners[next].id
    }

    private func refreshSelection() {
        guard filteredListeners.contains(where: { $0.id == selectedListenerID }) == false else { return }
        selectedListenerID = filteredListeners.first?.id
    }

    private func prepareRequestedPortIfNeeded() {
        guard let requestedPort else { return }
        self.requestedPort = nil
        let matches = listeners.filter { $0.port == requestedPort }
        switch matches.count {
        case 0:
            statusMessage = "No listener is using port \(requestedPort)."
        case 1:
            selectedListenerID = matches[0].id
            pendingTermination = matches[0]
        default:
            selectedListenerID = matches[0].id
            statusMessage = "Multiple listeners use port \(requestedPort). Choose one to review."
        }
    }

    func handleEscape() -> Bool {
        if pendingTermination != nil {
            pendingTermination = nil
            return true
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    private func confirmTermination() {
        guard let listener = pendingTermination, isTerminating == false else { return }
        isTerminating = true
        terminationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.terminate(listener: listener)
                guard Task.isCancelled == false else { return }
                self.pendingTermination = nil
                self.statusMessage = "Stopped \(listener.transport.title) port \(listener.port)."
                self.refresh()
            } catch is CancellationError {
                return
            } catch {
                self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to stop that listener."
            }
            self.isTerminating = false
        }
    }
}
