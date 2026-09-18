import AIKit
import CommandKit
import Foundation
import Observation

nonisolated enum QuickAIEntryState: Equatable, Sendable { case complete, streaming, stopped, failed, limited, refused }
nonisolated struct QuickAIEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let isUser: Bool
    var text: String
    var state: QuickAIEntryState
    init(id: UUID = UUID(), isUser: Bool, text: String, state: QuickAIEntryState = .complete) {
        self.id = id; self.isUser = isUser; self.text = text; self.state = state
    }
}

enum QuickAIActionID {
    static let send = CommandActionID(rawValue: "quick-ai.send")
    static let stop = CommandActionID(rawValue: "quick-ai.stop")
    static let retry = CommandActionID(rawValue: "quick-ai.retry")
    static let reset = CommandActionID(rawValue: "quick-ai.reset")
    static let settings = CommandActionID(rawValue: "quick-ai.settings")
    static let refresh = CommandActionID(rawValue: "quick-ai.refresh")
    static let refreshModels = CommandActionID(rawValue: "quick-ai.refresh-models")
}

@Observable
@MainActor
final class QuickAIViewModel: LauncherApplicationModel {
    private static let systemPrompt = "You are a helpful assistant in Commandly. Answer the user's text request clearly. You have no tools, browser, file access, or access to the user's screen. Do not claim to have performed actions outside this conversation."
    private static let maximumPromptBytes = 64 * 1_024
    private static let maximumConversationBytes = 1_024 * 1_024
    private static let maximumMessages = 64
    var draft = ""
    var showsActionsMenu = false
    private(set) var entries: [QuickAIEntry] = []
    private(set) var selections: [QuickAISelection] = []
    private(set) var selection: QuickAISelection?
    private(set) var pendingSelection: QuickAISelection?
    private(set) var isLoading = false
    private(set) var isResponding = false
    private(set) var needsReset = false
    private(set) var statusMessage: String?
    private(set) var loadError: String?
    private(set) var isRefreshingModels = false
    private(set) var modelRefreshMessage: String?
    private(set) var modelRefreshFailed = false
    @ObservationIgnored private let service: any QuickAIServicing
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onOpenSettings: () -> Void
    @ObservationIgnored private var messages: [AIMessage] = [.system(systemPrompt)]
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeTurnID: UUID?
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var modelRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var modelRefreshID = UUID()
    @ObservationIgnored private var discoveredChoices: [String: [QuickAISelection]] = [:]
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var retryPrompt: String?
    @ObservationIgnored private var retryEntryIDs: Set<UUID> = []
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var responseBytes = 0

    init(service: any QuickAIServicing, onGoBack: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.service = service; self.onGoBack = onGoBack; self.onOpenSettings = onOpenSettings
    }

    var isSelectedModelAvailable: Bool { selection.map { choice in selections.contains { $0.id == choice.id } } == true }
    var canRefreshModels: Bool {
        selection != nil && isLoading == false && isResponding == false && isRefreshingModels == false
            && pendingSelection == nil && needsReset == false
    }
    var composerIsEnabled: Bool { selection != nil && isLoading == false && isResponding == false && pendingSelection == nil }
    var modelRefreshDisclosure: String {
        guard let selection else { return "" }
        return "Refresh Models contacts \(selection.providerName) for available text models using your saved connection."
    }

