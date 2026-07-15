import AIKit
import Foundation
import SearchKit

nonisolated enum FinderAIToolExecutionOutcome: Sendable, Equatable {
    case completed(AIToolResult)
    case requiresApproval(FinderAIToolApprovalRequest)
}

/// Local-only approval request. This value is never encoded into provider traffic.
nonisolated enum FinderAIToolApprovalRequest: Sendable, Equatable {
    case textRead(call: AIToolCall, plan: FinderAITextReadPlan)
    case mutation(call: AIToolCall, plan: FinderAIMutationPlan)

    var call: AIToolCall {
        switch self {
        case .textRead(let call, _), .mutation(let call, _): return call
        }
    }

    var confirmationTitle: String {
        switch self {
        case .textRead(_, let plan):
            return plan.items.count == 1
                ? "Share File Contents"
                : "Share \(plan.items.count) Files’ Contents"
        case .mutation(_, let plan):
            switch plan.risk {
            case .createsItems: return "Create Files?"
            case .changesLocation: return "Change Files?"
            case .destructive: return "Move Files to Trash?"
            }
        }
    }

    var affectedItemCount: Int {
        switch self {
        case .textRead(_, let plan): return plan.items.count
        case .mutation(_, let plan): return plan.affectedItemCount
        }
    }
}

nonisolated protocol FinderAIToolExecuting: Sendable {
    var definitions: [AIToolDefinition] { get }
    func execute(
        _ call: AIToolCall,
        in session: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome
    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in session: FinderAISessionID
    ) async -> AIToolResult
    func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult
}

