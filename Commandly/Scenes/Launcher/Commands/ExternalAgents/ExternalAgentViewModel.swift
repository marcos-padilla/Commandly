import AIKit
import CommandKit
import Foundation
import Observation

nonisolated struct ExternalAgentConversation: Identifiable, Sendable {
    let id = UUID()
    let target: String
    var title = "New conversation"
    var entries: [QuickAIEntry] = []
    var messages: [ExternalAgentMessage] = []
    var requiresNewConversation = false
}

@MainActor @Observable final class ExternalAgentViewModel: LauncherApplicationModel {
    let kind: ExternalAgentKind
    @ObservationIgnored private let service: any ExternalAgentServing
    @ObservationIgnored let goBack: () -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private var started = false
    private(set) var connection: ExternalAgentConnection?
    private(set) var targets: [String] = []
    private(set) var conversations: [ExternalAgentConversation] = []
    private(set) var selectedConversationID: UUID?
    private(set) var busy = false
    private(set) var responding = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    var target = ""
    var endpoint: String
    var token = ""
    var draft = ""
    var showsConnection = false
    var showsActionsMenu = false
    var conversation: ExternalAgentConversation? { conversations.first { $0.id == selectedConversationID } }
    var entries: [QuickAIEntry] { conversation?.entries ?? [] }
    var canSend: Bool {
        !busy && !showsConnection && connection != nil && targets.contains(target)
            && conversation?.requiresNewConversation != true && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.utf8.count <= 64 * 1024 && (conversation?.messages.count ?? 0) < 63
    }
    var footerActions: [CommandActionDescriptor] {
        [.init(id: .init(rawValue: responding ? "external.stop" : "external.send"), title: responding ? "Stop Reply" : "Send Message",
               isPrimary: true, keyHint: .return, isEnabled: responding || canSend),
         .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: .init(rawValue: "external.new"), title: "New Conversation", isEnabled: !busy && !target.isEmpty),
         .init(id: .init(rawValue: "external.refresh"), title: "Refresh Available Agents", isEnabled: !busy && connection != nil),
         .init(id: .init(rawValue: "external.connection"), title: "Agent Connection…", isEnabled: !busy)]
    }
    init(kind: ExternalAgentKind, service: any ExternalAgentServing, goBack: @escaping () -> Void) {
        self.kind = kind; self.service = service; self.goBack = goBack; endpoint = kind.suggestedEndpoint
    }
    deinit { task?.cancel() }
    func start() { guard !started else { return }; started = true; reload() }
    func reload() {
        run { model in
            let saved = try await model.service.connection(for: model.kind)
            try Task.checkCancellation()
            if saved != model.connection { model.clearConversations() }
            model.connection = saved; model.targets = saved?.targets ?? []
            model.target = model.targets.first ?? ""
            model.endpoint = saved?.endpoint.absoluteString ?? model.kind.suggestedEndpoint
        }
    }
    func connect() {
        guard !busy else { return }
        let token = token; self.token = ""; let endpoint = endpoint
        run { model in
            _ = try await model.service.connect(kind: model.kind, endpoint: endpoint, token: token)
            let saved = try await model.service.connection(for: model.kind)
            try Task.checkCancellation()
            model.clearConversations(); model.connection = saved; model.targets = saved?.targets ?? []
            model.target = model.targets.first ?? ""; model.showsConnection = false
            model.statusMessage = "Connected. Choose an agent and send a message to begin."
        }
    }
    func disconnect() {
        run { model in
            try await model.service.disconnect(kind: model.kind); try Task.checkCancellation()
            model.clearConversations(); model.connection = nil; model.targets = []; model.target = ""
            model.statusMessage = "Local connection removed. Remote conversations remain on your server."
        }
    }
    func refreshTargets() {
        guard let connection else { return }
        run { model in
            let values = try await model.service.refresh(connection)
            try Task.checkCancellation(); model.targets = values
            if !values.contains(model.target) { model.target = values.first ?? ""; model.selectedConversationID = nil }
            model.statusMessage = "Available agents refreshed."
        }
    }
    func chooseTarget(_ value: String) {
        guard !busy, targets.contains(value), value != target else { return }
        target = value; selectedConversationID = nil; draft = ""; errorMessage = nil
    }
    func chooseConversation(_ id: UUID) {
        guard !busy, let selected = conversations.first(where: { $0.id == id }), targets.contains(selected.target) else { return }
        target = selected.target; selectedConversationID = id; draft = ""; errorMessage = nil
    }
    func newConversation() {
        guard !busy, targets.contains(target) else { return }
        if conversations.count == 8 { conversations.removeFirst() }
        let value = ExternalAgentConversation(target: target)
        conversations.append(value); selectedConversationID = value.id; draft = ""; errorMessage = nil
    }
    func removeConversation() {
        guard !busy else { return }
        conversations.removeAll { $0.id == selectedConversationID }; selectedConversationID = nil
        statusMessage = "Removed from this window. Server history is managed in the agent's own interface."
    }
    func send() {
        guard canSend, let connection else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedConversationID == nil { newConversation() }
        guard let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else { return }
        guard conversations[index].messages.reduce(0, { $0 + $1.content.utf8.count }) + prompt.utf8.count <= 1024 * 1024 else {
            errorMessage = ExternalAgentError.tooLarge.localizedDescription; return
        }
        let id = conversations[index].id; let selectedTarget = target
        let messages = conversations[index].messages + [.init(role: .user, content: prompt)]
        if conversations[index].entries.isEmpty { conversations[index].title = String(prompt.prefix(48)) }
        conversations[index].entries.append(.init(isUser: true, text: prompt))
        conversations[index].entries.append(.init(isUser: false, text: "", state: .streaming))
        draft = ""; responding = true
        let stamp = generation
        run { model in
            do {
                try await model.service.respond(connection: connection, target: selectedTarget, conversationID: id, messages: messages,
                    onText: { [weak model] delta in
                        try await MainActor.run {
                            guard let model, model.generation == stamp, model.responding,
                                  let i = model.conversations.firstIndex(where: { $0.id == id }), !model.conversations[i].entries.isEmpty else { throw CancellationError() }
                            let entry = model.conversations[i].entries.count - 1
                            model.conversations[i].entries[entry].text += delta
                            model.statusMessage = "Receiving reply…"
                        }
                    }, onProgress: { [weak model] in
                        try await MainActor.run {
                            guard let model, model.generation == stamp, model.responding else { throw CancellationError() }
                            model.statusMessage = "The agent is using a server-side tool."
                        }
                    })
                try Task.checkCancellation()
                guard let i = model.conversations.firstIndex(where: { $0.id == id }), let reply = model.conversations[i].entries.last else { return }
                model.conversations[i].messages = messages + [.init(role: .assistant, content: reply.text)]
                model.conversations[i].entries[model.conversations[i].entries.count - 1].state = .complete
                model.statusMessage = "Reply received."
            } catch {
                if model.generation == stamp, let i = model.conversations.firstIndex(where: { $0.id == id }), !model.conversations[i].entries.isEmpty {
                    model.conversations[i].requiresNewConversation = true
                    model.conversations[i].entries[model.conversations[i].entries.count - 1].state = .failed
                }
                throw error
            }
        }
    }
    private func run(_ operation: @escaping @MainActor (ExternalAgentViewModel) async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil; statusMessage = nil
        let stamp = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == stamp { self.busy = false; self.responding = false; self.task = nil } }
            do { try await operation(self) }
            catch {
                guard self.generation == stamp, !Task.isCancelled else { return }
                if let error = error as? ExternalAgentError { self.errorMessage = error.localizedDescription }
                else if let error = error as? AIProviderError { self.errorMessage = error.localizedDescription }
                else { self.errorMessage = ExternalAgentError.unavailable.localizedDescription }
            }
        }
    }
    func cancel() {
        let wasResponding = responding
        generation = UUID(); task?.cancel(); task = nil; busy = false; responding = false
        if wasResponding, let index = conversations.firstIndex(where: { $0.id == selectedConversationID }), !conversations[index].entries.isEmpty {
            conversations[index].requiresNewConversation = true
            conversations[index].entries[conversations[index].entries.count - 1].state = .stopped
            statusMessage = "Stopped receiving. Check the agent's own interface for tool outcomes before starting again."
        }
    }
    func closeConnection() { guard !busy else { return }; token = ""; showsConnection = false }
    func stop() { cancel(); token = ""; draft = ""; clearConversations(); started = false }
    private func clearConversations() { conversations = []; selectedConversationID = nil }
    func moveSelection(offset: Int) {}
    func perform(_ actionID: CommandActionID) {
        switch actionID.rawValue {
        case "external.send": send()
        case "external.stop": cancel()
        case "external.new": newConversation()
        case "external.refresh": refreshTargets()
        case "external.connection": if !busy { showsConnection = true }
        default: if actionID == BuiltInCommandActionID.openActions { showsActionsMenu.toggle() }
        }
    }
    func handleEscape() -> Bool {
        if showsActionsMenu { showsActionsMenu = false; return true }
        if busy { cancel(); return true }
        if showsConnection { closeConnection(); return true }
        if !draft.isEmpty { draft = ""; return true }
        return false
    }
}
