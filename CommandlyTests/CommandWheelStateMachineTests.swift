import CoreGraphics
import Foundation
import Testing
@testable import Commandly

struct CommandWheelStateMachineTests {
    @Test @MainActor func validExecutionFlowTraversesEveryRequiredState() throws {
        let machine = makeMachine()
        let ids = SessionIDs()
        let token = try begin(machine, ids: ids)
        #expect(machine.state == .preparing(session(machine)))

        #expect(machine.presentationBegan(sessionToken: token) == .applied)
        #expect(machine.state == .presenting(session(machine)))
        #expect(machine.trackingBegan(sessionToken: token) == .applied)
        #expect(machine.state == .tracking(session(machine), selection: nil))

        let selection = makeSelection(slotIndex: 2)
        #expect(machine.updateSelection(selection, sessionToken: token) == .applied)
        #expect(machine.state == .tracking(session(machine), selection: selection))

        #expect(machine.shortcutReleased(sessionToken: token) == .applied)
        #expect(
            machine.state
                == .executing(
                    CommandWheelExecutionRequest(session: session(machine), slotIndex: 2)
                )
        )
        #expect(machine.executionCompleted(sessionToken: token) == .applied)
        #expect(
            machine.state
                == .dismissing(session(machine), reason: .executionCompleted)
        )
        #expect(machine.dismissalCompleted(sessionToken: token) == .applied)
        #expect(machine.state == .idle)
    }

    @Test @MainActor func duplicatePressDoesNotReplaceActiveSession() throws {
        let machine = makeMachine()
        let firstIDs = SessionIDs()
        let token = try begin(machine, ids: firstIDs)
        let state = machine.state

        #expect(
            machine.shortcutPressed(profileID: UUID(), rootPageID: UUID())
                == .ignored(.duplicatePress)
        )
        #expect(machine.state == state)
        #expect(machine.state.session?.token == token)
    }

    @Test @MainActor func releaseBeforePresentationCancelsSafely() throws {
        let machine = makeMachine()
        let token = try begin(machine, ids: SessionIDs())

        #expect(machine.shortcutReleased(sessionToken: token) == .applied)
        #expect(
            machine.state
                == .dismissing(
                    session(machine),
                    reason: .cancelled(.releasedWithoutSelection)
                )
        )
    }

    @Test @MainActor func releaseWithoutTrackedSelectionCancels() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)

        #expect(machine.shortcutReleased(sessionToken: token) == .applied)
        guard case .dismissing(_, let reason) = machine.state else {
            Issue.record("Expected dismissing state")
            return
        }
        #expect(reason == .cancelled(.releasedWithoutSelection))
    }

    @Test @MainActor func duplicateReleaseAndExecutionAreSuppressed() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        #expect(machine.requestExecution(slotIndex: 3, sessionToken: token) == .applied)
        #expect(
            machine.requestExecution(slotIndex: 4, sessionToken: token)
                == .ignored(.executionAlreadyRequested)
        )
        #expect(
            machine.shortcutReleased(sessionToken: token)
                == .ignored(.duplicateRelease)
        )
        #expect(
            machine.shortcutReleased(sessionToken: token)
                == .ignored(.duplicateRelease)
        )
        guard case .executing(let request) = machine.state else {
            Issue.record("Expected executing state")
            return
        }
        #expect(request.slotIndex == 3)
    }

    @Test @MainActor func transitionMovesToChildPageAndClearsSelection() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let parentPageID = try #require(machine.state.session?.currentPageID)
        let childPageID = UUID()
        _ = machine.updateSelection(makeSelection(slotIndex: 1), sessionToken: token)

        #expect(machine.beginPageTransition(to: childPageID, sessionToken: token) == .applied)
        #expect(
            machine.state
                == .transitioning(
                    CommandWheelPageTransition(
                        session: session(machine),
                        fromPageID: parentPageID,
                        toPageID: childPageID
                    )
                )
        )
        #expect(machine.completePageTransition(sessionToken: token) == .applied)
        guard case .tracking(let childSession, let selection) = machine.state else {
            Issue.record("Expected tracking child page")
            return
        }
        #expect(childSession.currentPageID == childPageID)
        #expect(childSession.rootPageID == parentPageID)
        #expect(selection == nil)
    }

    @Test @MainActor func providerTasksAreOwnedAndCancelledOnPageTransition() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let task = Task<Void, Never> {}
        let taskID = CommandWheelProviderTaskID(rawValue: UUID())

        #expect(
            machine.registerProviderTask(task, id: taskID, sessionToken: token) == .applied
        )
        #expect(machine.providerTaskCount == 1)
        #expect(machine.beginPageTransition(to: UUID(), sessionToken: token) == .applied)
        #expect(task.isCancelled)
        #expect(machine.providerTaskCount == 0)
    }

    @Test @MainActor func cancellationCancelsProviderTasks() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let task = Task<Void, Never> {}
        _ = machine.registerProviderTask(
            task,
            id: CommandWheelProviderTaskID(rawValue: UUID()),
            sessionToken: token
        )

        #expect(machine.cancel(.applicationTerminating, sessionToken: token) == .applied)
        #expect(task.isCancelled)
        #expect(machine.providerTaskCount == 0)
        guard case .dismissing(_, let reason) = machine.state else {
            Issue.record("Expected dismissing state")
            return
        }
        #expect(reason == .cancelled(.applicationTerminating))
    }

    @Test @MainActor func executionCancelsOutstandingProviderTasks() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let task = Task<Void, Never> {}
        _ = machine.registerProviderTask(
            task,
            id: CommandWheelProviderTaskID(rawValue: UUID()),
            sessionToken: token
        )

        #expect(machine.requestExecution(slotIndex: 1, sessionToken: token) == .applied)
        #expect(task.isCancelled)
        #expect(machine.providerTaskCount == 0)
    }

    @Test @MainActor func staleProviderTaskIsCancelledImmediately() throws {
        let machine = makeMachine()
        let activeToken = try beginTracking(machine)
        let staleToken = CommandWheelSessionToken(
            identifier: UUID(),
            generation: activeToken.generation &+ 99
        )
        let task = Task<Void, Never> {}

        #expect(
            machine.registerProviderTask(
                task,
                id: CommandWheelProviderTaskID(rawValue: UUID()),
                sessionToken: staleToken
            ) == .ignored(.staleSession)
        )
        #expect(task.isCancelled)
        #expect(machine.providerTaskCount == 0)
    }

    @Test @MainActor func duplicateProviderTaskIDCancelsOnlyTheNewTask() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let taskID = CommandWheelProviderTaskID(rawValue: UUID())
        let first = Task<Void, Never> {}
        let duplicate = Task<Void, Never> {}

        #expect(machine.registerProviderTask(first, id: taskID, sessionToken: token) == .applied)
        #expect(
            machine.registerProviderTask(duplicate, id: taskID, sessionToken: token)
                == .ignored(.duplicateProviderTask)
        )
        #expect(duplicate.isCancelled)
        #expect(first.isCancelled == false)
        #expect(machine.providerTaskCount == 1)
    }

    @Test @MainActor func providerCompletionReleasesOwnership() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let taskID = CommandWheelProviderTaskID(rawValue: UUID())
        let task = Task<Void, Never> {}
        _ = machine.registerProviderTask(task, id: taskID, sessionToken: token)

        #expect(machine.providerTaskCompleted(id: taskID, sessionToken: token) == .applied)
        #expect(machine.providerTaskCount == 0)
        #expect(task.isCancelled == false)
    }

    @Test @MainActor func failureTransitionsThroughDismissalAndCancelsTasks() throws {
        let machine = makeMachine()
        let token = try beginTracking(machine)
        let task = Task<Void, Never> {}
        _ = machine.registerProviderTask(
            task,
            id: CommandWheelProviderTaskID(rawValue: UUID()),
            sessionToken: token
        )

        #expect(machine.fail(.providerFailed, sessionToken: token) == .applied)
        #expect(task.isCancelled)
        #expect(
            machine.state
                == .failed(
                    CommandWheelFailureState(
                        session: session(machine),
                        reason: .providerFailed
                    )
                )
        )
        #expect(machine.beginFailureDismissal(sessionToken: token) == .applied)
        #expect(machine.state == .dismissing(session(machine), reason: .failure))
        #expect(machine.dismissalCompleted(sessionToken: token) == .applied)
        #expect(machine.state == .idle)
    }

    @Test @MainActor func staleAsyncCompletionCannotMutateNewSession() throws {
        let machine = makeMachine()
        let firstToken = try beginTracking(machine)
        #expect(machine.cancel(.explicit, sessionToken: firstToken) == .applied)
        #expect(machine.dismissalCompleted(sessionToken: firstToken) == .applied)

        let secondToken = try beginTracking(machine)
        let secondState = machine.state
        #expect(
            machine.completePageTransition(sessionToken: firstToken)
                == .ignored(.staleSession)
        )
        #expect(
            machine.updateSelection(makeSelection(slotIndex: 4), sessionToken: firstToken)
                == .ignored(.staleSession)
        )
        #expect(machine.state == secondState)
        #expect(machine.state.session?.token == secondToken)
    }

    @Test @MainActor func sessionTokensRemainUniqueWhenUUIDSourceRepeats() throws {
        let repeatedUUID = UUID()
        let machine = CommandWheelSessionStateMachine(makeUUID: { repeatedUUID })
        let first = try beginTracking(machine)
        _ = machine.cancel(.explicit, sessionToken: first)
        _ = machine.dismissalCompleted(sessionToken: first)
        let second = try begin(machine, ids: SessionIDs())

        #expect(first.identifier == second.identifier)
        #expect(first.generation != second.generation)
        #expect(first != second)
    }

    @Test @MainActor func invalidTransitionsLeaveStateUnchanged() throws {
        let machine = makeMachine()
        let token = try begin(machine, ids: SessionIDs())
        let preparing = machine.state

        #expect(machine.trackingBegan(sessionToken: token) == .ignored(.invalidTransition))
        #expect(
            machine.requestExecution(slotIndex: 0, sessionToken: token)
                == .ignored(.invalidTransition)
        )
        #expect(machine.state == preparing)
    }

    @Test @MainActor func callsWithoutActiveSessionAreRejected() {
        let machine = makeMachine()
        let token = CommandWheelSessionToken(identifier: UUID(), generation: 1)

        #expect(
            machine.presentationBegan(sessionToken: token)
                == .ignored(.noActiveSession)
        )
        #expect(
            machine.shortcutReleased(sessionToken: token)
                == .ignored(.noActiveSession)
        )
        #expect(machine.state == .idle)
    }
}

