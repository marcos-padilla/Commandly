import AIKit
import Foundation
import Infrastructure
import SearchKit
import Testing
@testable import Commandly

struct FinderAIToolExecutorTests {
    @Test func definitionsArePortableClosedAndClassifiedByLocalEffect() throws {
        let executor = FinderAIToolExecutor(
            workspace: FailingFinderAIToolWorkspace(error: FinderAIToolTestError.unreachable),
            approvalCoordinator: FailingFinderAIApprovalCoordinator()
        )
        let definitions = executor.definitions

        #expect(Set(definitions.map(\.name)) == [
            "finder_list_roots",
            "finder_search",
            "finder_list_directory",
            "finder_get_metadata",
            "finder_reveal",
            "finder_read_text",
            "finder_create_folder",
            "finder_rename",
            "finder_duplicate",
            "finder_copy",
            "finder_move",
            "finder_trash"
        ])
        #expect(definitions.count == 12)

        for definition in definitions {
            try definition.validate()
            guard case .object(let properties, _, let additionalProperties, _) =
                definition.inputSchema else {
                Issue.record("Every tool input must be an object")
                continue
            }
            #expect(additionalProperties == false)
            #expect(properties.keys.allSatisfy { key in
                let normalized = key.lowercased()
                return !normalized.contains("path")
                    && !normalized.contains("url")
                    && !normalized.contains("command")
                    && !normalized.contains("script")
            })
        }

        let byName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        #expect(byName["finder_read_text"]?.effect == .readOnly)
        #expect(byName["finder_read_text"]?.confirmation == .always)
        #expect(byName["finder_create_folder"]?.effect == .mutating)
        #expect(byName["finder_create_folder"]?.confirmation == .always)
        #expect(byName["finder_trash"]?.effect == .destructive)
        #expect(byName["finder_trash"]?.confirmation == .always)
        #expect(byName["finder_search"]?.confirmation == .never)
    }

    @Test func malformedCallsAndLocalErrorsAreSanitizedWithoutEchoingPaths() async throws {
        let secretPath = "/Users/example/Secret Folder/passwords.txt"
        let realFixture = try FinderAIToolTestFixture()
        defer { realFixture.remove() }
        let service = await realFixture.makeService()
        let executor = FinderAIToolExecutor(
            workspace: service,
            approvalCoordinator: service
        )
        let session = await service.beginSession()
        let rawPathCall = AIToolCall(
            id: "raw-path",
            name: "finder_list_roots",
            arguments: .object(["path": .string(secretPath)])
        )

        let malformed = await executor.execute(rawPathCall, in: session)
        let malformedResult = try completedResult(malformed)
        #expect(malformedResult.isError)
        #expect(errorCode(in: malformedResult) == "invalid_arguments")
        #expect(try encodedString(malformedResult.content).contains(secretPath) == false)

        let leakingExecutor = FinderAIToolExecutor(
            workspace: FailingFinderAIToolWorkspace(
                error: FinderAIToolTestError.leakingPath(secretPath)
            ),
            approvalCoordinator: FailingFinderAIApprovalCoordinator()
        )
        let failed = await leakingExecutor.execute(
            AIToolCall(id: "failure", name: "finder_list_roots", arguments: .object([:])),
            in: FinderAISessionID()
        )
        let failedResult = try completedResult(failed)
        #expect(failedResult.isError)
        #expect(errorCode(in: failedResult) == "operation_failed")
        #expect(try encodedString(failedResult.content).contains(secretPath) == false)

        let unknown = await executor.execute(
            AIToolCall(id: "unknown", name: "finder_run_shell", arguments: .object([:])),
            in: session
        )
        #expect(errorCode(in: try completedResult(unknown)) == "unknown_tool")
    }

    @Test func searchRejectsOversizedUTF8QueriesAndRootListsBeforeWorkspaceAccess() async throws {
        let executor = FinderAIToolExecutor(
            workspace: FailingFinderAIToolWorkspace(error: FinderAIToolTestError.unreachable),
            approvalCoordinator: FailingFinderAIApprovalCoordinator()
        )
        let session = FinderAISessionID()
        let oversizedQuery = String(repeating: "é", count: 513)
        #expect(oversizedQuery.utf8.count > FinderAIToolExecutor.maximumSearchQueryByteCount)
        let queryResult = try completedResult(await executor.execute(
            AIToolCall(
                id: "query-too-large",
                name: "finder_search",
                arguments: .object(["query": .string(oversizedQuery)])
            ),
            in: session
        ))
        #expect(errorCode(in: queryResult) == "invalid_arguments")

        let tooManyRoots = (0...FinderAIToolExecutor.maximumSearchRootCount).map { _ in
            AIJSONValue.string(UUID().uuidString)
        }
        let rootsResult = try completedResult(await executor.execute(
            AIToolCall(
                id: "roots-too-large",
                name: "finder_search",
                arguments: .object([
                    "query": .string("note"),
                    "root_ids": .array(tooManyRoots)
                ])
            ),
            in: session
        ))
        #expect(errorCode(in: rootsResult) == "invalid_arguments")

        let boundaryQueryResult = try completedResult(await executor.execute(
            AIToolCall(
                id: "query-at-boundary",
                name: "finder_search",
                arguments: .object([
                    "query": .string(String(
                        repeating: "a",
                        count: FinderAIToolExecutor.maximumSearchQueryByteCount
                    ))
                ])
            ),
            in: session
        ))
        #expect(errorCode(in: boundaryQueryResult) == "operation_failed")
    }

    @Test func readToolsReturnOnlyOpaqueHandlesAndRootRelativeLocations() async throws {
        let fixture = try FinderAIToolTestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let session = await service.beginSession()

        let rootsResult = try completedResult(await executor.execute(
            AIToolCall(id: "roots", name: "finder_list_roots", arguments: .object([:])),
            in: session
        ))
        let roots = try #require(rootsResult.content["roots"]?.arrayValue)
        let rootObject = try #require(roots.first?.objectValue)
        let rootID = try #require(rootObject["id"]?.stringValue)
        #expect(UUID(uuidString: rootID) != nil)
        #expect(rootObject["display_name"]?.stringValue == fixture.root.lastPathComponent)
        #expect(rootObject["path"] == nil)

        let listingResult = try completedResult(await executor.execute(
            AIToolCall(
                id: "listing",
                name: "finder_list_directory",
                arguments: .object([
                    "directory_type": .string("root"),
                    "directory_id": .string(rootID),
                    "limit": .number(20)
                ])
            ),
            in: session
        ))
        let items = try #require(listingResult.content["items"]?.arrayValue)
        let note = try #require(items.first { $0["name"]?.stringValue == "note.txt" })
        #expect(UUID(uuidString: note["id"]?.stringValue ?? "") != nil)
        #expect(note["relative_location"]?.stringValue == "note.txt")
        #expect(note["path"] == nil)

        let serialized = try encodedString(.array([rootsResult.content, listingResult.content]))
        #expect(serialized.contains(fixture.root.path) == false)
        #expect(serialized.contains(fixture.note.path) == false)
    }

    @Test func textContentRequiresExactLocalApprovalAndIsSingleUse() async throws {
        let fixture = try FinderAIToolTestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        let call = AIToolCall(
            id: "read",
            name: "finder_read_text",
            arguments: .object([
                "item_ids": .array([.string(note.id.rawValue.uuidString)]),
                "maximum_bytes": .number(4)
            ])
        )

        let outcome = await executor.execute(call, in: session)
        let request = try approvalRequest(outcome)
        guard case .textRead(let pendingCall, let plan) = request else {
            Issue.record("Expected a text-read approval request")
            return
        }
        #expect(pendingCall == call)
        #expect(plan.maximumByteCount == 4)
        #expect(plan.items.map(\.displayName) == ["note.txt"])
        let preview = try #require(plan.items.first)
        #expect(preview.location.rootID == root.id)
        #expect(preview.location.rootRelativePath == "note.txt")
        #expect(
            preview.location.authorizedRootDisplayPath
                == (fixture.root.path as NSString).abbreviatingWithTildeInPath
        )
        #expect(
            preview.location.userVisibleDescription.contains(
                preview.location.authorizedRootDisplayPath
            )
        )
        #expect(request.affectedItemCount == 1)
        #expect(request.confirmationTitle == "Share File Contents")

        let denied = executor.denied(request)
        #expect(denied.isError)
        #expect(errorCode(in: denied) == "user_denied")

        let anotherSession = await service.beginSession()
        let crossSession = await executor.executeApproved(request, in: anotherSession)
        #expect(errorCode(in: crossSession) == "session_mismatch")

        let approved = await executor.executeApproved(request, in: session)
        #expect(approved.isError == false)
        #expect(errorCode(in: approved) == nil)
        #expect(approved.content["items"]?.arrayValue?.first?["text"]?.stringValue == "hell")
        #expect(approved.content["items"]?.arrayValue?.first?["truncated"]?.booleanValue == true)
        #expect(try encodedString(approved.content).contains(fixture.root.path) == false)

        let replay = await executor.executeApproved(request, in: session)
        #expect(replay.isError)
        #expect(errorCode(in: replay) == "approval_invalid")
    }

    @Test func mutationsStayPendingUntilApprovedAndApprovedPlansCannotReplay() async throws {
        let fixture = try FinderAIToolTestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let destination = fixture.root.appendingPathComponent("AI Notes", isDirectory: true)
        let call = AIToolCall(
            id: "create",
            name: "finder_create_folder",
            arguments: .object([
                "parent_type": .string("root"),
                "parent_id": .string(root.id.rawValue.uuidString),
                "name": .string("AI Notes")
            ])
        )

        let request = try approvalRequest(await executor.execute(call, in: session))
        guard case .mutation(let pendingCall, let plan) = request else {
            Issue.record("Expected a mutation approval request")
            return
        }
        #expect(pendingCall == call)
        #expect(plan.risk == .createsItems)
        #expect(plan.operations.first?.kind == .createFolder)
        let operation = try #require(plan.operations.first)
        let destinationPreview = try #require(operation.destinations.first)
        guard case .authorizedLocation(let previewDestination) = destinationPreview else {
            Issue.record("Expected an exact authorized destination")
            return
        }
        #expect(previewDestination.rootID == root.id)
        #expect(previewDestination.rootRelativePath == "AI Notes")
        #expect(
            previewDestination.authorizedRootDisplayPath
                == (fixture.root.path as NSString).abbreviatingWithTildeInPath
        )
        #expect(
            previewDestination.userVisibleDescription.contains(
                previewDestination.authorizedRootDisplayPath
            )
        )
        #expect(request.confirmationTitle == "Create Files?")
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)

        let approved = await executor.executeApproved(request, in: session)
        #expect(approved.isError == false)
        #expect(approved.content["status"]?.stringValue == "completed")
        #expect(
            approved.content["summary"]?.stringValue
                == "All requested Finder operations completed."
        )
        #expect(approved.content["completed_count"]?.numberValue == 1)
        #expect(try encodedString(approved.content).contains(fixture.root.path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        let replay = await executor.executeApproved(request, in: session)
        #expect(replay.isError)
        #expect(errorCode(in: replay) == "approval_invalid")
    }

    @Test func mutationReportsExposeHonestAggregateOutcomesFromItemStatuses() async throws {
        let fixture = try FinderAIToolTestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let cases: [(
            name: String,
            statuses: [FinderAIExecutionItemStatus],
            expectedStatus: String,
            expectedSummary: String,
            completedCount: Int,
            failedCount: Int,
            cancelledCount: Int
        )] = [
            (
                "failed",
                [.failed(.operationFailed), .failed(.collision)],
                "failed",
                "The requested Finder operations did not complete.",
                0,
                2,
                0
            ),
            (
                "cancelled",
                [.cancelled, .cancelled],
                "cancelled",
                "The requested Finder operations were cancelled.",
                0,
                0,
                2
            ),
            (
                "partial",
                [.completed, .failed(.operationFailed), .cancelled],
                "partial",
                "Some requested Finder operations completed; others failed or were cancelled.",
                1,
                1,
                1
            ),
        ]

        for testCase in cases {
            let executor = FinderAIToolExecutor(
                workspace: service,
                approvalCoordinator: ReportingFinderAIApprovalCoordinator(
                    base: service,
                    statuses: testCase.statuses
                )
            )
            let call = AIToolCall(
                id: "report-\(testCase.name)",
                name: "finder_create_folder",
                arguments: .object([
                    "parent_type": .string("root"),
                    "parent_id": .string(root.id.rawValue.uuidString),
                    "name": .string("Outcome \(testCase.name)"),
                ])
            )
            let request = try approvalRequest(await executor.execute(call, in: session))
            let result = await executor.executeApproved(request, in: session)

            #expect(result.isError)
            #expect(result.content["status"]?.stringValue == testCase.expectedStatus)
            #expect(result.content["total_count"]?.numberValue == Double(testCase.statuses.count))
            #expect(result.content["completed_count"]?.numberValue == Double(testCase.completedCount))
            #expect(result.content["failed_count"]?.numberValue == Double(testCase.failedCount))
            #expect(result.content["cancelled_count"]?.numberValue == Double(testCase.cancelledCount))
            #expect(result.content["summary"]?.stringValue == testCase.expectedSummary)
            #expect(try encodedString(result.content).contains(fixture.root.path) == false)
        }
    }

    @Test func unsafeNamesAndInvalidHandlesFailBeforeApproval() async throws {
        let fixture = try FinderAIToolTestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)

        let traversal = await executor.execute(
            AIToolCall(
                id: "traversal",
                name: "finder_create_folder",
                arguments: .object([
                    "parent_type": .string("root"),
                    "parent_id": .string(root.id.rawValue.uuidString),
                    "name": .string("../Outside")
                ])
            ),
            in: session
        )
        #expect(errorCode(in: try completedResult(traversal)) == "invalid_arguments")

        let badHandle = await executor.execute(
            AIToolCall(
                id: "bad-handle",
                name: "finder_trash",
                arguments: .object(["item_ids": .array([.string("not-a-uuid")])])
            ),
            in: session
        )
        #expect(errorCode(in: try completedResult(badHandle)) == "invalid_arguments")
    }
}

