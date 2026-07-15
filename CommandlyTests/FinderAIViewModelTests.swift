import AIKit
import CommandKit
import Foundation
import SearchKit
import Testing
@testable import Commandly

@MainActor
struct FinderAIViewModelTests {
    @Test func missingOrNonToolSelectionShowsUnavailableState() async throws {
        let noSelection = makeViewModel(
            runtime: InMemoryAIProviderRuntimeService(),
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )

        await noSelection.start()

        #expect(noSelection.phase == .unavailable)
        #expect(noSelection.canSend == false)
        #expect(noSelection.configurationMessage?.contains("Connect an AI provider") == true)
        #expect(noSelection.footerActions.first?.keyHint == nil)

        let incapableSelection = makeSelection(supportsTools: false)
        let incapable = makeViewModel(
            runtime: InMemoryAIProviderRuntimeService(
                activeSelection: incapableSelection
            ),
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )

        await incapable.start()

        #expect(incapable.phase == .unavailable)
        #expect(incapable.canSend == false)
        #expect(incapable.configurationMessage?.contains("tool-capable model") == true)
    }

    @Test func toolCapableSelectionWithoutAuthorizedFoldersStaysUnavailable() async {
        let viewModel = makeViewModel(
            runtime: InMemoryAIProviderRuntimeService(activeSelection: makeSelection()),
            workspace: StubFinderAIViewModelWorkspace(authorizedRoots: []),
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )

        await viewModel.start()

        #expect(viewModel.phase == .unavailable)
        #expect(viewModel.canSend == false)
        #expect(viewModel.needsFolderAuthorization)
        #expect(viewModel.configurationMessage?.contains("at least one specific folder") == true)
        #expect(viewModel.footerActions.first?.id == FinderAIActionID.openPermissionsSettings)
    }

