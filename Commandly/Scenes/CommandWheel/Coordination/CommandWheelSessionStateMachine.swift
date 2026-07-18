import Foundation

nonisolated struct CommandWheelSessionToken: Hashable, Sendable, Equatable {
    let identifier: UUID
    let generation: UInt64
}

nonisolated struct CommandWheelSession: Sendable, Equatable {
    let token: CommandWheelSessionToken
    let profileID: UUID
    let rootPageID: UUID
    let currentPageID: UUID

    func moving(to pageID: UUID) -> CommandWheelSession {
        CommandWheelSession(
            token: token,
            profileID: profileID,
            rootPageID: rootPageID,
            currentPageID: pageID
        )
    }
}

nonisolated struct CommandWheelPageTransition: Sendable, Equatable {
    let session: CommandWheelSession
    let fromPageID: UUID
    let toPageID: UUID
}

nonisolated struct CommandWheelExecutionRequest: Sendable, Equatable {
    let session: CommandWheelSession
    let slotIndex: Int
}

nonisolated enum CommandWheelCancellationReason: Sendable, Equatable {
    case releasedWithoutSelection
    case explicit
    case shortcutInvalidated
    case displayUnavailable
    case contextLost
    case inputUnavailable
    case featureDisabled
    case applicationTerminating
}

nonisolated enum CommandWheelDismissalReason: Sendable, Equatable {
    case cancelled(CommandWheelCancellationReason)
    case executionCompleted
    case failure
}

nonisolated enum CommandWheelFailureReason: Sendable, Equatable {
    case profileUnavailable
    case pageUnavailable
    case providerFailed
    case presentationFailed
    case invalidTransition
}

nonisolated struct CommandWheelFailureState: Sendable, Equatable {
    let session: CommandWheelSession
    let reason: CommandWheelFailureReason
}

nonisolated enum CommandWheelPresentationState: Sendable, Equatable {
    case idle
    case preparing(CommandWheelSession)
    case presenting(CommandWheelSession)
    case tracking(CommandWheelSession, selection: CommandWheelSelection?)
    case transitioning(CommandWheelPageTransition)
    case executing(CommandWheelExecutionRequest)
    case dismissing(CommandWheelSession, reason: CommandWheelDismissalReason)
    case failed(CommandWheelFailureState)

    var session: CommandWheelSession? {
        switch self {
        case .idle:
            return nil
        case .preparing(let session), .presenting(let session),
             .tracking(let session, _), .dismissing(let session, _):
            return session
        case .transitioning(let transition):
            return transition.session
        case .executing(let request):
            return request.session
        case .failed(let failure):
            return failure.session
        }
    }
}

nonisolated enum CommandWheelMutationIgnoreReason: Sendable, Equatable {
    case duplicatePress
    case duplicateRelease
    case executionAlreadyRequested
    case staleSession
    case noActiveSession
    case invalidTransition
    case duplicateProviderTask
}

nonisolated enum CommandWheelMutationResult: Sendable, Equatable {
    case applied
    case ignored(CommandWheelMutationIgnoreReason)
}

nonisolated enum CommandWheelBeginResult: Sendable, Equatable {
    case started(CommandWheelSessionToken)
    case ignored(CommandWheelMutationIgnoreReason)
}

nonisolated struct CommandWheelProviderTaskID: Hashable, Sendable, Equatable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Main-actor state machine for exactly one Command Wheel invocation.
///
/// All asynchronous completions must present their session token. A token combines a UUID with a
/// monotonically increasing generation, so even a deterministic or faulty UUID source cannot make
/// work from an older invocation valid for a newer one. The machine owns provider tasks registered
/// for the active session and cancels them on page transitions and every terminal path.
@MainActor
final class CommandWheelSessionStateMachine {
    private(set) var state: CommandWheelPresentationState = .idle
    private(set) var providerTaskCount = 0

    private let makeUUID: () -> UUID
    private var nextGeneration: UInt64 = 0
    private var acceptedReleaseToken: CommandWheelSessionToken?
    private var executionRequestedToken: CommandWheelSessionToken?
    private var providerTasks: [CommandWheelProviderTaskID: Task<Void, Never>] = [:]

    init(makeUUID: @escaping () -> UUID = UUID.init) {
        self.makeUUID = makeUUID
    }

    deinit {
        for task in providerTasks.values {
            task.cancel()
        }
    }

    @discardableResult
    func shortcutPressed(profileID: UUID, rootPageID: UUID) -> CommandWheelBeginResult {
        guard case .idle = state else {
            return .ignored(.duplicatePress)
        }

        nextGeneration &+= 1
        let token = CommandWheelSessionToken(
            identifier: makeUUID(),
            generation: nextGeneration
        )
        let session = CommandWheelSession(
            token: token,
            profileID: profileID,
            rootPageID: rootPageID,
            currentPageID: rootPageID
        )
        acceptedReleaseToken = nil
        executionRequestedToken = nil
        state = .preparing(session)
        return .started(token)
    }