/// Provider-neutral bridge from AIKit tool calls to the local Finder safety boundary.
///
/// This type has no URL/path API. Model-provided filesystem references must be UUID handles issued
/// by `FinderAIWorkspaceService`; raw paths, file URLs, shell commands, and AppleScript are absent
/// from every schema and rejected as unknown arguments.
nonisolated struct FinderAIToolExecutor: FinderAIToolExecuting {
    nonisolated static let maximumSearchQueryByteCount = 1_024
    nonisolated static let maximumSearchRootCount = 50

    let workspace: any FinderAIWorkspaceQuerying
    let approvalCoordinator: any FinderAIWorkspaceApprovalCoordinating

    init(
        workspace: any FinderAIWorkspaceQuerying,
        approvalCoordinator: any FinderAIWorkspaceApprovalCoordinating
    ) {
        self.workspace = workspace
        self.approvalCoordinator = approvalCoordinator
    }

    var definitions: [AIToolDefinition] { Self.allDefinitions }

    func execute(
        _ call: AIToolCall,
        in session: FinderAISessionID
    ) async -> FinderAIToolExecutionOutcome {
        do {
            switch call.name {
            case ToolName.listRoots.rawValue:
                let arguments = try Arguments(call, allowed: [])
                _ = arguments
                let roots = try await workspace.authorizedRoots(in: session)
                return .completed(Self.result(call, content: .object([
                    "roots": .array(roots.map(Self.json))
                ])))

            case ToolName.search.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["query", "root_ids", "category", "limit"],
                    required: ["query"]
                )
                let query = try arguments.string("query")
                guard query.utf8.count <= Self.maximumSearchQueryByteCount else {
                    throw ExecutorError.invalidArguments
                }
                let rootIDs = try arguments.optionalUUIDArray(
                    "root_ids",
                    maximumCount: Self.maximumSearchRootCount
                ).map {
                    Set($0.map { FinderAIRootID(rawValue: $0) })
                } ?? []
                let categoryValue = try arguments.optionalString("category") ?? "all"
                guard let category = FileSearchCategory(rawValue: categoryValue) else {
                    throw ExecutorError.invalidArguments
                }
                let page = try await workspace.search(
                    FinderAISearchRequest(
                        query: query,
                        rootIDs: rootIDs,
                        category: category,
                        limit: try arguments.optionalInteger("limit") ?? 20
                    ),
                    in: session
                )
                return .completed(Self.result(call, content: Self.json(page)))

            case ToolName.listDirectory.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["directory_type", "directory_id", "limit"],
                    required: ["directory_type", "directory_id"]
                )
                let directory = try arguments.directoryReference(
                    typeKey: "directory_type",
                    idKey: "directory_id"
                )
                let page = try await workspace.listDirectory(
                    directory,
                    limit: try arguments.optionalInteger("limit") ?? 50,
                    in: session
                )
                return .completed(Self.result(call, content: Self.json(page)))

            case ToolName.metadata.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_ids"],
                    required: ["item_ids"]
                )
                let ids = try arguments.itemIDs("item_ids")
                let items = try await workspace.metadata(for: ids, in: session)
                return .completed(Self.result(call, content: .object([
                    "items": .array(items.map(Self.json))
                ])))

            case ToolName.reveal.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_ids"],
                    required: ["item_ids"]
                )
                let ids = try arguments.itemIDs("item_ids")
                try await workspace.reveal(itemIDs: ids, in: session)
                return .completed(Self.result(call, content: .object([
                    "revealed_count": .number(Double(ids.count))
                ])))

            case ToolName.readText.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_ids", "maximum_bytes"],
                    required: ["item_ids"]
                )
                let plan = try await workspace.prepareTextRead(
                    itemIDs: try arguments.itemIDs("item_ids"),
                    maximumByteCount: try arguments.optionalInteger("maximum_bytes") ?? 64 * 1_024,
                    in: session
                )
                return .requiresApproval(.textRead(call: call, plan: plan))

            case ToolName.createFolder.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["parent_type", "parent_id", "name"],
                    required: ["parent_type", "parent_id", "name"]
                )
                return try await pendingMutation(
                    call,
                    operation: .createFolder(
                        parent: arguments.directoryReference(
                            typeKey: "parent_type",
                            idKey: "parent_id"
                        ),
                        name: arguments.string("name")
                    ),
                    session: session
                )

            case ToolName.rename.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_id", "new_name"],
                    required: ["item_id", "new_name"]
                )
                return try await pendingMutation(
                    call,
                    operation: .rename(
                        item: FinderAIItemID(rawValue: arguments.uuid("item_id")),
                        newName: arguments.string("new_name")
                    ),
                    session: session
                )

            case ToolName.duplicate.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_ids", "collision_policy"],
                    required: ["item_ids"]
                )
                return try await pendingMutation(
                    call,
                    operation: .duplicate(
                        items: arguments.itemIDs("item_ids"),
                        collisionPolicy: arguments.collisionPolicy()
                    ),
                    session: session
                )

            case ToolName.copy.rawValue, ToolName.move.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: [
                        "item_ids", "destination_type", "destination_id", "collision_policy"
                    ],
                    required: ["item_ids", "destination_type", "destination_id"]
                )
                let items = try arguments.itemIDs("item_ids")
                let destination = try arguments.directoryReference(
                    typeKey: "destination_type",
                    idKey: "destination_id"
                )
                let policy = try arguments.collisionPolicy()
                let operation: FinderAIMutationOperation = call.name == ToolName.move.rawValue
                    ? .move(items: items, destination: destination, collisionPolicy: policy)
                    : .copy(items: items, destination: destination, collisionPolicy: policy)
                return try await pendingMutation(call, operation: operation, session: session)

            case ToolName.trash.rawValue:
                let arguments = try Arguments(
                    call,
                    allowed: ["item_ids"],
                    required: ["item_ids"]
                )
                return try await pendingMutation(
                    call,
                    operation: .trash(items: arguments.itemIDs("item_ids")),
                    session: session
                )

            default:
                throw ExecutorError.unknownTool
            }
        } catch {
            return .completed(Self.errorResult(call, error: error))
        }
    }

    func executeApproved(
        _ request: FinderAIToolApprovalRequest,
        in session: FinderAISessionID
    ) async -> AIToolResult {
        let call = request.call
        do {
            switch request {
            case .textRead(_, let plan):
                guard plan.sessionID == session else { throw ExecutorError.sessionMismatch }
                let approval = try await approvalCoordinator.approveTextRead(
                    planID: plan.id,
                    in: session
                )
                let contents = try await approvalCoordinator.readApprovedText(approval)
                return Self.result(call, content: .object([
                    "items": .array(contents.map(Self.json))
                ]))

            case .mutation(_, let plan):
                guard plan.sessionID == session else { throw ExecutorError.sessionMismatch }
                let approval = try await approvalCoordinator.approveMutation(
                    planID: plan.id,
                    in: session
                )
                let report = try await approvalCoordinator.executeApprovedMutation(approval)
                let status = Self.status(for: report)
                return AIToolResult(
                    callID: call.id,
                    toolName: call.name,
                    content: Self.json(report, status: status),
                    isError: status != .completed
                )
            }
        } catch {
            return Self.errorResult(call, error: error)
        }
    }

    func denied(_ request: FinderAIToolApprovalRequest) -> AIToolResult {
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
}

