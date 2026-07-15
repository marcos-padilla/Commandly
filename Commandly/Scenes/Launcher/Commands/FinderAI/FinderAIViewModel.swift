import AIKit
import CommandKit
import Foundation
import Observation

nonisolated enum FinderAIConversationRole: Sendable, Equatable {
    case user
    case assistant
    case activity
    case error
}

/// Local-only presentation entry. Finder AI conversations are intentionally never persisted.
nonisolated struct FinderAIConversationEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: FinderAIConversationRole
    let text: String

    init(id: UUID = UUID(), role: FinderAIConversationRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

nonisolated enum FinderAIConversationPhase: Sendable, Equatable {
    case loading
    case ready
    case responding
    case awaitingApproval
    case unavailable
}

enum FinderAIActionID {
    static let send = CommandActionID(rawValue: "finder-ai.send")
    static let stopGeneration = CommandActionID(rawValue: "finder-ai.stop")
    static let approve = CommandActionID(rawValue: "finder-ai.approve")
    static let deny = CommandActionID(rawValue: "finder-ai.deny")
    static let clearConversation = CommandActionID(rawValue: "finder-ai.clear")
    static let openAISettings = CommandActionID(rawValue: "finder-ai.open-settings")
    static let openPermissionsSettings = CommandActionID(
        rawValue: "finder-ai.open-permissions-settings"
    )
}

nonisolated enum FinderAIConfigurationIssue: Sendable, Equatable {
    case missingConnection
    case unsupportedModel
    case missingAuthorizedFolders
    case loadFailed
}

/// Coordinates one ephemeral provider conversation and one isolated Finder workspace session.
///
/// This type never sees a provider credential or filesystem URL. Provider access is delegated to
/// `AIProviderRuntimeServicing`; filesystem operations are delegated to the typed tool executor.
@Observable
@MainActor
final class FinderAIViewModel {
    private enum ConversationInvalidationReason {
        case connectionChanged
        case incompleteApprovedMutation
    }

    private static let maximumProviderRounds = 8
    private static let maximumToolCalls = 24
    private static let maximumCallsPerRound = 8
    private static let maximumToolNameBytes = 128
    private static let maximumToolArgumentBytes = 64 * 1_024
    private static let maximumToolArgumentBytesPerConversation = 256 * 1_024
    private static let maximumToolResultBytes = 512 * 1_024
    private static let maximumConversationBytes = 1_024 * 1_024
    private static let maximumConversationMessages = 64
    private static let maximumPromptBytes = 64 * 1_024

    private let runtime: any AIProviderRuntimeServicing
    private let workspace: any FinderAIWorkspaceQuerying
    private let toolExecutor: any FinderAIToolExecuting
    private let onGoBack: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenPermissionsSettings: () -> Void

    private var sessionID: FinderAISessionID?
    private var providerMessages: [AIMessage] = [.system(FinderAIViewModel.systemPrompt)]
    private var providerState: AIProviderState?
    private var conversationSelection: AIActiveProviderSelection?
    private var conversationInvalidationReason: ConversationInvalidationReason?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var approvalTurnID: UUID?
    private var incompleteToolTurnMessageIndex: Int?
    private var incompleteToolTurnHasApprovedMutation = false
    private var didStart = false
    private var lifecycleID = UUID()
    private var activeTurnID: UUID?

    @ObservationIgnored
    private var requestTask: Task<Void, Never>?

    var draft = ""
    var showsActionsMenu = false
    private(set) var entries: [FinderAIConversationEntry] = []
    private(set) var selection: AIActiveProviderSelection?
    private(set) var pendingApproval: FinderAIToolApprovalRequest?
    private(set) var phase: FinderAIConversationPhase = .loading
    private(set) var statusMessage: String?
    private(set) var configurationIssue: FinderAIConfigurationIssue?

    init(
        runtime: any AIProviderRuntimeServicing,
        workspace: any FinderAIWorkspaceQuerying,
        toolExecutor: any FinderAIToolExecuting,
        onGoBack: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenPermissionsSettings: @escaping () -> Void = {}
    ) {
        self.runtime = runtime
        self.workspace = workspace
        self.toolExecutor = toolExecutor
        self.onGoBack = onGoBack
        self.onOpenSettings = onOpenSettings
        self.onOpenPermissionsSettings = onOpenPermissionsSettings
    }

    var isWorking: Bool {
        phase == .responding || phase == .awaitingApproval
    }

    var canSend: Bool {
        selection?.supportsTools == true
            && sessionID != nil
            && phase == .ready
            && conversationNeedsReset == false
            && draftIsTooLarge == false
            && draftWouldExceedConversationLimit == false
            && normalizedDraft.isEmpty == false
    }

    var draftIsTooLarge: Bool {
        draft.utf8.count > Self.maximumPromptBytes
    }

    var conversationNeedsReset: Bool {
        conversationInvalidationReason != nil || conversationIsAtLimit
    }

    var draftWouldExceedConversationLimit: Bool {
        guard normalizedDraft.isEmpty == false else { return false }
        let projectedMessages = providerMessages + [.user(normalizedDraft)]
        return Self.reachesConversationLimit(projectedMessages)
    }

    var composerHint: String {
        switch conversationInvalidationReason {
        case .connectionChanged:
            return "The AI connection changed · clear this conversation to continue"
        case .incompleteApprovedMutation:
            return "An approved Finder operation may have changed files, but the provider transcript is incomplete · clear this conversation to continue"
        case nil:
            break
        }
        if conversationIsAtLimit {
            return "Conversation limit reached · clear it from Actions to continue"
        }
        if draftIsTooLarge {
            return "Prompt is too large · shorten it to continue"
        }
        if draftWouldExceedConversationLimit {
            return "This prompt would exceed the conversation limit · shorten it to continue"
        }
        if pendingApproval != nil {
            return "Review the one-time plan above · choose Approve Once or Deny"
        }
        if phase == .responding {
            return "Finder AI is working · Escape stops this request"
        }
        return "Return sends · content reads and file changes require approval"
    }

    var configurationMessage: String? {
        guard phase == .unavailable else { return nil }
        switch configurationIssue {
        case .missingConnection:
            return "Connect an AI provider and choose a tool-capable model in AI Settings."
        case .unsupportedModel:
            return "The active model isn’t configured for tool use. Choose a tool-capable model in AI Settings."
        case .missingAuthorizedFolders:
            return "Finder AI needs at least one specific folder in Permissions. Home, folders above Home, and whole volumes are intentionally excluded."
        case .loadFailed:
            return "Finder AI couldn’t load its connection or authorized folders. Check the settings, then try again."
        case nil:
            return nil
        }
    }

    var needsFolderAuthorization: Bool {
        configurationIssue == .missingAuthorizedFolders
    }

    var providerLabel: String? {
        guard let selection else { return nil }
        return "\(selection.providerName) · \(selection.modelName)"
    }

    var providerDisclosureMessage: String {
        let providerName = selection?.providerName ?? "the selected provider"
        return "Your prompt and bounded file metadata and tool results are sent directly to \(providerName). File contents are sent only after you approve a read."
    }

    var approvalProviderName: String? {
        conversationSelection?.providerName ?? selection?.providerName
    }

    var footerActions: [CommandActionDescriptor] {
        if pendingApproval != nil {
            return [
                CommandActionDescriptor(
                    id: FinderAIActionID.approve,
                    title: "Approve Once",
                    isPrimary: true
                ),
                CommandActionDescriptor(
                    id: FinderAIActionID.deny,
                    title: "Deny",
                    keyHint: .escape
                ),
            ]
        }
        if phase == .responding {
            return [
                CommandActionDescriptor(
                    id: FinderAIActionID.stopGeneration,
                    title: "Stop",
                    isPrimary: true,
                    keyHint: .escape
                ),
            ]
        }
        if phase == .unavailable {
            if needsFolderAuthorization {
                return [
                    CommandActionDescriptor(
                        id: FinderAIActionID.openPermissionsSettings,
                        title: "Open Permissions",
                        isPrimary: true
                    ),
                ]
            }
            return [
                CommandActionDescriptor(
                    id: FinderAIActionID.openAISettings,
                    title: "Open AI Settings",
                    isPrimary: true
                ),
            ]
        }
        return [
            CommandActionDescriptor(
                id: FinderAIActionID.send,
                title: "Send",
                isPrimary: true,
                keyHint: canSend ? .return : nil,
                isEnabled: canSend
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            ),
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        var actions: [CommandActionDescriptor] = [
            CommandActionDescriptor(
                id: FinderAIActionID.clearConversation,
                title: "Clear Conversation",
                isEnabled: entries.isEmpty == false
                    && isWorking == false
                    && phase != .loading
            ),
            CommandActionDescriptor(
                id: FinderAIActionID.openAISettings,
                title: "Open AI Settings"
            ),
            CommandActionDescriptor(
                id: FinderAIActionID.openPermissionsSettings,
                title: "Manage Finder Folders"
            ),
        ]
        if phase == .responding {
            actions.insert(
                CommandActionDescriptor(id: FinderAIActionID.stopGeneration, title: "Stop"),
                at: 0
            )
        }
        return actions
    }

    func start() async {
        guard didStart == false else { return }
        didStart = true
        let lifecycleID = beginLifecycle()
        phase = .loading
        let resolvedSession = await workspace.beginSession()
        guard isCurrentLifecycle(lifecycleID), didStart else {
            await workspace.endSession(resolvedSession)
            return
        }
        sessionID = resolvedSession
        do {
            let resolvedSelection = try await runtime.activeSelection()
            let roots = try await workspace.authorizedRoots(in: resolvedSession)
            try Task.checkCancellation()
            guard isCurrentLifecycle(lifecycleID), didStart else { return }
            applyConfiguration(
                selection: resolvedSelection,
                hasAuthorizedRoots: roots.isEmpty == false,
                readyStatus: "Finder access stays limited to folders selected in Permissions."
            )
        } catch is CancellationError {
            guard isCurrentLifecycle(lifecycleID) else { return }
            sessionID = nil
            didStart = false
            _ = beginLifecycle()
            await workspace.endSession(resolvedSession)
        } catch {
            guard isCurrentLifecycle(lifecycleID), didStart else { return }
            phase = .unavailable
            configurationIssue = .loadFailed
            statusMessage = "Finder AI configuration couldn’t be loaded."
        }
    }

    func send() {
        guard canSend,
              let selection,
              let sessionID else { return }
        if let pinnedSelection = conversationSelection {
            guard Self.isSameConnection(pinnedSelection, selection) else {
                invalidateConversationForConnectionChange()
                return
            }
        } else {
            conversationSelection = selection
        }
        let prompt = normalizedDraft
        draft = ""
        statusMessage = nil
        entries.append(FinderAIConversationEntry(role: .user, text: prompt))
        providerMessages.append(.user(prompt))
        phase = .responding
        let turnID = UUID()
        activeTurnID = turnID
        let currentLifecycleID = lifecycleID
        requestTask = Task { [weak self] in
            await self?.runProviderLoop(
                selection: selection,
                sessionID: sessionID,
                turnID: turnID,
                lifecycleID: currentLifecycleID
            )
        }
    }

    func approvePendingRequest() {
        guard pendingApproval != nil,
              approvalTurnID == activeTurnID else { return }
        phase = .responding
        statusMessage = "Executing the approved plan…"
        resolveApproval(true)
    }

    func denyPendingRequest() {
        guard pendingApproval != nil,
              approvalTurnID == activeTurnID else { return }
        phase = .responding
        statusMessage = "The proposed action was denied."
        resolveApproval(false)
    }

    func clearConversation() {
        guard isWorking == false,
              phase != .loading,
              let previousSessionID = sessionID else { return }
        let lifecycleID = beginLifecycle()
        sessionID = nil
        phase = .loading
        resetConversation()
        statusMessage = "Clearing the isolated Finder session…"
        Task { [weak self] in
            await self?.rotateSession(
                ending: previousSessionID,
                lifecycleID: lifecycleID
            )
        }
    }

    func refreshConnection() {
        guard isWorking == false, phase != .loading else { return }
        let lifecycleID = beginLifecycle()
        Task { [weak self] in
            guard let self else { return }
            do {
                let refreshedSelection = try await runtime.activeSelection()
                let roots: [FinderAIRootSummary]
                if let sessionID {
                    roots = try await workspace.authorizedRoots(in: sessionID)
                } else {
                    roots = []
                }
                guard isCurrentLifecycle(lifecycleID), didStart else { return }
                updateConversationPin(for: refreshedSelection)
                applyConfiguration(
                    selection: refreshedSelection,
                    hasAuthorizedRoots: roots.isEmpty == false,
                    readyStatus: nil
                )
                statusMessage = invalidationStatusMessage ?? statusMessage
            } catch {
                guard isCurrentLifecycle(lifecycleID), didStart else { return }
                phase = .unavailable
                configurationIssue = .loadFailed
                statusMessage = "Finder AI configuration couldn’t be loaded."
            }
        }
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case FinderAIActionID.send:
            send()
        case FinderAIActionID.stopGeneration:
            cancelCurrentRequest()
        case FinderAIActionID.approve:
            approvePendingRequest()
        case FinderAIActionID.deny:
            denyPendingRequest()
        case FinderAIActionID.clearConversation:
            clearConversation()
        case FinderAIActionID.openAISettings:
            onOpenSettings()
        case FinderAIActionID.openPermissionsSettings:
            onOpenPermissionsSettings()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            onGoBack()
        default:
            break
        }
    }

    func moveSelection(offset _: Int) {}

    func goBack() {
        onGoBack()
    }

    func handleEscape() -> Bool {
        if pendingApproval != nil {
            denyPendingRequest()
            return true
        }
        if phase == .responding {
            cancelCurrentRequest()
            return true
        }
        if draft.isEmpty == false {
            draft = ""
            return true
        }
        return false
    }

    func stop() {
        let wasWorking = isWorking
        requestTask?.cancel()
        resolveApproval(false)
        rollbackIncompleteToolTurn()
        activeTurnID = nil
        requestTask = nil
        _ = beginLifecycle()
        didStart = false
        selection = nil
        configurationIssue = nil
        resetConversation()
        phase = .loading
        statusMessage = wasWorking ? "Request stopped." : nil
        guard let sessionID else { return }
        self.sessionID = nil
        Task { [workspace] in
            await workspace.endSession(sessionID)
        }
    }

    private func runProviderLoop(
        selection: AIActiveProviderSelection,
        sessionID: FinderAISessionID,
        turnID: UUID,
        lifecycleID: UUID
    ) async {
        var toolCallCount = 0
        var toolArgumentByteCount = 0
        var toolResultByteCount = 0

        do {
            for _ in 0 ..< Self.maximumProviderRounds {
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                try Task.checkCancellation()
                try await validatePinnedConnection(
                    selection,
                    turnID: turnID,
                    lifecycleID: lifecycleID
                )
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                try Task.checkCancellation()
                let response = try await runtime.complete(
                    AICompletionRequest(
                        modelID: selection.modelID,
                        messages: providerMessages,
                        tools: toolExecutor.definitions,
                        maximumOutputTokens: 2_048,
                        state: providerState
                    ),
                    providerID: selection.providerID,
                    connectionRevision: selection.connectionRevision
                )
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                try Task.checkCancellation()
                try await validatePinnedConnection(
                    selection,
                    turnID: turnID,
                    lifecycleID: lifecycleID
                )
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                try Task.checkCancellation()

                let calls = response.message.toolCalls
                try Self.validateFinishReason(response.finishReason, hasToolCalls: calls.isEmpty == false)
                guard calls.count <= Self.maximumCallsPerRound,
                      toolCallCount + calls.count <= Self.maximumToolCalls else {
                    throw FinderAIConversationError.toolLimitReached
                }
                let argumentByteCount = try Self.validateAssistantMessage(
                    response.message,
                    allowedToolNames: Set(toolExecutor.definitions.map(\.name))
                )
                guard argumentByteCount <= Self.maximumToolArgumentBytesPerConversation
                        - toolArgumentByteCount else {
                    throw FinderAIConversationError.toolArgumentsTooLarge
                }
                guard Self.reachesConversationLimit(
                    providerMessages + [response.message]
                ) == false else {
                    throw FinderAIConversationError.conversationLimitReached
                }
                toolCallCount += calls.count
                toolArgumentByteCount += argumentByteCount

                if calls.isEmpty {
                    providerMessages.append(response.message)
                    providerState = response.state
                    if let text = Self.text(from: response.message), text.isEmpty == false {
                        entries.append(FinderAIConversationEntry(role: .assistant, text: text))
                    }
                    finishTurn(
                        turnID,
                        lifecycleID: lifecycleID,
                        statusMessage: Self.terminalStatusMessage(for: response.finishReason)
                    )
                    return
                }

                incompleteToolTurnMessageIndex = providerMessages.count
                incompleteToolTurnHasApprovedMutation = false
                providerMessages.append(response.message)

                var results: [AIToolResult] = []
                results.reserveCapacity(calls.count)
                for call in calls {
                    try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                    try Task.checkCancellation()
                    let result = try await execute(
                        call,
                        in: sessionID,
                        selection: selection,
                        turnID: turnID,
                        lifecycleID: lifecycleID
                    )
                    try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                    try Task.checkCancellation()
                    let resultByteCount = Self.serializedByteCount(of: result)
                    guard resultByteCount <= Self.maximumToolResultBytes - toolResultByteCount else {
                        throw FinderAIConversationError.toolPayloadLimitReached
                    }
                    toolResultByteCount += resultByteCount
                    results.append(result)
                }
                let toolMessage = AIMessage.tool(results: results)
                guard Self.reachesConversationLimit(
                    providerMessages + [toolMessage]
                ) == false else {
                    throw FinderAIConversationError.conversationLimitReached
                }
                providerMessages.append(toolMessage)
                incompleteToolTurnMessageIndex = nil
                incompleteToolTurnHasApprovedMutation = false
                providerState = response.state
                if let text = Self.text(from: response.message), text.isEmpty == false {
                    entries.append(FinderAIConversationEntry(role: .assistant, text: text))
                }
                phase = .responding
            }
            throw FinderAIConversationError.roundLimitReached
        } catch is CancellationError {
            guard isCurrentTurn(turnID, lifecycleID: lifecycleID) else { return }
            rollbackIncompleteToolTurn()
            finishTurn(
                turnID,
                lifecycleID: lifecycleID,
                statusMessage: invalidationStatusMessage ?? "Request stopped."
            )
        } catch let error as AIProviderError where error == .cancelled {
            guard isCurrentTurn(turnID, lifecycleID: lifecycleID) else { return }
            rollbackIncompleteToolTurn()
            finishTurn(
                turnID,
                lifecycleID: lifecycleID,
                statusMessage: invalidationStatusMessage ?? "Request stopped."
            )
        } catch {
            guard isCurrentTurn(turnID, lifecycleID: lifecycleID) else { return }
            rollbackIncompleteToolTurn()
            if Self.isConnectionChange(error) {
                conversationInvalidationReason = conversationInvalidationReason ?? .connectionChanged
            }
            entries.append(FinderAIConversationEntry(
                role: .error,
                text: Self.userMessage(for: error)
            ))
            finishTurn(
                turnID,
                lifecycleID: lifecycleID,
                statusMessage: invalidationStatusMessage
            )
        }
    }

    private func execute(
        _ call: AIToolCall,
        in sessionID: FinderAISessionID,
        selection: AIActiveProviderSelection,
        turnID: UUID,
        lifecycleID: UUID
    ) async throws -> AIToolResult {
        switch await toolExecutor.execute(call, in: sessionID) {
        case .completed(let result):
            try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
            try Task.checkCancellation()
            guard Self.isCorrelated(result, with: call) else {
                throw FinderAIConversationError.invalidToolCalls
            }
            entries.append(contentsOf: Self.activityEntries(for: result))
            return result
        case .requiresApproval(let approval):
            try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
            try Task.checkCancellation()
            pendingApproval = approval
            approvalTurnID = turnID
            phase = .awaitingApproval
            statusMessage = "Review the exact Finder plan before it runs."
            let isApproved = await waitForApproval(turnID: turnID)
            try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
            try Task.checkCancellation()
            let result: AIToolResult
            if isApproved {
                try await validatePinnedConnection(
                    selection,
                    turnID: turnID,
                    lifecycleID: lifecycleID
                )
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                try Task.checkCancellation()
                result = await toolExecutor.executeApproved(approval, in: sessionID)
                try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
                guard Self.isCorrelated(result, with: call) else {
                    throw FinderAIConversationError.invalidToolCalls
                }
                entries.append(contentsOf: Self.activityEntries(for: result))
                if toolExecutor.definitions.first(where: { $0.name == call.name })?.effect
                    != .readOnly {
                    incompleteToolTurnHasApprovedMutation = true
                }
                try Task.checkCancellation()
                return result
            } else {
                result = toolExecutor.denied(approval)
            }
            guard Self.isCorrelated(result, with: call) else {
                throw FinderAIConversationError.invalidToolCalls
            }
            entries.append(contentsOf: Self.activityEntries(for: result))
            return result
        }
    }

    private func waitForApproval(turnID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            guard activeTurnID == turnID else {
                continuation.resume(returning: false)
                return
            }
            approvalContinuation = continuation
        }
    }

    private func resolveApproval(_ approved: Bool) {
        let continuation = approvalContinuation
        approvalContinuation = nil
        pendingApproval = nil
        approvalTurnID = nil
        continuation?.resume(returning: approved)
    }

    private func cancelCurrentRequest() {
        guard let requestTask else { return }
        requestTask.cancel()
        resolveApproval(false)
        phase = .responding
        statusMessage = "Stopping request…"
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conversationIsAtLimit: Bool {
        Self.reachesConversationLimit(providerMessages)
    }

    private func beginLifecycle() -> UUID {
        let identifier = UUID()
        lifecycleID = identifier
        return identifier
    }

    private func isCurrentLifecycle(_ identifier: UUID) -> Bool {
        lifecycleID == identifier
    }

    private func isCurrentTurn(_ turnID: UUID, lifecycleID: UUID) -> Bool {
        activeTurnID == turnID && isCurrentLifecycle(lifecycleID) && didStart
    }

    private func checkCurrentTurn(_ turnID: UUID, lifecycleID: UUID) throws {
        guard isCurrentTurn(turnID, lifecycleID: lifecycleID) else {
            throw FinderAIConversationError.staleTurn
        }
    }

    private func rotateSession(
        ending previousSessionID: FinderAISessionID,
        lifecycleID: UUID
    ) async {
        await workspace.endSession(previousSessionID)
        let replacementSessionID = await workspace.beginSession()
        guard isCurrentLifecycle(lifecycleID), didStart else {
            await workspace.endSession(replacementSessionID)
            return
        }
        sessionID = replacementSessionID
        do {
            let refreshedSelection = try await runtime.activeSelection()
            let roots = try await workspace.authorizedRoots(in: replacementSessionID)
            try Task.checkCancellation()
            guard isCurrentLifecycle(lifecycleID), didStart else { return }
            applyConfiguration(
                selection: refreshedSelection,
                hasAuthorizedRoots: roots.isEmpty == false,
                readyStatus: "Conversation cleared. A new isolated Finder session is ready."
            )
        } catch is CancellationError {
            guard isCurrentLifecycle(lifecycleID) else { return }
            sessionID = nil
            await workspace.endSession(replacementSessionID)
        } catch {
            guard isCurrentLifecycle(lifecycleID), didStart else { return }
            phase = .unavailable
            configurationIssue = .loadFailed
            statusMessage = "Finder AI configuration couldn’t be loaded."
        }
    }

    private func resetConversation() {
        entries = []
        providerMessages = [.system(Self.systemPrompt)]
        providerState = nil
        conversationSelection = nil
        conversationInvalidationReason = nil
        incompleteToolTurnMessageIndex = nil
        incompleteToolTurnHasApprovedMutation = false
    }

    private func applyConfiguration(
        selection: AIActiveProviderSelection?,
        hasAuthorizedRoots: Bool,
        readyStatus: String?
    ) {
        self.selection = selection
        if selection == nil {
            configurationIssue = .missingConnection
            phase = .unavailable
            statusMessage = nil
        } else if selection?.supportsTools == false {
            configurationIssue = .unsupportedModel
            phase = .unavailable
            statusMessage = nil
        } else if hasAuthorizedRoots == false {
            configurationIssue = .missingAuthorizedFolders
            phase = .unavailable
            statusMessage = nil
        } else {
            configurationIssue = nil
            phase = .ready
            statusMessage = readyStatus
        }
    }

    private func updateConversationPin(for refreshedSelection: AIActiveProviderSelection?) {
        guard let pinnedSelection = conversationSelection else { return }
        guard let refreshedSelection,
              Self.isSameConnection(pinnedSelection, refreshedSelection) else {
            invalidateConversationForConnectionChange()
            return
        }
    }

    private func invalidateConversationForConnectionChange() {
        conversationInvalidationReason = .connectionChanged
        statusMessage = "The AI connection changed. Clear this conversation before continuing."
    }

    private func validatePinnedConnection(
        _ pinnedSelection: AIActiveProviderSelection,
        turnID: UUID,
        lifecycleID: UUID
    ) async throws {
        let activeSelection = try await runtime.activeSelection()
        try checkCurrentTurn(turnID, lifecycleID: lifecycleID)
        try Task.checkCancellation()
        guard let activeSelection,
              activeSelection.supportsTools,
              Self.isSameConnection(pinnedSelection, activeSelection) else {
            throw FinderAIConversationError.connectionChanged
        }
    }

    private func finishTurn(
        _ turnID: UUID,
        lifecycleID: UUID,
        statusMessage: String?
    ) {
        guard isCurrentTurn(turnID, lifecycleID: lifecycleID) else { return }
        resolveApproval(false)
        incompleteToolTurnMessageIndex = nil
        incompleteToolTurnHasApprovedMutation = false
        activeTurnID = nil
        requestTask = nil
        phase = selection?.supportsTools == true
            && sessionID != nil
            && configurationIssue == nil ? .ready : .unavailable
        self.statusMessage = statusMessage
    }

    private func rollbackIncompleteToolTurn() {
        guard let messageIndex = incompleteToolTurnMessageIndex else { return }
        let requiresReset = incompleteToolTurnHasApprovedMutation
        if providerMessages.indices.contains(messageIndex) {
            providerMessages.removeSubrange(messageIndex...)
        }
        incompleteToolTurnMessageIndex = nil
        incompleteToolTurnHasApprovedMutation = false
        if requiresReset {
            conversationInvalidationReason = conversationInvalidationReason
                ?? .incompleteApprovedMutation
        }
    }

    private var invalidationStatusMessage: String? {
        switch conversationInvalidationReason {
        case .connectionChanged:
            "The AI connection changed. Clear this conversation before continuing."
        case .incompleteApprovedMutation:
            "An approved Finder operation may have changed files, but the provider transcript is incomplete. Clear this conversation before continuing."
        case nil:
            nil
        }
    }

    private static func isSameConnection(
        _ left: AIActiveProviderSelection,
        _ right: AIActiveProviderSelection
    ) -> Bool {
        left.providerID == right.providerID
            && left.modelID == right.modelID
            && left.connectionRevision == right.connectionRevision
    }

    private static func isCorrelated(_ result: AIToolResult, with call: AIToolCall) -> Bool {
        result.callID == call.id && result.toolName == call.name
    }

    private static func isConnectionChange(_ error: Error) -> Bool {
        switch error {
        case FinderAIConversationError.connectionChanged,
             AIProviderRuntimeError.connectionMismatch,
             AIProviderRuntimeError.modelMismatch,
             AIProviderRuntimeError.noActiveConnection,
             AIProviderRuntimeError.toolsUnsupported:
            true
        default:
            false
        }
    }

    private static func validateAssistantMessage(
        _ message: AIMessage,
        allowedToolNames: Set<String>
    ) throws -> Int {
        guard message.role == .assistant,
              message.toolResults.isEmpty,
              message.content.count <= 8,
              message.content.isEmpty == false || message.toolCalls.isEmpty == false else {
            throw FinderAIConversationError.invalidToolCalls
        }

        var textByteCount = 0
        var hasNonemptyText = false
        for content in message.content {
            guard case .text(let text) = content else {
                throw FinderAIConversationError.unsupportedAssistantContent
            }
            hasNonemptyText = hasNonemptyText || text.isEmpty == false
            let byteCount = text.utf8.count
            guard byteCount < maximumConversationBytes - textByteCount else {
                throw FinderAIConversationError.conversationLimitReached
            }
            textByteCount += byteCount
        }
        guard hasNonemptyText || message.toolCalls.isEmpty == false else {
            throw FinderAIConversationError.unsupportedAssistantContent
        }

        guard message.toolCalls.allSatisfy({ call in
            call.id.isEmpty == false && call.id.utf8.count <= 256
        }), Set(message.toolCalls.map(\.id)).count == message.toolCalls.count else {
            throw FinderAIConversationError.invalidToolCalls
        }

        var argumentByteCount = 0
        for call in message.toolCalls {
            guard isPortableToolName(call.name),
                  allowedToolNames.contains(call.name),
                  call.arguments.objectValue != nil else {
                throw FinderAIConversationError.invalidToolCalls
            }
            let callByteCount = boundedJSONByteCount(
                call.arguments,
                limit: maximumToolArgumentBytes
            )
            guard callByteCount <= maximumToolArgumentBytes,
                  callByteCount <= maximumToolArgumentBytesPerConversation
                    - argumentByteCount else {
                throw FinderAIConversationError.toolArgumentsTooLarge
            }
            argumentByteCount += callByteCount
        }
        return argumentByteCount
    }

    private static func validateFinishReason(
        _ finishReason: AIFinishReason,
        hasToolCalls: Bool
    ) throws {
        if hasToolCalls {
            guard finishReason == .toolCalls else {
                throw FinderAIConversationError.invalidFinishReason
            }
            return
        }
        guard finishReason != .toolCalls, finishReason != .unknown else {
            throw FinderAIConversationError.invalidFinishReason
        }
    }

    private static func terminalStatusMessage(for finishReason: AIFinishReason) -> String? {
        switch finishReason {
        case .completed:
            nil
        case .length:
            "The provider stopped at its output limit, so this response may be incomplete."
        case .contentFiltered:
            "The provider stopped this response because of its content policy."
        case .refused:
            "The provider declined this request."
        case .toolCalls, .unknown:
            nil
        }
    }

    private static func isPortableToolName(_ name: String) -> Bool {
        let bytes = name.utf8
        guard bytes.isEmpty == false, bytes.count <= maximumToolNameBytes else { return false }
        return bytes.allSatisfy { byte in
            (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
                || (48 ... 57).contains(byte)
                || byte == 45
                || byte == 95
        }
    }

    private static func boundedJSONByteCount(
        _ value: AIJSONValue,
        limit: Int,
        depth: Int = 0
    ) -> Int {
        guard depth <= 64 else { return limit + 1 }
        switch value {
        case .null:
            return 4
        case .boolean:
            return 5
        case .number:
            return 32
        case .string(let value):
            return conservativeJSONStringByteCount(value, limit: limit)
        case .array(let values):
            var count = 2
            for value in values {
                count = boundedSum(
                    count,
                    boundedJSONByteCount(value, limit: limit, depth: depth + 1) + 1,
                    limit: limit
                )
                if count > limit { return count }
            }
            return count
        case .object(let values):
            var count = 2
            for (key, value) in values {
                count = boundedSum(
                    count,
                    conservativeJSONStringByteCount(key, limit: limit) + 1,
                    limit: limit
                )
                count = boundedSum(
                    count,
                    boundedJSONByteCount(value, limit: limit, depth: depth + 1) + 1,
                    limit: limit
                )
                if count > limit { return count }
            }
            return count
        }
    }

    private static func conservativeJSONStringByteCount(_ value: String, limit: Int) -> Int {
        var count = 2
        for scalar in value.unicodeScalars {
            let scalarByteCount: Int
            switch scalar.value {
            case 0 ... 31:
                scalarByteCount = 6
            case 34, 47, 92:
                scalarByteCount = 2
            default:
                scalarByteCount = scalar.utf8.count
            }
            count = boundedSum(count, scalarByteCount, limit: limit)
            if count > limit { return count }
        }
        return count
    }

    private static func boundedSum(_ left: Int, _ right: Int, limit: Int) -> Int {
        guard left <= limit, right <= limit - left else { return limit + 1 }
        return left + right
    }

    private static func text(from message: AIMessage) -> String? {
        let values = message.content.compactMap { content -> String? in
            guard case .text(let text) = content else { return nil }
            return text
        }
        guard values.isEmpty == false else { return nil }
        return values.joined(separator: "\n")
    }

    private static func activityEntries(for result: AIToolResult) -> [FinderAIConversationEntry] {
        guard let itemizedResults = result.content["results"]?.arrayValue else {
            return [FinderAIConversationEntry(
                role: result.isError ? .error : .activity,
                text: result.isError
                    ? "Finder tool \(result.toolName) couldn’t complete."
                    : "Finder tool \(result.toolName) completed."
            )]
        }
        let statuses = itemizedResults.map { MutationItemStatus($0["status"]?.stringValue) }
        let reportStatus = MutationReportStatus(statuses: statuses)
        var entries = [FinderAIConversationEntry(
            role: reportStatus == .completed ? .activity : .error,
            text: reportStatus.summary(
                toolName: result.toolName,
                totalCount: statuses.count,
                completedCount: statuses.count { $0 == .completed }
            )
        )]
        entries.append(contentsOf: itemizedResults.compactMap { value in
            guard let name = value["name"]?.stringValue else { return nil }
            let status = MutationItemStatus(value["status"]?.stringValue)
            return FinderAIConversationEntry(
                role: status == .completed ? .activity : .error,
                text: "\(name): \(status.presentationLabel)."
            )
        })
        return entries
    }

    private enum MutationItemStatus: Equatable {
        case completed
        case failed
        case cancelled
        case unavailable

        init(_ rawValue: String?) {
            switch rawValue {
            case "completed": self = .completed
            case "failed": self = .failed
            case "cancelled": self = .cancelled
            default: self = .unavailable
            }
        }

        var presentationLabel: String {
            switch self {
            case .completed: "completed"
            case .failed: "failed"
            case .cancelled: "cancelled"
            case .unavailable: "outcome unavailable"
            }
        }
    }

    private enum MutationReportStatus: Equatable {
        case completed
        case partial
        case failed
        case cancelled

        init(statuses: [MutationItemStatus]) {
            let completedCount = statuses.count { $0 == .completed }
            guard statuses.isEmpty == false else {
                self = .failed
                return
            }
            if completedCount == statuses.count {
                self = .completed
            } else if completedCount > 0 {
                self = .partial
            } else if statuses.allSatisfy({ $0 == .cancelled }) {
                self = .cancelled
            } else {
                self = .failed
            }
        }

        func summary(
            toolName: String,
            totalCount: Int,
            completedCount: Int
        ) -> String {
            switch self {
            case .completed:
                let noun = totalCount == 1 ? "operation" : "operations"
                return "Finder tool \(toolName) completed \(totalCount) \(noun)."
            case .partial:
                return "Finder tool \(toolName) partially completed: \(completedCount) of \(totalCount) operations succeeded."
            case .failed:
                return "Finder tool \(toolName) failed; no operations completed."
            case .cancelled:
                return "Finder tool \(toolName) was cancelled; no operations completed."
            }
        }
    }

    private static func userMessage(for error: Error) -> String {
        switch error {
        case AIProviderRuntimeError.noActiveConnection:
            "No active AI connection is configured."
        case AIProviderRuntimeError.credentialUnavailable:
            "The active provider credential isn’t available in Keychain."
        case AIProviderRuntimeError.toolsUnsupported:
            "The active model or provider doesn’t support Finder tools."
        case AIProviderRuntimeError.modelMismatch,
             AIProviderRuntimeError.connectionMismatch,
             FinderAIConversationError.connectionChanged:
            "The active AI connection changed. Clear the conversation before continuing."
        case AIProviderRuntimeError.providerUnavailable:
            "The active provider is unavailable. Revalidate it in AI Settings."
        case AIProviderError.invalidCredential:
            "The provider rejected the saved credential. Revalidate it in AI Settings."
        case AIProviderError.rateLimited:
            "The provider reached a rate or quota limit. Try again shortly; if it persists, check account credits and spending limits."
        case AIProviderError.billingUnavailable:
            "The provider reports that billing isn’t available for this request."
        case AIProviderError.invalidRequest:
            "The provider couldn’t complete that request."
        case FinderAIConversationError.toolLimitReached,
             FinderAIConversationError.roundLimitReached,
             FinderAIConversationError.invalidToolCalls,
             FinderAIConversationError.invalidFinishReason,
             FinderAIConversationError.toolArgumentsTooLarge,
             FinderAIConversationError.unsupportedAssistantContent:
            "The request stopped after reaching Commandly’s safety limit. Try a smaller task."
        case FinderAIConversationError.toolPayloadLimitReached:
            "The approved tool results were too large to send. Try fewer files or a smaller content limit."
        case FinderAIConversationError.conversationLimitReached:
            "The provider response would exceed the conversation limit. Clear the conversation or try a smaller task."
        default:
            "The AI request couldn’t be completed. No unapproved Finder action was run."
        }
    }

    private static let systemPrompt = """
        You are Commandly Finder AI, a local file-workspace assistant. Work only through the supplied
        Finder tools. Tool arguments use opaque root and item handles; never invent handles or ask for
        absolute paths. Search or list before acting. Explain uncertainty. Reading file contents and
        every filesystem mutation require a separate local user approval that you cannot grant. Never
        claim an operation succeeded until its tool result says it completed. Deletion means moving to
        Trash only. Do not request shell commands, AppleScript, permanent deletion, permission changes,
        hidden-file traversal, or access outside the authorized roots. Prefer the smallest exact action.
        Request at most one content read at a time and use the smallest useful byte limit.
        """

    private static func serializedByteCount(of messages: [AIMessage]) -> Int {
        messages.reduce(0) { partialResult, message in
            let count = (try? JSONEncoder().encode(message).count) ?? maximumConversationBytes
            return min(maximumConversationBytes, partialResult + count)
        }
    }

    private static func reachesConversationLimit(_ messages: [AIMessage]) -> Bool {
        messages.count >= maximumConversationMessages
            || serializedByteCount(of: messages) >= maximumConversationBytes
    }

    private static func serializedByteCount(of result: AIToolResult) -> Int {
        (try? JSONEncoder().encode(result).count) ?? maximumToolResultBytes + 1
    }
}

private nonisolated enum FinderAIConversationError: Error, Sendable {
    case toolLimitReached
    case roundLimitReached
    case toolPayloadLimitReached
    case toolArgumentsTooLarge
    case conversationLimitReached
    case invalidToolCalls
    case invalidFinishReason
    case unsupportedAssistantContent
    case connectionChanged
    case staleTurn
}