    @discardableResult
    func presentationBegan(sessionToken: CommandWheelSessionToken) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .preparing = state else {
            return .ignored(.invalidTransition)
        }
        state = .presenting(session)
        return .applied
    }

    @discardableResult
    func trackingBegan(sessionToken: CommandWheelSessionToken) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .presenting = state else {
            return .ignored(.invalidTransition)
        }
        state = .tracking(session, selection: nil)
        return .applied
    }

    @discardableResult
    func updateSelection(
        _ selection: CommandWheelSelection?,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .tracking = state else {
            return .ignored(.invalidTransition)
        }
        state = .tracking(session, selection: selection)
        return .applied
    }

    @discardableResult
    func beginPageTransition(
        to pageID: UUID,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .tracking = state else {
            return .ignored(.invalidTransition)
        }
        cancelProviderTasks()
        state = .transitioning(
            CommandWheelPageTransition(
                session: session,
                fromPageID: session.currentPageID,
                toPageID: pageID
            )
        )
        return .applied
    }

    @discardableResult
    func completePageTransition(
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard validatedSession(for: sessionToken) != nil else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .transitioning(let transition) = state else {
            return .ignored(.invalidTransition)
        }
        state = .tracking(transition.session.moving(to: transition.toPageID), selection: nil)
        return .applied
    }

    /// Handles the physical release that owns this activation session.
    ///
    /// Release with a current selection enters execution exactly once. Release during preparation,
    /// presentation, transition, or tracking without a selection cancels safely.
    @discardableResult
    func shortcutReleased(sessionToken: CommandWheelSessionToken) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard acceptedReleaseToken != sessionToken else {
            return .ignored(.duplicateRelease)
        }
        acceptedReleaseToken = sessionToken

        switch state {
        case .tracking(_, let selection):
            if let selection {
                return requestExecution(slotIndex: selection.slotIndex, sessionToken: sessionToken)
            }
            beginDismissal(
                session: session,
                reason: .cancelled(.releasedWithoutSelection)
            )
            return .applied

        case .preparing, .presenting, .transitioning:
            beginDismissal(
                session: session,
                reason: .cancelled(.releasedWithoutSelection)
            )
            return .applied

        case .executing, .dismissing, .failed:
            return .ignored(.duplicateRelease)

        case .idle:
            return .ignored(.noActiveSession)
        }
    }

    @discardableResult
    func requestExecution(
        slotIndex: Int,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard executionRequestedToken != sessionToken else {
            return .ignored(.executionAlreadyRequested)
        }
        guard case .tracking = state else {
            return .ignored(.invalidTransition)
        }
        executionRequestedToken = sessionToken
        cancelProviderTasks()
        state = .executing(
            CommandWheelExecutionRequest(session: session, slotIndex: slotIndex)
        )
        return .applied
    }

    @discardableResult
    func executionCompleted(sessionToken: CommandWheelSessionToken) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .executing = state else {
            return .ignored(.invalidTransition)
        }
        beginDismissal(session: session, reason: .executionCompleted)
        return .applied
    }

    @discardableResult
    func cancel(
        _ reason: CommandWheelCancellationReason,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        switch state {
        case .preparing, .presenting, .tracking, .transitioning, .executing:
            beginDismissal(session: session, reason: .cancelled(reason))
            return .applied
        case .dismissing, .failed:
            return .ignored(.invalidTransition)
        case .idle:
            return .ignored(.noActiveSession)
        }
    }

    @discardableResult
    func fail(
        _ reason: CommandWheelFailureReason,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .idle = state else {
            cancelProviderTasks()
            state = .failed(CommandWheelFailureState(session: session, reason: reason))
            return .applied
        }
        return .ignored(.noActiveSession)
    }

    @discardableResult
    func beginFailureDismissal(
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let session = validatedSession(for: sessionToken) else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .failed = state else {
            return .ignored(.invalidTransition)
        }
        beginDismissal(session: session, reason: .failure)
        return .applied
    }

    @discardableResult
    func dismissalCompleted(
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard validatedSession(for: sessionToken) != nil else {
            return staleOrMissingResult(for: sessionToken)
        }
        guard case .dismissing = state else {
            return .ignored(.invalidTransition)
        }
        cancelProviderTasks()
        state = .idle
        acceptedReleaseToken = nil
        executionRequestedToken = nil
        return .applied
    }

    @discardableResult
    func registerProviderTask(
        _ task: Task<Void, Never>,
        id: CommandWheelProviderTaskID,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard validatedSession(for: sessionToken) != nil else {
            task.cancel()
            return staleOrMissingResult(for: sessionToken)
        }
        guard acceptsProviderTasks else {
            task.cancel()
            return .ignored(.invalidTransition)
        }
        guard providerTasks[id] == nil else {
            task.cancel()
            return .ignored(.duplicateProviderTask)
        }
        providerTasks[id] = task
        providerTaskCount = providerTasks.count
        return .applied
    }

    @discardableResult
    func providerTaskCompleted(
        id: CommandWheelProviderTaskID,
        sessionToken: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard validatedSession(for: sessionToken) != nil else {
            return staleOrMissingResult(for: sessionToken)
        }
        providerTasks[id] = nil
        providerTaskCount = providerTasks.count
        return .applied
    }

    private var acceptsProviderTasks: Bool {
        switch state {
        case .preparing, .presenting, .tracking:
            return true
        case .idle, .transitioning, .executing, .dismissing, .failed:
            return false
        }
    }

    private func validatedSession(
        for token: CommandWheelSessionToken
    ) -> CommandWheelSession? {
        guard let session = state.session, session.token == token else { return nil }
        return session
    }

    private func staleOrMissingResult(
        for token: CommandWheelSessionToken
    ) -> CommandWheelMutationResult {
        guard let activeToken = state.session?.token else {
            return .ignored(.noActiveSession)
        }
        return .ignored(activeToken == token ? .invalidTransition : .staleSession)
    }

    private func beginDismissal(
        session: CommandWheelSession,
        reason: CommandWheelDismissalReason
    ) {
        cancelProviderTasks()
        state = .dismissing(session, reason: reason)
    }

    private func cancelProviderTasks() {
        for task in providerTasks.values {
            task.cancel()
        }
        providerTasks.removeAll()
        providerTaskCount = 0
    }
}