private extension FinderAIToolExecutor {
    nonisolated enum MutationReportStatus: String, Equatable {
        case completed
        case partial
        case failed
        case cancelled

        var summary: String {
            switch self {
            case .completed:
                "All requested Finder operations completed."
            case .partial:
                "Some requested Finder operations completed; others failed or were cancelled."
            case .failed:
                "The requested Finder operations did not complete."
            case .cancelled:
                "The requested Finder operations were cancelled."
            }
        }
    }

    nonisolated enum ToolName: String, CaseIterable {
        case listRoots = "finder_list_roots"
        case search = "finder_search"
        case listDirectory = "finder_list_directory"
        case metadata = "finder_get_metadata"
        case reveal = "finder_reveal"
        case readText = "finder_read_text"
        case createFolder = "finder_create_folder"
        case rename = "finder_rename"
        case duplicate = "finder_duplicate"
        case copy = "finder_copy"
        case move = "finder_move"
        case trash = "finder_trash"
    }

    nonisolated static let allDefinitions: [AIToolDefinition] = [
        definition(
            .listRoots,
            description: "List folders the user explicitly authorized for Finder AI.",
            properties: [:],
            required: [],
            effect: .readOnly,
            confirmation: .never
        ),
        definition(
            .search,
            description: "Search the local index and return opaque item handles and metadata.",
            properties: [
                "query": .string(
                    allowedValues: nil,
                    description: "Search text, at most 1 KiB when UTF-8 encoded."
                ),
                "root_ids": .array(
                    items: handleSchema("Authorized root UUID."),
                    description: "Optional roots to search, at most 50."
                ),
                "category": .string(
                    allowedValues: FileSearchCategory.allCases.map(\.rawValue),
                    description: "Optional file category."
                ),
                "limit": .integer(
                    minimum: 1,
                    maximum: FinderAIWorkspaceService.maximumSearchResultCount,
                    description: "Maximum results."
                )
            ],
            required: ["query"],
            effect: .readOnly,
            confirmation: .never
        ),
        definition(
            .listDirectory,
            description: "List one authorized directory without recursively traversing it.",
            properties: directoryProperties(prefix: "directory")
                .merging([
                    "limit": .integer(
                        minimum: 1,
                        maximum: FinderAIWorkspaceService.maximumDirectoryResultCount,
                        description: "Maximum entries."
                    )
                ], uniquingKeysWith: { first, _ in first }),
            required: ["directory_type", "directory_id"],
            effect: .readOnly,
            confirmation: .never
        ),
        itemArrayDefinition(
            .metadata,
            description: "Read metadata for opaque Finder item handles.",
            effect: .readOnly,
            confirmation: .never
        ),
        itemArrayDefinition(
            .reveal,
            description: "Reveal authorized items in Finder without opening or executing them.",
            effect: .readOnly,
            confirmation: .never
        ),
        definition(
            .readText,
            description: "Prepare a bounded text-content read that requires local user approval.",
            properties: [
                "item_ids": itemIDArraySchema,
                "maximum_bytes": .integer(
                    minimum: 1,
                    maximum: FinderAIWorkspaceService.maximumTextByteCount,
                    description: "Total content byte budget."
                )
            ],
            required: ["item_ids"],
            effect: .readOnly,
            confirmation: .always
        ),
        definition(
            .createFolder,
            description: "Prepare creation of one folder under an authorized parent.",
            properties: directoryProperties(prefix: "parent").merging([
                "name": .string(allowedValues: nil, description: "One filename component.")
            ], uniquingKeysWith: { first, _ in first }),
            required: ["parent_type", "parent_id", "name"],
            effect: .mutating,
            confirmation: .always
        ),
        definition(
            .rename,
            description: "Prepare an exact rename for one opaque item handle.",
            properties: [
                "item_id": handleSchema("Item UUID."),
                "new_name": .string(allowedValues: nil, description: "One filename component.")
            ],
            required: ["item_id", "new_name"],
            effect: .mutating,
            confirmation: .always
        ),
        mutationItemsDefinition(
            .duplicate,
            description: "Prepare duplicates beside authorized source items."
        ),
        transferDefinition(
            .copy,
            description: "Prepare copying authorized items into an authorized directory."
        ),
        transferDefinition(
            .move,
            description: "Prepare moving authorized items into an authorized directory."
        ),
        itemArrayDefinition(
            .trash,
            description: "Prepare moving authorized items to Trash. Permanent deletion is unavailable.",
            effect: .destructive,
            confirmation: .always
        )
    ]