    @Test func twoRoundToolLoopSendsDefinitionsThenToolResultsBeforeFinalText() async throws {
        let selection = makeSelection()
        let call = AIToolCall(
            id: "call-list",
            name: "finder_list_roots",
            arguments: .object([:])
        )
        let runtime = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "tool-round",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .toolCalls
                ),
                AICompletionResponse(
                    id: "final-round",
                    message: .assistant("Your authorized folder is ready."),
                    finishReason: .completed
                ),
            ]
        )
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        #expect(viewModel.providerDisclosureMessage.contains("Test Provider"))
        #expect(viewModel.providerDisclosureMessage.contains("File contents are sent only after"))
        viewModel.draft = "Show my authorized folders"
        #expect(viewModel.footerActions.first?.keyHint == .return)

        viewModel.send()

        let finished = await eventually {
            viewModel.phase == .ready
                && viewModel.entries.contains { entry in
                    entry.role == .assistant && entry.text == "Your authorized folder is ready."
                }
        }
        #expect(finished)
        let requests = await runtime.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].tools.map(\.name) == ["finder_list_roots", "finder_read_text"])
        #expect(requests[1].tools == requests[0].tools)
        let secondRoundResults = requests[1].messages.flatMap(\.toolResults)
        #expect(secondRoundResults.count == 1)
        #expect(secondRoundResults.first?.callID == call.id)
        #expect(secondRoundResults.first?.toolName == call.name)
        #expect(secondRoundResults.first?.isError == false)
        #expect(await executor.recordedCalls() == [call])
        #expect(viewModel.entries.contains { entry in
            entry.role == .activity
                && entry.text == "Finder tool finder_list_roots completed."
        })
    }

    @Test func textReadWaitsForApprovalBeforeProviderLoopResumes() async throws {
        let selection = makeSelection()
        let call = makeTextReadCall(id: "read-approved")
        let runtime = approvalRuntime(selection: selection, call: call, finalText: "Read complete.")
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .requireTextReadApproval)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Read the note"

        viewModel.send()

        let isWaiting = await eventually {
            viewModel.phase == .awaitingApproval && viewModel.pendingApproval != nil
        }
        #expect(isWaiting)
        #expect(viewModel.footerActions.first?.keyHint == nil)
        await yieldExecution()
        #expect(await runtime.recordedRequests().count == 1)
        #expect(await executor.approvedExecutionCount() == 0)

        viewModel.approvePendingRequest()

        let finished = await eventually {
            viewModel.phase == .ready
                && viewModel.entries.contains { $0.text == "Read complete." }
        }
        #expect(finished)
        #expect(await executor.approvedExecutionCount() == 1)
        let requests = await runtime.recordedRequests()
        #expect(requests.count == 2)
        let result = try #require(requests[1].messages.flatMap(\.toolResults).first)
        #expect(result.callID == call.id)
        #expect(result.isError == false)
        #expect(result.content["items"]?.arrayValue?.first?["text"]?.stringValue == "preview text")
    }

    @Test func denialReturnsErrorToolResultWithoutApprovedExecution() async throws {
        let selection = makeSelection()
        let call = makeTextReadCall(id: "read-denied")
        let runtime = approvalRuntime(selection: selection, call: call, finalText: "Request denied.")
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .requireTextReadApproval)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Read the note"
        viewModel.send()
        #expect(await eventually { viewModel.pendingApproval != nil })

        viewModel.denyPendingRequest()

        #expect(await eventually {
            viewModel.phase == .ready
                && viewModel.entries.contains { $0.text == "Request denied." }
        })
        #expect(await executor.approvedExecutionCount() == 0)
        let requests = await runtime.recordedRequests()
        #expect(requests.count == 2)
        let result = try #require(requests[1].messages.flatMap(\.toolResults).first)
        #expect(result.callID == call.id)
        #expect(result.isError)
        #expect(result.content["error"]?["code"]?.stringValue == "user_denied")
    }

    @Test func stoppingWhileApprovalIsPendingNeverExecutesIt() async throws {
        let selection = makeSelection()
        let call = makeTextReadCall(id: "read-stopped")
        let runtime = approvalRuntime(selection: selection, call: call, finalText: "Must not appear")
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .requireTextReadApproval)
        let workspace = StubFinderAIViewModelWorkspace()
        let viewModel = makeViewModel(
            runtime: runtime,
            workspace: workspace,
            executor: executor
        )
        await viewModel.start()
        viewModel.draft = "Read the note"
        viewModel.send()
        #expect(await eventually { viewModel.pendingApproval != nil })

        viewModel.stop()

        #expect(await eventually { viewModel.statusMessage == "Request stopped." })
        await yieldExecution()
        #expect(await executor.approvedExecutionCount() == 0)
        #expect(await runtime.recordedRequests().count == 1)
        #expect(viewModel.entries.contains { $0.text == "Must not appear" } == false)
    }

    @Test func cancelledRequestStaysNonReadyUntilItsTaskUnwinds() async throws {
        let selection = makeSelection()
        let runtime = ControllableFinderAIViewModelRuntime(
            selection: selection,
            responses: [
                AICompletionResponse(
                    id: "late-response",
                    message: .assistant("Must not be rendered"),
                    finishReason: .completed
                ),
            ]
        )
        await runtime.suspendNextCompletion()
        let viewModel = makeViewModel(
            runtime: runtime,
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )
        await viewModel.start()
        viewModel.draft = "Wait for the provider"
        viewModel.send()
        #expect(await eventually { await runtime.completionRequestCount() == 1 })

        viewModel.perform(FinderAIActionID.stopGeneration)

        #expect(viewModel.phase == .responding)
        #expect(viewModel.canSend == false)
        #expect(viewModel.statusMessage == "Stopping request…")
        await yieldExecution()
        #expect(viewModel.phase == .responding)

        await runtime.resumeCompletion()

        #expect(await eventually {
            viewModel.phase == .ready && viewModel.statusMessage == "Request stopped."
        })
        #expect(viewModel.entries.contains { $0.text == "Must not be rendered" } == false)
    }

    @Test func providerOrCredentialRevisionChangeInvalidatesApprovalWithoutExecution() async throws {
        let initialSelection = makeSelection()
        let switchedSelections = [
            makeSelection(connectionRevision: "rotated-credential-revision"),
            makeSelection(
                providerID: "different-provider",
                providerName: "Different Provider"
            ),
        ]

        for switchedSelection in switchedSelections {
            let call = makeTextReadCall(id: UUID().uuidString)
            let runtime = ControllableFinderAIViewModelRuntime(
                selection: initialSelection,
                responses: [
                    AICompletionResponse(
                        id: "approval-round",
                        message: .assistant(toolCalls: [call]),
                        finishReason: .toolCalls
                    ),
                ]
            )
            let executor = RecordingFinderAIViewModelToolExecutor(
                behavior: .requireTextReadApproval
            )
            let viewModel = makeViewModel(runtime: runtime, executor: executor)
            await viewModel.start()
            viewModel.draft = "Read the note"
            viewModel.send()
            #expect(await eventually { viewModel.pendingApproval != nil })
            #expect(viewModel.approvalProviderName == initialSelection.providerName)

            await runtime.setSelection(switchedSelection)
            viewModel.approvePendingRequest()

            #expect(await eventually {
                viewModel.phase == .ready && viewModel.conversationNeedsReset
            })
            #expect(await executor.approvedExecutionCount() == 0)
            #expect(await runtime.completionRequestCount() == 1)
            #expect(viewModel.canSend == false)
            #expect(viewModel.entries.contains { entry in
                entry.role == .error && entry.text.contains("connection changed")
            })
        }
    }

    @Test func approvalRevalidationRemainsCancellableAfterApprove() async throws {
        let selection = makeSelection()
        let call = makeTextReadCall(id: "approval-cancellation")
        let runtime = ControllableFinderAIViewModelRuntime(
            selection: selection,
            responses: [
                AICompletionResponse(
                    id: "approval-round",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .toolCalls
                ),
            ]
        )
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .requireTextReadApproval)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Read the note"
        viewModel.send()
        #expect(await eventually { viewModel.pendingApproval != nil })
        await runtime.suspendNextSelection()

        viewModel.approvePendingRequest()

        #expect(await eventually { await runtime.selectionSuspensionCount() == 1 })
        #expect(viewModel.phase == .responding)
        #expect(viewModel.pendingApproval == nil)
        #expect(viewModel.footerActions.first?.id == FinderAIActionID.stopGeneration)
        #expect(viewModel.handleEscape())
        #expect(viewModel.phase == .responding)
        await runtime.resumeSelection()

        #expect(await eventually {
            viewModel.phase == .ready && viewModel.statusMessage == "Request stopped."
        })
        #expect(await executor.approvedExecutionCount() == 0)
    }

    @Test func completedApprovedResultRemainsVisibleWhenCancellationArrivesDuringExecution() async throws {
        let selection = makeSelection()
        let call = makeTextReadCall(id: "approved-result-cancellation")
        let runtime = ControllableFinderAIViewModelRuntime(
            selection: selection,
            responses: [
                AICompletionResponse(
                    id: "approval-round",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .toolCalls
                ),
            ]
        )
        let executor = BlockingApprovedFinderAIViewModelToolExecutor()
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Apply the approved plan"
        viewModel.send()
        #expect(await eventually { viewModel.pendingApproval != nil })

        viewModel.approvePendingRequest()
        #expect(await eventually { await executor.approvedExecutionCount() == 1 })
        viewModel.perform(FinderAIActionID.stopGeneration)
        await executor.resumeApprovedExecution()

        #expect(await eventually {
            viewModel.phase == .ready && viewModel.statusMessage == "Request stopped."
        })
        #expect(viewModel.entries.contains { entry in
            entry.role == .activity && entry.text == "report.txt: completed."
        })
        #expect(viewModel.conversationNeedsReset == false)
        #expect(await runtime.completionRequestCount() == 1)
    }

    @Test func cancelledApprovedMutationRequiresClearWhenItsToolTurnIsIncomplete() async throws {
        let selection = makeSelection()
        let call = AIToolCall(
            id: "approved-mutation-cancellation",
            name: "finder_mutate",
            arguments: .object([:])
        )
        let runtime = ControllableFinderAIViewModelRuntime(
            selection: selection,
            responses: [
                AICompletionResponse(
                    id: "mutation-round",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .toolCalls
                ),
            ]
        )
        let executor = BlockingApprovedFinderAIViewModelToolExecutor(
            toolName: call.name,
            effect: .mutating
        )
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Apply the Finder change"
        viewModel.send()
        #expect(await eventually { viewModel.pendingApproval != nil })

        viewModel.approvePendingRequest()
        #expect(await eventually { await executor.approvedExecutionCount() == 1 })
        viewModel.perform(FinderAIActionID.stopGeneration)
        await executor.resumeApprovedExecution()

        #expect(await eventually {
            viewModel.phase == .ready && viewModel.conversationNeedsReset
        })
        #expect(viewModel.statusMessage?.contains("provider transcript is incomplete") == true)
        #expect(viewModel.composerHint.contains("provider transcript is incomplete"))
        #expect(viewModel.entries.contains { entry in
            entry.role == .activity && entry.text == "report.txt: completed."
        })
        viewModel.draft = "Do it again"
        #expect(viewModel.canSend == false)

        viewModel.clearConversation()
        #expect(await eventually { viewModel.phase == .ready })
        #expect(viewModel.conversationNeedsReset == false)
        #expect(viewModel.entries.isEmpty)
    }

    @Test func mutationActivityDerivesFailedCancelledAndPartialSummariesFromItems() async throws {
        let selection = makeSelection()
        let cases: [(
            name: String,
            statuses: [FinderAIViewModelMutationFixtureStatus],
            expectedSummary: String,
            expectedRows: [(role: FinderAIConversationRole, text: String)]
        )] = [
            (
                "failed",
                [.failed, .failed],
                "Finder tool finder_mutate failed; no operations completed.",
                [(.error, "item-1: failed."), (.error, "item-2: failed.")]
            ),
            (
                "cancelled",
                [.cancelled, .cancelled],
                "Finder tool finder_mutate was cancelled; no operations completed.",
                [(.error, "item-1: cancelled."), (.error, "item-2: cancelled.")]
            ),
            (
                "partial",
                [.completed, .failed, .cancelled],
                "Finder tool finder_mutate partially completed: 1 of 3 operations succeeded.",
                [
                    (.activity, "item-1: completed."),
                    (.error, "item-2: failed."),
                    (.error, "item-3: cancelled."),
                ]
            ),
        ]

        for testCase in cases {
            let call = AIToolCall(
                id: "mutation-report-\(testCase.name)",
                name: "finder_mutate",
                arguments: .object([:])
            )
            let runtime = approvalRuntime(
                selection: selection,
                call: call,
                finalText: "Mutation report received."
            )
            let executor = ReportingFinderAIViewModelToolExecutor(statuses: testCase.statuses)
            let viewModel = makeViewModel(runtime: runtime, executor: executor)
            await viewModel.start()
            viewModel.draft = "Apply the reviewed Finder plan"
            viewModel.send()
            #expect(await eventually { viewModel.pendingApproval != nil })

            viewModel.approvePendingRequest()

            #expect(await eventually {
                viewModel.phase == .ready
                    && viewModel.entries.contains { $0.text == "Mutation report received." }
            })
            #expect(viewModel.entries.contains { entry in
                entry.role == .error && entry.text == testCase.expectedSummary
            })
            #expect(viewModel.entries.contains { entry in
                entry.text == "Finder tool finder_mutate completed."
            } == false)
            for expectedRow in testCase.expectedRows {
                #expect(viewModel.entries.contains { entry in
                    entry.role == expectedRow.role && entry.text == expectedRow.text
                })
            }
        }
    }

    @Test func clearConversationEndsAndReplacesTheWorkspaceSession() async throws {
        let selection = makeSelection()
        let workspaceState = RecordingFinderAIWorkspaceState()
        let workspace = RecordingFinderAIViewModelWorkspace(state: workspaceState)
        let viewModel = makeViewModel(
            runtime: InMemoryAIProviderRuntimeService(activeSelection: selection),
            workspace: workspace,
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )
        await viewModel.start()
        let firstSnapshot = await workspaceState.snapshot()
        let firstSession = try #require(firstSnapshot.begun.first)

        viewModel.clearConversation()

        #expect(viewModel.phase == .loading)
        #expect(viewModel.canSend == false)
        #expect(await eventually { viewModel.phase == .ready })
        let snapshot = await workspaceState.snapshot()
        #expect(snapshot.begun.count == 2)
        let replacementSession = try #require(snapshot.begun.last)
        #expect(replacementSession != firstSession)
        #expect(snapshot.ended == [firstSession])
        #expect(Array(snapshot.events.prefix(3)) == [
            .began(firstSession),
            .ended(firstSession),
            .began(replacementSession),
        ])
    }

    @Test func stoppedStartCannotLeakSessionOrMutateRestartedState() async throws {
        let selection = makeSelection()
        let runtime = ControllableFinderAIViewModelRuntime(selection: selection)
        let workspaceState = RecordingFinderAIWorkspaceState()
        let viewModel = makeViewModel(
            runtime: runtime,
            workspace: RecordingFinderAIViewModelWorkspace(state: workspaceState),
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )
        await runtime.suspendNextSelection()
        let starting = Task { await viewModel.start() }
        #expect(await eventually {
            let suspensionCount = await runtime.selectionSuspensionCount()
            let snapshot = await workspaceState.snapshot()
            return suspensionCount == 1 && snapshot.begun.count == 1
        })

        viewModel.stop()
        await runtime.resumeSelection()
        await starting.value

        #expect(await eventually { await workspaceState.snapshot().ended.count == 1 })
        #expect(viewModel.phase == .loading)
        #expect(viewModel.canSend == false)

        await viewModel.start()

        #expect(viewModel.phase == .ready)
        let snapshot = await workspaceState.snapshot()
        #expect(snapshot.begun.count == 2)
        let firstSession = try #require(snapshot.begun.first)
        #expect(snapshot.ended == [firstSession])
    }

    @Test func midBatchCancellationRollsBackIncompleteAssistantToolTurn() async throws {
        let selection = makeSelection()
        let calls = [
            AIToolCall(id: "first-call", name: "finder_list_roots", arguments: .object([:])),
            AIToolCall(id: "second-call", name: "finder_list_roots", arguments: .object([:])),
        ]
        let runtime = ControllableFinderAIViewModelRuntime(
            selection: selection,
            responses: [
                AICompletionResponse(
                    id: "tool-batch",
                    message: .assistant(toolCalls: calls),
                    finishReason: .toolCalls
                ),
                AICompletionResponse(
                    id: "next-turn",
                    message: .assistant("A clean next turn."),
                    finishReason: .completed
                ),
            ]
        )
        let executor = BlockingSecondFinderAIViewModelToolExecutor()
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Run two reads"
        viewModel.send()
        #expect(await eventually { await executor.executionCount() == 2 })

        viewModel.perform(FinderAIActionID.stopGeneration)
        #expect(viewModel.phase == .responding)
        await executor.resumeSecondExecution()
        #expect(await eventually { viewModel.phase == .ready })

        viewModel.draft = "Continue safely"
        viewModel.send()
        #expect(await eventually {
            viewModel.entries.contains { $0.text == "A clean next turn." }
        })
        let requests = await runtime.recordedRequests()
        #expect(requests.count == 2)
        let secondRequest = try #require(requests.last)
        #expect(secondRequest.messages.flatMap(\.toolCalls).isEmpty)
        #expect(secondRequest.messages.flatMap(\.toolResults).isEmpty)
    }

    @Test func projectedDraftCannotCrossConversationByteLimit() async throws {
        let selection = makeSelection()
        let runtime = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "large-but-accepted",
                    message: .assistant(String(repeating: "a", count: 985_000)),
                    finishReason: .completed
                ),
            ]
        )
        let viewModel = makeViewModel(
            runtime: runtime,
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )
        await viewModel.start()
        viewModel.draft = "Seed"
        viewModel.send()
        #expect(await eventually { viewModel.phase == .ready })
        #expect(viewModel.conversationNeedsReset == false)

        viewModel.draft = String(repeating: "b", count: 64 * 1_024)

        #expect(viewModel.draftIsTooLarge == false)
        #expect(viewModel.draftWouldExceedConversationLimit)
        #expect(viewModel.canSend == false)
    }

    @Test func lengthLimitedResponseIsPresentedAsIncomplete() async throws {
        let selection = makeSelection()
        let runtime = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "truncated",
                    message: .assistant("This answer is partial"),
                    finishReason: .length
                ),
            ]
        )
        let viewModel = makeViewModel(
            runtime: runtime,
            executor: RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        )
        await viewModel.start()
        viewModel.draft = "Explain these files"

        viewModel.send()

        #expect(await eventually { viewModel.phase == .ready })
        #expect(viewModel.entries.contains { $0.text == "This answer is partial" })
        #expect(viewModel.statusMessage?.contains("may be incomplete") == true)
    }

    @Test func impossibleFinishReasonAndToolCallCombinationIsRejected() async throws {
        let selection = makeSelection()
        let call = AIToolCall(
            id: "bad-finish-reason",
            name: "finder_list_roots",
            arguments: .object([:])
        )
        let runtime = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "invalid",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .completed
                ),
            ]
        )
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Run an invalid provider response"

        viewModel.send()

        #expect(await eventually { viewModel.phase == .ready })
        #expect(viewModel.entries.contains { entry in
            entry.role == .error && entry.text.contains("safety limit")
        })
        #expect(await executor.recordedCalls().isEmpty)
    }

    @Test func oversizedAssistantResponseIsRejectedBeforeRenderingOrToolExecution() async throws {
        let selection = makeSelection()
        let runtime = InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "oversized",
                    message: .assistant(String(repeating: "x", count: 1_024 * 1_024)),
                    finishReason: .completed
                ),
            ]
        )
        let executor = RecordingFinderAIViewModelToolExecutor(behavior: .complete)
        let viewModel = makeViewModel(runtime: runtime, executor: executor)
        await viewModel.start()
        viewModel.draft = "Ignore provider limits"
        viewModel.send()

        #expect(await eventually { viewModel.phase == .ready })
        #expect(viewModel.entries.contains { entry in
            entry.role == .assistant
        } == false)
        #expect(viewModel.entries.contains { entry in
            entry.role == .error && entry.text.contains("conversation limit")
        })
        #expect(await executor.recordedCalls().isEmpty)
    }

    @Test func oversizedToolArgumentsAndJSONAssistantContentAreRejected() async throws {
        let selection = makeSelection()
        let oversizedCall = AIToolCall(
            id: "oversized-arguments",
            name: "finder_list_roots",
            arguments: .object([
                "payload": .string(String(repeating: "x", count: 70_000)),
            ])
        )
        let responses = [
            AICompletionResponse(
                id: "oversized-tool",
                message: .assistant(toolCalls: [oversizedCall]),
                finishReason: .toolCalls
            ),
            AICompletionResponse(
                id: "json-content",
                message: AIMessage(
                    role: .assistant,
                    content: [.json(.object(["unsafe": .boolean(true)]))]
                ),
                finishReason: .completed
            ),
        ]

        for response in responses {
            let executor = RecordingFinderAIViewModelToolExecutor(behavior: .complete)
            let viewModel = makeViewModel(
                runtime: InMemoryAIProviderRuntimeService(
                    activeSelection: selection,
                    responses: [response]
                ),
                executor: executor
            )
            await viewModel.start()
            viewModel.draft = "Use untrusted response"
            viewModel.send()

            #expect(await eventually { viewModel.phase == .ready })
            #expect(await executor.recordedCalls().isEmpty)
            #expect(viewModel.entries.contains { $0.role == .assistant } == false)
            #expect(viewModel.entries.contains { $0.role == .error })
        }
    }

    private func makeViewModel(
        runtime: any AIProviderRuntimeServicing,
        workspace: any FinderAIWorkspaceQuerying = StubFinderAIViewModelWorkspace(),
        executor: any FinderAIToolExecuting
    ) -> FinderAIViewModel {
        FinderAIViewModel(
            runtime: runtime,
            workspace: workspace,
            toolExecutor: executor,
            onGoBack: {},
            onOpenSettings: {}
        )
    }

    private func makeSelection(
        providerID: String = "test-provider",
        providerName: String = "Test Provider",
        modelID: String = "test-model",
        connectionRevision: String = "test-connection-revision",
        supportsTools: Bool = true
    ) -> AIActiveProviderSelection {
        AIActiveProviderSelection(
            providerID: providerID,
            providerName: providerName,
            modelID: modelID,
            modelName: "Test Model",
            supportsTools: supportsTools,
            connectionRevision: connectionRevision
        )
    }

    private func approvalRuntime(
        selection: AIActiveProviderSelection,
        call: AIToolCall,
        finalText: String
    ) -> InMemoryAIProviderRuntimeService {
        InMemoryAIProviderRuntimeService(
            activeSelection: selection,
            responses: [
                AICompletionResponse(
                    id: "approval-round",
                    message: .assistant(toolCalls: [call]),
                    finishReason: .toolCalls
                ),
                AICompletionResponse(
                    id: "final-round",
                    message: .assistant(finalText),
                    finishReason: .completed
                ),
            ]
        )
    }

    private func makeTextReadCall(id: String) -> AIToolCall {
        AIToolCall(
            id: id,
            name: "finder_read_text",
            arguments: .object(["item_ids": .array([])])
        )
    }

    private func eventually(
        attempts: Int = 2_000,
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            await Task<Never, Never>.yield()
        }
        return await condition()
    }

    private func yieldExecution(iterations: Int = 100) async {
        for _ in 0 ..< iterations {
            await Task<Never, Never>.yield()
        }
    }
}