private func completedResult(
    _ outcome: FinderAIToolExecutionOutcome
) throws -> AIToolResult {
    guard case .completed(let result) = outcome else {
        throw FinderAIToolTestError.unexpectedOutcome
    }
    return result
}

private func approvalRequest(
    _ outcome: FinderAIToolExecutionOutcome
) throws -> FinderAIToolApprovalRequest {
    guard case .requiresApproval(let request) = outcome else {
        throw FinderAIToolTestError.unexpectedOutcome
    }
    return request
}

private func errorCode(in result: AIToolResult) -> String? {
    result.content["error"]?["code"]?.stringValue
}

private func encodedString(_ value: AIJSONValue) throws -> String {
    String(decoding: try value.encodedData(), as: UTF8.self)
}

nonisolated private enum FinderAIToolTestError: Error {
    case unreachable
    case leakingPath(String)
    case unexpectedOutcome
}

private actor FailingFinderAIToolWorkspace: FinderAIWorkspaceQuerying {
    let error: FinderAIToolTestError

    init(error: FinderAIToolTestError) {
        self.error = error
    }

    func beginSession() -> FinderAISessionID { FinderAISessionID() }
    func endSession(_ sessionID: FinderAISessionID) { _ = sessionID }

    func authorizedRoots(in sessionID: FinderAISessionID) throws -> [FinderAIRootSummary] {
        _ = sessionID
        throw error
    }

    func search(
        _ request: FinderAISearchRequest,
        in sessionID: FinderAISessionID
    ) throws -> FinderAIItemPage {
        _ = request
        _ = sessionID
        throw error
    }

    func listDirectory(
        _ directory: FinderAIDirectoryReference,
        limit: Int,
        in sessionID: FinderAISessionID
    ) throws -> FinderAIItemPage {
        _ = directory
        _ = limit
        _ = sessionID
        throw error
    }

    func metadata(
        for itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) throws -> [FinderAIItemSummary] {
        _ = itemIDs
        _ = sessionID
        throw error
    }

    func prepareTextRead(
        itemIDs: [FinderAIItemID],
        maximumByteCount: Int,
        in sessionID: FinderAISessionID
    ) throws -> FinderAITextReadPlan {
        _ = itemIDs
        _ = maximumByteCount
        _ = sessionID
        throw error
    }

    func reveal(
        itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) throws {
        _ = itemIDs
        _ = sessionID
        throw error
    }

    func planMutation(
        _ request: FinderAIMutationRequest,
        in sessionID: FinderAISessionID
    ) throws -> FinderAIMutationPlan {
        _ = request
        _ = sessionID
        throw error
    }
}