    func pendingMutation(
        _ call: AIToolCall,
        operation: FinderAIMutationOperation,
        session: FinderAISessionID
    ) async throws -> FinderAIToolExecutionOutcome {
        let plan = try await workspace.planMutation(
            FinderAIMutationRequest(operations: [operation]),
            in: session
        )
        return .requiresApproval(.mutation(call: call, plan: plan))
    }

    static func result(_ call: AIToolCall, content: AIJSONValue) -> AIToolResult {
        AIToolResult(callID: call.id, toolName: call.name, content: content)
    }

    static func errorResult(_ call: AIToolCall, error: Error) -> AIToolResult {
        let details = sanitizedError(error)
        return AIToolResult(
            callID: call.id,
            toolName: call.name,
            content: .object([
                "error": .object([
                    "code": .string(details.code),
                    "message": .string(details.message)
                ])
            ]),
            isError: true
        )
    }

    static func sanitizedError(_ error: Error) -> (code: String, message: String) {
        if error is CancellationError {
            return ("cancelled", "The operation was cancelled.")
        }
        if let error = error as? ExecutorError {
            switch error {
            case .unknownTool: return ("unknown_tool", "That tool is not available.")
            case .invalidArguments: return ("invalid_arguments", "The tool arguments are invalid.")
            case .sessionMismatch: return ("session_mismatch", "That approval belongs to another session.")
            }
        }
        guard let error = error as? FinderAIWorkspaceError else {
            return ("operation_failed", "The Finder operation could not be completed.")
        }
        switch error {
        case .unknownSession, .unknownRoot, .unknownItem, .referenceExpired:
            return ("invalid_handle", "A Finder handle is invalid or expired.")
        case .noAuthorizedRoots, .unauthorized, .rootIsProtected:
            return ("access_denied", "The item is outside the current authorized folders.")
        case .itemNotFound:
            return ("not_found", "The item is no longer available.")
        case .expectedDirectory, .invalidName, .unsupportedItemKind, .emptyRequest:
            return ("invalid_arguments", "The requested Finder operation is not valid.")
        case .collision, .recursiveDestination:
            return ("conflict", "The requested destination conflicts with an existing item.")
        case .limitExceeded:
            return ("limit_exceeded", "The request exceeds the Finder tool limits.")
        case .approvalRequired, .invalidApproval, .planAlreadyConsumed:
            return ("approval_invalid", "The approval is missing, invalid, or already used.")
        case .planExpired, .itemChangedSincePreview:
            return ("stale_plan", "The files changed; review a new plan before continuing.")
        case .unreadableText:
            return ("unreadable_text", "The approved file does not contain supported text.")
        case .operationFailed:
            return ("operation_failed", "The Finder operation could not be completed.")
        }
    }

    static func json(_ root: FinderAIRootSummary) -> AIJSONValue {
        .object([
            "id": .string(root.id.rawValue.uuidString),
            "display_name": .string(root.displayName),
            "writable": .boolean(root.isWritable)
        ])
    }

    static func json(_ page: FinderAIItemPage) -> AIJSONValue {
        .object([
            "items": .array(page.items.map(json)),
            "truncated": .boolean(page.wasTruncated)
        ])
    }