    var canSend: Bool {
        selection?.supportsStreaming == true && isLoading == false && isResponding == false
            && isSelectedModelAvailable && isRefreshingModels == false
            && needsReset == false && pendingSelection == nil && normalizedDraft.isEmpty == false
            && draftIsTooLarge == false && conversationWouldOverflow == false
    }
    var canRetry: Bool {
        retryPrompt != nil && needsReset == false && isResponding == false && isLoading == false
            && selection?.supportsStreaming == true && pendingSelection == nil
            && isSelectedModelAvailable && isRefreshingModels == false
    }
    var draftIsTooLarge: Bool { draft.utf8.count > Self.maximumPromptBytes }
    var conversationWouldOverflow: Bool {
        messages.count + 2 > Self.maximumMessages
            || Self.byteCount(messages) + normalizedDraft.utf8.count + 256 * 1_024 > Self.maximumConversationBytes
            || entries.count + 2 > Self.maximumMessages
            || entries.reduce(0, { $0 + $1.text.utf8.count }) + normalizedDraft.utf8.count + 256 * 1_024 > Self.maximumConversationBytes
    }
    var composerHint: String {
        if needsReset { return "Connection changed · start a new chat before sending again" }
        if isRefreshingModels { return "Refreshing available models · Escape cancels this request" }
        if selection != nil && isSelectedModelAvailable == false { return "Current model is no longer listed · choose a model to start a new chat" }
        if draftIsTooLarge { return "Shorten this message to 64 KiB or less" }
        if conversationWouldOverflow { return "Conversation limit reached · start a new chat" }
        if isResponding { return "Receiving reply · Escape stops this request" }
        if selection?.supportsStreaming == false { return "Streaming is unavailable for this configured provider" }
        return "Return sends · Shift-Return adds a line · conversations stay in this session"
    }
    var disclosure: String {
        guard let selection else { return "Connect your own provider in AI Settings to begin." }
        return selection.providerID == AIProviderID.ollama.rawValue
            ? "Your messages and this conversation go to your configured local Ollama endpoint."
            : "Your messages and this conversation go directly to \(selection.providerName) under your account."
    }
    var footerActions: [CommandActionDescriptor] {
        let primary = isResponding
            ? CommandActionDescriptor(id: QuickAIActionID.stop, title: "Stop Reply", isPrimary: true, keyHint: .escape)
            : selection == nil
                ? CommandActionDescriptor(id: QuickAIActionID.settings, title: "Open AI Settings", isPrimary: true)
                : CommandActionDescriptor(id: QuickAIActionID.send, title: "Send Message", isPrimary: true, keyHint: .return, isEnabled: canSend)
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [
            .init(id: QuickAIActionID.retry, title: "Retry Last Message", isEnabled: canRetry),
            .init(id: QuickAIActionID.reset, title: "New Chat", isEnabled: entries.isEmpty == false || needsReset),
             .init(id: QuickAIActionID.refreshModels, title: "Refresh Models from Provider", isEnabled: canRefreshModels),
            .init(id: QuickAIActionID.refresh, title: "Reload Saved Connections", isEnabled: isResponding == false),
            .init(id: QuickAIActionID.settings, title: "Open AI Settings")
        ]
    }

    func start() { guard didStart == false else { return }; didStart = true; reloadChoices() }