nonisolated private struct FailingFinderAIApprovalCoordinator:
    FinderAIWorkspaceApprovalCoordinating {
    func approveTextRead(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadApproval {
        _ = planID
        _ = sessionID
        throw FinderAIToolTestError.unreachable
    }

    func readApprovedText(
        _ approval: FinderAITextReadApproval
    ) async throws -> [FinderAITextContent] {
        _ = approval
        throw FinderAIToolTestError.unreachable
    }

    func approveMutation(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationApproval {
        _ = planID
        _ = sessionID
        throw FinderAIToolTestError.unreachable
    }

    func executeApprovedMutation(
        _ approval: FinderAIMutationApproval
    ) async throws -> FinderAIExecutionReport {
        _ = approval
        throw FinderAIToolTestError.unreachable
    }
}

nonisolated private struct ReportingFinderAIApprovalCoordinator:
    FinderAIWorkspaceApprovalCoordinating {
    let base: FinderAIWorkspaceService
    let statuses: [FinderAIExecutionItemStatus]

    func approveTextRead(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadApproval {
        try await base.approveTextRead(planID: planID, in: sessionID)
    }

    func readApprovedText(
        _ approval: FinderAITextReadApproval
    ) async throws -> [FinderAITextContent] {
        try await base.readApprovedText(approval)
    }

    func approveMutation(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationApproval {
        try await base.approveMutation(planID: planID, in: sessionID)
    }

    func executeApprovedMutation(
        _ approval: FinderAIMutationApproval
    ) async throws -> FinderAIExecutionReport {
        _ = approval
        return FinderAIExecutionReport(
            planID: FinderAIPlanID(),
            results: statuses.enumerated().map { index, status in
                FinderAIExecutionItemResult(
                    id: UUID(),
                    operation: .createFolder,
                    displayName: "item-\(index + 1)",
                    resultingName: status == .completed ? "item-\(index + 1)" : nil,
                    status: status
                )
            }
        )
    }
}

nonisolated private struct NoOpFinderAIToolRevealer: FileRevealing {
    func revealInFinder(urls: [URL]) async throws {
        _ = urls
    }
}

private final class FinderAIToolTestFixture {
    let base: URL
    let root: URL
    let note: URL

    init() throws {
        let fileManager = FileManager.default
        base = fileManager.temporaryDirectory.appendingPathComponent(
            "Commandly-FinderAITool-\(UUID().uuidString)",
            isDirectory: true
        )
        root = base.appendingPathComponent("Scope", isDirectory: true)
        note = root.appendingPathComponent("note.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: note)
    }

    func makeService() async -> FinderAIWorkspaceService {
        let folderAccessStore = await MainActor.run { InMemoryFolderAccessStore() }
        return FinderAIWorkspaceService(
            folderAccessStore: folderAccessStore,
            searchService: InMemoryFileSearchService(),
            fileRevealer: NoOpFinderAIToolRevealer(),
            directAuthorizedRoots: [root],
            protectedUserHomeDirectory: base.appendingPathComponent(
                "Unrelated Home",
                isDirectory: true
            ),
            protectedVolumeRoots: [],
            commandlyOwnedDataDirectories: []
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}