nonisolated private struct StubFinderAIViewModelWorkspace: FinderAIWorkspaceQuerying {
    private let sessionID: FinderAISessionID
    private let roots: [FinderAIRootSummary]

    init(
        sessionID: FinderAISessionID = FinderAISessionID(),
        authorizedRoots: [FinderAIRootSummary] = [
            FinderAIRootSummary(
                id: FinderAIRootID(),
                displayName: "Test Folder",
                isWritable: true
            ),
        ]
    ) {
        self.sessionID = sessionID
        roots = authorizedRoots
    }

    func beginSession() async -> FinderAISessionID {
        sessionID
    }

    func endSession(_: FinderAISessionID) async {}

    func authorizedRoots(in _: FinderAISessionID) async throws -> [FinderAIRootSummary] {
        roots
    }

    func search(
        _: FinderAISearchRequest,
        in _: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        throw FinderAIWorkspaceError.operationFailed
    }

    func listDirectory(
        _: FinderAIDirectoryReference,
        limit _: Int,
        in _: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        throw FinderAIWorkspaceError.operationFailed
    }

    func metadata(
        for _: [FinderAIItemID],
        in _: FinderAISessionID
    ) async throws -> [FinderAIItemSummary] {
        throw FinderAIWorkspaceError.operationFailed
    }

    func prepareTextRead(
        itemIDs _: [FinderAIItemID],
        maximumByteCount _: Int,
        in _: FinderAISessionID
    ) async throws -> FinderAITextReadPlan {
        throw FinderAIWorkspaceError.operationFailed
    }

    func reveal(
        itemIDs _: [FinderAIItemID],
        in _: FinderAISessionID
    ) async throws {
        throw FinderAIWorkspaceError.operationFailed
    }

    func planMutation(
        _: FinderAIMutationRequest,
        in _: FinderAISessionID
    ) async throws -> FinderAIMutationPlan {
        throw FinderAIWorkspaceError.operationFailed
    }
}