private struct SessionIDs {
    let profileID = UUID()
    let pageID = UUID()
}

@MainActor
private func makeMachine() -> CommandWheelSessionStateMachine {
    CommandWheelSessionStateMachine(makeUUID: { UUID() })
}

@MainActor
private func begin(
    _ machine: CommandWheelSessionStateMachine,
    ids: SessionIDs
) throws -> CommandWheelSessionToken {
    guard case .started(let token) = machine.shortcutPressed(
        profileID: ids.profileID,
        rootPageID: ids.pageID
    ) else {
        throw StateMachineTestError.couldNotBegin
    }
    return token
}

@MainActor
private func beginTracking(
    _ machine: CommandWheelSessionStateMachine,
    ids: SessionIDs = SessionIDs()
) throws -> CommandWheelSessionToken {
    let token = try begin(machine, ids: ids)
    guard machine.presentationBegan(sessionToken: token) == .applied,
          machine.trackingBegan(sessionToken: token) == .applied else {
        throw StateMachineTestError.couldNotBeginTracking
    }
    return token
}

@MainActor
private func session(_ machine: CommandWheelSessionStateMachine) -> CommandWheelSession {
    guard let session = machine.state.session else {
        fatalError("Expected an active session")
    }
    return session
}

private func makeSelection(slotIndex: Int) -> CommandWheelSelection {
    CommandWheelSelection(
        slotIndex: slotIndex,
        hitTest: CommandWheelHitTest(
            pointerLocation: CGPoint(x: 0, y: 100),
            distance: 100,
            clockwiseAngleDegrees: Double(slotIndex) * 45,
            region: .selection,
            target: .selectableSlot(slotIndex)
        )
    )
}

private enum StateMachineTestError: Error {
    case couldNotBegin
    case couldNotBeginTracking
}