    static func json(_ item: FinderAIItemSummary) -> AIJSONValue {
        var value: [String: AIJSONValue] = [
            "id": .string(item.id.rawValue.uuidString),
            "root_id": .string(item.rootID.rawValue.uuidString),
            "name": .string(item.displayName),
            "relative_location": .string(item.relativeLocation),
            "kind": .string(item.kind.rawValue),
            "tags": .array(item.tags.map(AIJSONValue.string))
        ]
        if let type = item.contentTypeIdentifier { value["content_type"] = .string(type) }
        if let bytes = item.byteCount { value["byte_count"] = .number(Double(bytes)) }
        if let created = item.createdAt { value["created_at"] = .string(created.ISO8601Format()) }
        if let modified = item.modifiedAt { value["modified_at"] = .string(modified.ISO8601Format()) }
        if let matchKind = item.matchKind { value["match_kind"] = .string(matchKind.rawValue) }
        return .object(value)
    }

    static func json(_ content: FinderAITextContent) -> AIJSONValue {
        .object([
            "item": json(content.item),
            "text": .string(content.text),
            "truncated": .boolean(content.wasTruncated)
        ])
    }

    static func status(for report: FinderAIExecutionReport) -> MutationReportStatus {
        let completedCount = report.completedCount
        let cancelledCount = report.results.count { result in
            result.status == .cancelled
        }
        guard report.results.isEmpty == false else { return .failed }
        if completedCount == report.results.count { return .completed }
        if completedCount > 0 { return .partial }
        if cancelledCount == report.results.count { return .cancelled }
        return .failed
    }

    static func json(
        _ report: FinderAIExecutionReport,
        status: MutationReportStatus
    ) -> AIJSONValue {
        let cancelledCount = report.results.count { result in
            result.status == .cancelled
        }
        let failedCount = report.results.count - report.completedCount - cancelledCount
        return .object([
            "status": .string(status.rawValue),
            "summary": .string(status.summary),
            "total_count": .number(Double(report.results.count)),
            "completed_count": .number(Double(report.completedCount)),
            "failed_count": .number(Double(failedCount)),
            "cancelled_count": .number(Double(cancelledCount)),
            "results": .array(report.results.map { result in
                var object: [String: AIJSONValue] = [
                    "operation": .string(result.operation.rawValue),
                    "name": .string(result.displayName)
                ]
                if let resultingName = result.resultingName {
                    object["resulting_name"] = .string(resultingName)
                }
                switch result.status {
                case .completed:
                    object["status"] = .string("completed")
                case .cancelled:
                    object["status"] = .string("cancelled")
                case .failed(let error):
                    object["status"] = .string("failed")
                    object["error_code"] = .string(sanitizedError(error).code)
                }
                return .object(object)
            })
        ])
    }

    static func definition(
        _ name: ToolName,
        description: String,
        properties: [String: AIJSONSchema],
        required: [String],
        effect: AIToolEffect,
        confirmation: AIToolConfirmationRequirement
    ) -> AIToolDefinition {
        AIToolDefinition(
            name: name.rawValue,
            description: description,
            inputSchema: .closedObject(properties: properties, required: required),
            effect: effect,
            confirmation: confirmation
        )
    }

    static func itemArrayDefinition(
        _ name: ToolName,
        description: String,
        effect: AIToolEffect,
        confirmation: AIToolConfirmationRequirement
    ) -> AIToolDefinition {
        definition(
            name,
            description: description,
            properties: ["item_ids": itemIDArraySchema],
            required: ["item_ids"],
            effect: effect,
            confirmation: confirmation
        )
    }

    static func mutationItemsDefinition(
        _ name: ToolName,
        description: String
    ) -> AIToolDefinition {
        definition(
            name,
            description: description,
            properties: [
                "item_ids": itemIDArraySchema,
                "collision_policy": collisionPolicySchema
            ],
            required: ["item_ids"],
            effect: .mutating,
            confirmation: .always
        )
    }