private actor ControllableFinderAIViewModelRuntime: AIProviderRuntimeServicing {
    private var selection: AIActiveProviderSelection?
    private var responses: [AICompletionResponse]
    private var requests: [AICompletionRequest] = []
    private var shouldSuspendCompletion = false
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendSelection = false
    private var selectionContinuation: CheckedContinuation<Void, Never>?
    private var selectionSuspensions = 0

    init(
        selection: AIActiveProviderSelection?,
        responses: [AICompletionResponse] = []
    ) {
        self.selection = selection
        self.responses = responses
    }

    func activeSelection() async throws -> AIActiveProviderSelection? {
        if shouldSuspendSelection {
            shouldSuspendSelection = false
            selectionSuspensions += 1
            await withCheckedContinuation { continuation in
                selectionContinuation = continuation
            }
        }
        return selection
    }

    func complete(
        _ request: AICompletionRequest,
        providerID: String,
        connectionRevision: String
    ) async throws -> AICompletionResponse {
        requests.append(request)
        guard let selection else {
            throw AIProviderRuntimeError.noActiveConnection
        }
        guard selection.providerID == providerID else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        guard selection.connectionRevision == connectionRevision else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        guard selection.modelID == request.modelID else {
            throw AIProviderRuntimeError.modelMismatch
        }
        guard responses.isEmpty == false else {
            throw AIProviderRuntimeTestError.responseQueueExhausted
        }
        let response = responses.removeFirst()
        if shouldSuspendCompletion {
            shouldSuspendCompletion = false
            await withCheckedContinuation { continuation in
                completionContinuation = continuation
            }
        }
        return response
    }

    func setSelection(_ selection: AIActiveProviderSelection?) {
        self.selection = selection
    }

    func suspendNextCompletion() {
        shouldSuspendCompletion = true
    }

    func resumeCompletion() {
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume()
    }

    func suspendNextSelection() {
        shouldSuspendSelection = true
    }

    func resumeSelection() {
        let continuation = selectionContinuation
        selectionContinuation = nil
        continuation?.resume()
    }

    func completionRequestCount() -> Int {
        requests.count
    }

    func selectionSuspensionCount() -> Int {
        selectionSuspensions
    }

    func recordedRequests() -> [AICompletionRequest] {
        requests
    }
}