    func reloadChoices() {
        guard isResponding == false else { return }
        loadingTask?.cancel()
        pendingSelection = nil
        cancelModelRefresh()
        modelRefreshMessage = nil
        let token = UUID()
        generation = token
        isLoading = true
        loadError = nil
        loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let catalog = try await service.catalog()
                guard Task.isCancelled == false, generation == token else { return }
                discoveredChoices = discoveredChoices.filter { provider, choices in
                    guard let saved = catalog.selections.first(where: { $0.providerID == provider }) else { return false }
                    return choices.allSatisfy { $0.connectionRevision == saved.connectionRevision }
                }
                selections = catalog.selections.flatMap { saved in discoveredChoices[saved.providerID] ?? [saved] }
                if let selection, let refreshed = selections.first(where: { $0.id == selection.id }) {
                    self.selection = refreshed
                } else if selection != nil {
                    self.selection = nil
                    needsReset = entries.isEmpty == false || draft.isEmpty == false
                }
                if selection == nil && needsReset == false {
                    selection = selections.first { $0.id == catalog.preferredID } ?? selections.first
                }
                isLoading = false
            } catch {
                guard Task.isCancelled == false, generation == token else { return }
                isLoading = false
                loadError = "Configured providers could not be loaded. Check AI Settings, then try again."
            }
        }
    }

    func refreshModels() {
        guard canRefreshModels, let requested = selection else { return }
        modelRefreshTask?.cancel()
        let token = UUID()
        modelRefreshID = token
        isRefreshingModels = true
        modelRefreshMessage = nil
        modelRefreshFailed = false
        modelRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let choices = try await service.refreshModels(for: requested)
                guard Task.isCancelled == false, modelRefreshID == token else { return }
                var seen: Set<String> = []
                let compatible = choices.filter {
                    $0.providerID == requested.providerID && $0.connectionRevision == requested.connectionRevision
                        && $0.supportsStreaming && seen.insert($0.id).inserted
                }.prefix(256)
                guard compatible.isEmpty == false else { throw AIConnectionServiceError.noCompatibleModels }
                discoveredChoices[requested.providerID] = Array(compatible)
                selections.removeAll { $0.providerID == requested.providerID }
                selections += compatible
                selections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                if let refreshed = selections.first(where: { $0.id == requested.id }) { selection = refreshed }
                modelRefreshMessage = isSelectedModelAvailable
                    ? "\(compatible.count) text models available from \(requested.providerName). Choose a model in the header."
                    : "\(requested.providerName) no longer lists the current model. Choose another model to start a new chat."
                isRefreshingModels = false
            } catch {
                guard Task.isCancelled == false, modelRefreshID == token else { return }
                isRefreshingModels = false
                modelRefreshFailed = true
                if Self.requiresReset(error) { needsReset = true }
                modelRefreshMessage = Self.modelRefreshFailure(error, provider: requested.providerName)
            }
        }
    }

    func cancelModelRefresh() {
        guard isRefreshingModels else { return }
        modelRefreshTask?.cancel()
        modelRefreshID = UUID()
        isRefreshingModels = false
        modelRefreshFailed = false
        modelRefreshMessage = "Model refresh canceled. Your current chat is unchanged."
    }

    func requestSelection(_ id: String) {
        guard isResponding == false, isLoading == false, isRefreshingModels == false, let next = selections.first(where: { $0.id == id }), next != selection else { return }
        if entries.isEmpty == false || draft.isEmpty == false { pendingSelection = next }
        else { selection = next; needsReset = false; modelRefreshMessage = nil }
    }
    func confirmSelectionChange() {
        guard let next = pendingSelection else { return }
        reset()
        selection = next
        modelRefreshMessage = nil
    }
    func cancelSelectionChange() { pendingSelection = nil }

    func send() {
        guard canSend, let selection else { return }
        let prompt = normalizedDraft
        draft = ""
        let user = QuickAIEntry(isUser: true, text: prompt)
        let assistant = QuickAIEntry(isUser: false, text: "", state: .streaming)
        entries += [user, assistant]
        retryPrompt = prompt
        retryEntryIDs = [user.id, assistant.id]
        statusMessage = nil
        isResponding = true
        responseBytes = 0
        let turnID = UUID()
        activeTurnID = turnID
        let requestMessages = messages + [.user(prompt)]
        responseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await service.respond(messages: requestMessages, selection: selection) { [weak self] delta in
                    guard let self else { throw CancellationError() }
                    try await self.receive(delta, entryID: assistant.id, turnID: turnID)
                }
                guard Task.isCancelled == false, activeTurnID == turnID else { return }
                let text = response.message.content.compactMap { if case .text(let value) = $0 { return value }; return nil }.joined()
                guard text.isEmpty == false, text.utf8.count <= 256 * 1_024,
                      response.message.toolCalls.isEmpty, response.message.toolResults.isEmpty,
                      [.completed, .length, .contentFiltered, .refused].contains(response.finishReason) else {
                    throw AIProviderError.invalidProviderResponse
                }
                update(assistant.id, text: text, state: response.finishReason == .length ? .limited
                    : [.refused, .contentFiltered].contains(response.finishReason) ? .refused : .complete)
                messages = requestMessages + [.assistant(text)]
                retryPrompt = nil
                retryEntryIDs = []
                if response.finishReason == .length { statusMessage = "The model reached its response limit. You can ask it to continue." }
                if [.refused, .contentFiltered].contains(response.finishReason) { statusMessage = "The provider declined or limited this response." }
                isResponding = false
                activeTurnID = nil
            } catch {
                guard activeTurnID == turnID else { return }
                let cancelled = Task.isCancelled || (error as? AIProviderError) == .cancelled || error is CancellationError
                let changed = Self.requiresReset(error)
                if changed { needsReset = true; retryPrompt = nil }
                update(assistant.id, text: changed ? "" : nil, state: cancelled ? .stopped : .failed)
                statusMessage = cancelled ? "Reply stopped. Partial output is not included in follow-up context."
                    : changed ? "The configured connection changed. Start a new chat after checking AI Settings."
                    : Self.failureMessage(error)
                isResponding = false
                activeTurnID = nil
            }
        }
    }

    func stopReply() {
        guard isResponding else { return }
        responseTask?.cancel()
        activeTurnID = nil
        isResponding = false
        if let entry = entries.last, entry.state == .streaming { update(entry.id, state: .stopped) }
        statusMessage = "Reply stopped. Partial output is not included in follow-up context."
    }
    func retry() {
        guard canRetry, let prompt = retryPrompt else { return }
        entries.removeAll { retryEntryIDs.contains($0.id) }
        draft = prompt
        send()
    }
    func reset() {
        stopReply()
        cancelModelRefresh()
        entries = []; messages = [.system(Self.systemPrompt)]; draft = ""
        retryPrompt = nil; retryEntryIDs = []; needsReset = false; pendingSelection = nil; statusMessage = nil
        if isSelectedModelAvailable == false { selection = selections.first }
    }
    func stop() {
        loadingTask?.cancel(); generation = UUID(); reset(); didStart = false; isLoading = false
        selections = []; selection = nil; discoveredChoices = [:]; modelRefreshMessage = nil; modelRefreshFailed = false
    }
    func goBack() { onGoBack() }
    func openSettings() { onOpenSettings() }
    func moveSelection(offset: Int) { }
    func handleEscape() -> Bool {
        if pendingSelection != nil { cancelSelectionChange(); return true }
        if isResponding { stopReply(); return true }
        if isRefreshingModels { cancelModelRefresh(); return true }
        return false
    }
    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        switch actionID {
        case QuickAIActionID.send: send()
        case QuickAIActionID.stop: stopReply()
        case QuickAIActionID.retry: retry()
        case QuickAIActionID.reset: reset()
        case QuickAIActionID.settings: openSettings()
        case QuickAIActionID.refresh: reloadChoices()
        case QuickAIActionID.refreshModels: refreshModels()
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }
    func waitForLoadingForTesting() async { await loadingTask?.value }
    func waitForModelRefreshForTesting() async { await modelRefreshTask?.value }
    func waitForResponseForTesting() async { await responseTask?.value }

    private var normalizedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func receive(_ delta: String, entryID: UUID, turnID: UUID) throws {
        guard activeTurnID == turnID, Task.isCancelled == false,
              let index = entries.firstIndex(where: { $0.id == entryID }) else { throw CancellationError() }
        responseBytes += delta.utf8.count
        guard responseBytes <= 256 * 1_024 else { throw AIProviderError.invalidProviderResponse }
        entries[index].text += delta
    }
    private func update(_ id: UUID, text: String? = nil, state: QuickAIEntryState) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if let text { entries[index].text = text }
        entries[index].state = state
    }
    private static func byteCount(_ messages: [AIMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.reduce(0) { total, part in
            if case .text(let value) = part { return total + value.utf8.count }; return total
        } }
    }
    private static func requiresReset(_ error: any Error) -> Bool {
        if let error = error as? AIProviderRuntimeError {
            return [.connectionMismatch, .modelMismatch, .noActiveConnection, .credentialUnavailable].contains(error)
        }
        return (error as? AIProviderError) == .configurationMismatch
    }
    private static func modelRefreshFailure(_ error: any Error, provider: String) -> String {
        if requiresReset(error) { return "The saved connection changed. Reload Saved Connections after checking AI Settings. Your current chat is preserved." }
        let recovery: String
        switch error as? AIConnectionServiceError {
        case .invalidCredential, .insufficientPermission: recovery = "Check its key and permissions in AI Settings."
        case .billingUnavailable: recovery = "Check billing or credits with this provider."
        case .rateLimited: recovery = "The provider reached a rate or quota limit. Try again later."
        case .noCompatibleModels: recovery = "No compatible text models were returned. Check model access in AI Settings."
        case .invalidEndpoint: recovery = "Check the configured local endpoint in AI Settings."
        case .unsupportedRuntime: recovery = "Model discovery is unavailable for this provider."
        default: recovery = "Check its connection and try again."
        }
        return "Could not refresh \(provider) models. \(recovery) Your current chat is unchanged."
    }

    private static func failureMessage(_ error: any Error) -> String {
        if let error = error as? AIProviderError {
            switch error {
            case .invalidCredential, .credentialMissing, .insufficientPermission:
                return "Check this provider's credential and permissions in AI Settings."
            case .billingUnavailable: return "Check billing or credits with your provider, then retry."
            case .rateLimited: return "The provider reached a rate or quota limit. Retry later or check its credits."
            case .modelUnavailable, .unsupportedCapability: return "This model could not stream a text reply. Choose another configured model or check AI Settings."
            default: return "The reply could not be completed. Retry the message or check your provider settings."
            }
        }
        return "The reply could not be completed. Retry the message or check AI Settings."
    }
}