    static func transferDefinition(
        _ name: ToolName,
        description: String
    ) -> AIToolDefinition {
        definition(
            name,
            description: description,
            properties: [
                "item_ids": itemIDArraySchema,
                "destination_type": directoryTypeSchema,
                "destination_id": handleSchema("Destination directory UUID."),
                "collision_policy": collisionPolicySchema
            ],
            required: ["item_ids", "destination_type", "destination_id"],
            effect: .mutating,
            confirmation: .always
        )
    }

    static func directoryProperties(prefix: String) -> [String: AIJSONSchema] {
        [
            "\(prefix)_type": directoryTypeSchema,
            "\(prefix)_id": handleSchema("Opaque authorized directory UUID.")
        ]
    }

    static func handleSchema(_ description: String) -> AIJSONSchema {
        .string(allowedValues: nil, description: description)
    }

    static let directoryTypeSchema = AIJSONSchema.string(
        allowedValues: ["root", "item"],
        description: "Whether the UUID is a root or item handle."
    )

    static let collisionPolicySchema = AIJSONSchema.string(
        allowedValues: FinderAICollisionPolicy.allValues,
        description: "Fail on collision or choose an exact keep-both name."
    )

    static let itemIDArraySchema = AIJSONSchema.array(
        items: handleSchema("Opaque Finder item UUID."),
        description: "One or more opaque item handles."
    )
}

nonisolated private enum ExecutorError: Error {
    case unknownTool
    case invalidArguments
    case sessionMismatch
}

nonisolated private struct Arguments {
    let values: [String: AIJSONValue]

    init(
        _ call: AIToolCall,
        allowed: Set<String>,
        required: Set<String> = []
    ) throws {
        guard let values = call.arguments.objectValue,
              Set(values.keys).isSubset(of: allowed),
              required.isSubset(of: Set(values.keys)) else {
            throw ExecutorError.invalidArguments
        }
        self.values = values
    }

    func string(_ key: String) throws -> String {
        guard let value = values[key]?.stringValue, value.isEmpty == false else {
            throw ExecutorError.invalidArguments
        }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let raw = values[key] else { return nil }
        guard let value = raw.stringValue, value.isEmpty == false else {
            throw ExecutorError.invalidArguments
        }
        return value
    }

    func optionalInteger(_ key: String) throws -> Int? {
        guard let raw = values[key] else { return nil }
        guard let value = raw.numberValue,
              value.isFinite,
              value.rounded() == value,
              let integer = Int(exactly: value) else {
            throw ExecutorError.invalidArguments
        }
        return integer
    }

    func uuid(_ key: String) throws -> UUID {
        guard let value = UUID(uuidString: try string(key)) else {
            throw ExecutorError.invalidArguments
        }
        return value
    }

    func optionalUUIDArray(_ key: String, maximumCount: Int? = nil) throws -> [UUID]? {
        guard values[key] != nil else { return nil }
        return try uuidArray(key, maximumCount: maximumCount)
    }

    func uuidArray(_ key: String, maximumCount: Int? = nil) throws -> [UUID] {
        guard let values = self.values[key]?.arrayValue,
              values.isEmpty == false,
              maximumCount.map({ values.count <= $0 }) ?? true else {
            throw ExecutorError.invalidArguments
        }
        return try values.map { value in
            guard let string = value.stringValue, let uuid = UUID(uuidString: string) else {
                throw ExecutorError.invalidArguments
            }
            return uuid
        }
    }

    func itemIDs(_ key: String) throws -> [FinderAIItemID] {
        try uuidArray(key).map { FinderAIItemID(rawValue: $0) }
    }

    func directoryReference(typeKey: String, idKey: String) throws -> FinderAIDirectoryReference {
        let id = try uuid(idKey)
        switch try string(typeKey) {
        case "root": return .root(FinderAIRootID(rawValue: id))
        case "item": return .item(FinderAIItemID(rawValue: id))
        default: throw ExecutorError.invalidArguments
        }
    }

    func collisionPolicy() throws -> FinderAICollisionPolicy {
        let value = try optionalString("collision_policy") ?? FinderAICollisionPolicy.fail.rawValue
        guard let policy = FinderAICollisionPolicy(rawValue: value) else {
            throw ExecutorError.invalidArguments
        }
        return policy
    }
}

private extension FinderAICollisionPolicy {
    nonisolated static let allValues = [fail.rawValue, keepBoth.rawValue]
}