nonisolated private enum RecordingFinderAIWorkspaceEvent: Equatable, Sendable {
    case began(FinderAISessionID)
    case ended(FinderAISessionID)
}

nonisolated private struct RecordingFinderAIWorkspaceSnapshot: Equatable, Sendable {
    let begun: [FinderAISessionID]
    let ended: [FinderAISessionID]
    let events: [RecordingFinderAIWorkspaceEvent]
}

private actor RecordingFinderAIWorkspaceState {
    private var begun: [FinderAISessionID] = []
    private var ended: [FinderAISessionID] = []
    private var events: [RecordingFinderAIWorkspaceEvent] = []

    func beginSession() -> FinderAISessionID {
        let sessionID = FinderAISessionID()
        begun.append(sessionID)
        events.append(.began(sessionID))
        return sessionID
    }

    func endSession(_ sessionID: FinderAISessionID) {
        ended.append(sessionID)
        events.append(.ended(sessionID))
    }

    func snapshot() -> RecordingFinderAIWorkspaceSnapshot {
        RecordingFinderAIWorkspaceSnapshot(begun: begun, ended: ended, events: events)
    }
}

nonisolated private struct RecordingFinderAIViewModelWorkspace: FinderAIWorkspaceQuerying {
    let state: RecordingFinderAIWorkspaceState

    func beginSession() async -> FinderAISessionID {
        await state.beginSession()
    }

    func endSession(_ sessionID: FinderAISessionID) async {
        await state.endSession(sessionID)
    }

    func authorizedRoots(in _: FinderAISessionID) async throws -> [FinderAIRootSummary] {
        [
            FinderAIRootSummary(
                id: FinderAIRootID(),
                displayName: "Recording Folder",
                isWritable: true
            ),
        ]
    }

    func search(
        _: FinderAISearchRequest,
        in _: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        throw FinderAIWorkspaceError.operationFailed
    }

    func listDirectory(
        _: FinderAIDirectoryReference,
        limit _: Int,
        in _: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        throw FinderAIWorkspaceError.operationFailed
    }

    func metadata(
        for _: [FinderAIItemID],
        in _: FinderAISessionID
    ) async throws -> [FinderAIItemSummary] {
        throw FinderAIWorkspaceError.operationFailed
    }

    func prepareTextRead(
        itemIDs _: [FinderAIItemID],
        maximumByteCount _: Int,
        in _: FinderAISessionID
    ) async throws -> FinderAITextReadPlan {
        throw FinderAIWorkspaceError.operationFailed
    }

    func reveal(
        itemIDs _: [FinderAIItemID],
        in _: FinderAISessionID
    ) async throws {
        throw FinderAIWorkspaceError.operationFailed
    }

    func planMutation(
        _: FinderAIMutationRequest,
        in _: FinderAISessionID
    ) async throws -> FinderAIMutationPlan {
        throw FinderAIWorkspaceError.operationFailed
    }
}

private actor BlockingSecondFinderAIViewModelToolExecutor: FinderAIToolExecuting {
    nonisolated let definitions: [AIToolDefinition] = [
        AIToolDefinition(
            name: "finder_list_roots",
            description: "List authorized roots.",
            inputSchema: .closedObject(properties: [:]),
            effect: .readOnly,
            confirmation: .never
        ),
    ]

    private var count = 0
    private var secondExecutionContinuation: CheckedContinuation<Void, Never>?

    func execute(
        _ call: AIToolCall,
        in _: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome {
        count += 1
        if count == 2 {
            await withCheckedContinuation { continuation in
                secondExecutionContinuation = continuation
            }
        }
        return .completed(AIToolResult(
            callID: call.id,
            toolName: call.name,
            content: .object(["roots": .array([])])
        ))
    }

    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in _: FinderAISessionID
    ) async -> AIToolResult {
        denied(request)
    }

    nonisolated func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult {
        AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object(["error": .string("denied")]),
            isError: true
        )
    }

    func executionCount() -> Int {
        count
    }

    func resumeSecondExecution() {
        let continuation = secondExecutionContinuation
        secondExecutionContinuation = nil
        continuation?.resume()
    }
}

private actor BlockingApprovedFinderAIViewModelToolExecutor: FinderAIToolExecuting {
    nonisolated let definitions: [AIToolDefinition]

    private var approvedCount = 0
    private var approvedContinuation: CheckedContinuation<Void, Never>?

    init(
        toolName: String = "finder_read_text",
        effect: AIToolEffect = .readOnly
    ) {
        definitions = [
            AIToolDefinition(
                name: toolName,
                description: "Execute an approved Finder operation.",
                inputSchema: .closedObject(properties: [:]),
                effect: effect,
                confirmation: .always
            ),
        ]
    }

    func execute(
        _ call: AIToolCall,
        in session: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome {
        .requiresApproval(.textRead(
            call: call,
            plan: FinderAITextReadPlan(
                id: FinderAIPlanID(),
                sessionID: session,
                expiresAt: .distantFuture,
                items: [Self.item],
                maximumByteCount: 1_024
            )
        ))
    }

    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in _: FinderAISessionID
    ) async -> AIToolResult {
        approvedCount += 1
        await withCheckedContinuation { continuation in
            approvedContinuation = continuation
        }
        return AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object([
                "completed_count": .number(1),
                "results": .array([
                    .object([
                        "name": .string("report.txt"),
                        "status": .string("completed"),
                    ]),
                ]),
            ])
        )
    }

    nonisolated func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult {
        AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object(["error": .string("denied")]),
            isError: true
        )
    }

    func approvedExecutionCount() -> Int {
        approvedCount
    }

    func resumeApprovedExecution() {
        let continuation = approvedContinuation
        approvedContinuation = nil
        continuation?.resume()
    }

    private static let item = FinderAIItemSummary(
        id: FinderAIItemID(),
        rootID: FinderAIRootID(),
        displayName: "report.txt",
        relativeLocation: "report.txt",
        kind: .file,
        contentTypeIdentifier: "public.plain-text",
        byteCount: 12,
        createdAt: nil,
        modifiedAt: nil,
        tags: [],
        matchKind: nil
    )
}

nonisolated private enum FinderAIViewModelMutationFixtureStatus: Sendable {
    case completed
    case failed
    case cancelled

    var rawValue: String {
        switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }
}

private actor ReportingFinderAIViewModelToolExecutor: FinderAIToolExecuting {
    nonisolated let definitions: [AIToolDefinition] = [
        AIToolDefinition(
            name: "finder_mutate",
            description: "Execute an approved Finder mutation.",
            inputSchema: .closedObject(properties: [:]),
            effect: .mutating,
            confirmation: .always
        ),
    ]

    private let statuses: [FinderAIViewModelMutationFixtureStatus]

    init(statuses: [FinderAIViewModelMutationFixtureStatus]) {
        self.statuses = statuses
    }

    func execute(
        _ call: AIToolCall,
        in session: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome {
        .requiresApproval(.mutation(
            call: call,
            plan: FinderAIMutationPlan(
                id: FinderAIPlanID(),
                sessionID: session,
                expiresAt: .distantFuture,
                risk: .changesLocation,
                operations: [],
                warnings: [.batchIsNotAtomic],
                affectedItemCount: statuses.count
            )
        ))
    }

    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in _: FinderAISessionID
    ) async -> AIToolResult {
        AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object([
                // Deliberately inconsistent aggregate fields prove the UI derives its status from
                // the local itemized outcomes instead of trusting a top-level success claim.
                "status": .string("completed"),
                "completed_count": .number(Double(statuses.count)),
                "results": .array(statuses.enumerated().map { index, status in
                    .object([
                        "name": .string("item-\(index + 1)"),
                        "status": .string(status.rawValue),
                    ])
                }),
            ]),
            isError: false
        )
    }

    nonisolated func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult {
        AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object(["error": .string("denied")]),
            isError: true
        )
    }
}

private actor RecordingFinderAIViewModelToolExecutor: FinderAIToolExecuting {
    enum Behavior: Sendable {
        case complete
        case requireTextReadApproval
    }

    nonisolated let definitions: [AIToolDefinition]
    private let behavior: Behavior
    private var calls: [AIToolCall] = []
    private var approvedCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
        self.definitions = [
            AIToolDefinition(
                name: "finder_list_roots",
                description: "List authorized roots.",
                inputSchema: .closedObject(properties: [:]),
                effect: .readOnly,
                confirmation: .never
            ),
            AIToolDefinition(
                name: "finder_read_text",
                description: "Read approved text.",
                inputSchema: .closedObject(properties: [:]),
                effect: .readOnly,
                confirmation: .always
            ),
        ]
    }

    func execute(
        _ call: AIToolCall,
        in session: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome {
        calls.append(call)
        switch behavior {
        case .complete:
            return .completed(AIToolResult(
                callID: call.id,
                toolName: call.name,
                content: .object(["roots": .array([])])
            ))
        case .requireTextReadApproval:
            return .requiresApproval(.textRead(
                call: call,
                plan: FinderAITextReadPlan(
                    id: FinderAIPlanID(),
                    sessionID: session,
                    expiresAt: .distantFuture,
                    items: [Self.item],
                    maximumByteCount: 1_024
                )
            ))
        }
    }

    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in _: FinderAISessionID
    ) async -> AIToolResult {
        approvedCount += 1
        return AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object([
                "items": .array([
                    .object(["name": .string("note.txt"), "text": .string("preview text")])
                ])
            ])
        )
    }

    nonisolated func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult {
        AIToolResult(
            callID: request.call.id,
            toolName: request.call.name,
            content: .object([
                "error": .object([
                    "code": .string("user_denied"),
                    "message": .string("The user declined this operation.")
                ])
            ]),
            isError: true
        )
    }

    func recordedCalls() async -> [AIToolCall] {
        calls
    }

    func approvedExecutionCount() async -> Int {
        approvedCount
    }

    private static let item = FinderAIItemSummary(
        id: FinderAIItemID(),
        rootID: FinderAIRootID(),
        displayName: "note.txt",
        relativeLocation: "note.txt",
        kind: .file,
        contentTypeIdentifier: "public.plain-text",
        byteCount: 12,
        createdAt: nil,
        modifiedAt: nil,
        tags: [],
        matchKind: nil
    )
}
