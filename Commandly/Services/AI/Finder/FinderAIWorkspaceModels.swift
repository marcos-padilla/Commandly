import Foundation
import SearchKit

/// Identifies one in-memory Finder AI conversation boundary.
nonisolated struct FinderAISessionID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Opaque handle for an authorized folder. It intentionally contains no path information.
nonisolated struct FinderAIRootID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Opaque, session-scoped handle for a filesystem item.
nonisolated struct FinderAIItemID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct FinderAIPlanID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum FinderAIItemKind: String, Sendable, Codable, Equatable {
    case file
    case directory
    case package
    case symbolicLink
    case alias
}

nonisolated enum FinderAICapability: String, Hashable, Sendable {
    case enumerate
    case readMetadata
    case readContent
    case createChildren
    case mutateItem
    case trashItem
}

nonisolated struct FinderAIRootSummary: Sendable, Equatable, Identifiable {
    let id: FinderAIRootID
    let displayName: String
    let isWritable: Bool
}

nonisolated struct FinderAIItemSummary: Sendable, Equatable, Identifiable {
    let id: FinderAIItemID
    let rootID: FinderAIRootID
    let displayName: String
    /// A root-relative display location. Absolute local paths never enter model tool results.
    let relativeLocation: String
    let kind: FinderAIItemKind
    let contentTypeIdentifier: String?
    let byteCount: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let tags: [String]
    let matchKind: FileSearchMatchKind?
}

nonisolated struct FinderAIItemPage: Sendable, Equatable {
    let items: [FinderAIItemSummary]
    let wasTruncated: Bool
}

/// A filesystem location rendered only in Commandly's local approval UI.
///
/// This type is deliberately not `Codable`. Provider tool results continue to use the bounded,
/// root-relative location on ``FinderAIItemSummary`` and must never serialize this local path.
nonisolated struct FinderAIApprovalLocation: Sendable, Equatable {
    let rootID: FinderAIRootID
    let authorizedRootName: String
    let authorizedRootDisplayPath: String
    let rootRelativePath: String

    var userVisibleDescription: String {
        let root = "\(authorizedRootName) — \(authorizedRootDisplayPath)"
        guard rootRelativePath.isEmpty == false else { return root }
        return "\(root) › \(rootRelativePath)"
    }
}

nonisolated struct FinderAISearchRequest: Sendable, Equatable {
    let query: String
    let rootIDs: Set<FinderAIRootID>
    let category: FileSearchCategory
    let limit: Int

    init(
        query: String,
        rootIDs: Set<FinderAIRootID> = [],
        category: FileSearchCategory = .all,
        limit: Int = 20
    ) {
        self.query = query
        self.rootIDs = rootIDs
        self.category = category
        self.limit = limit
    }
}

/// Refers to an authorized directory without allowing a model to provide a path.
nonisolated enum FinderAIDirectoryReference: Sendable, Codable, Equatable, Hashable {
    case root(FinderAIRootID)
    case item(FinderAIItemID)
}

/// One local-only item row in a content-disclosure approval.
nonisolated struct FinderAIApprovalItemPreview: Sendable, Equatable, Identifiable {
    let id: FinderAIItemID
    let displayName: String
    let location: FinderAIApprovalLocation

    /// Compatibility surface used by the current approval view.
    var relativeLocation: String { location.userVisibleDescription }
}

nonisolated struct FinderAITextReadPlan: Sendable, Equatable, Identifiable {
    let id: FinderAIPlanID
    let sessionID: FinderAISessionID
    let expiresAt: Date
    let items: [FinderAIApprovalItemPreview]
    let maximumByteCount: Int

    init(
        id: FinderAIPlanID,
        sessionID: FinderAISessionID,
        expiresAt: Date,
        items: [FinderAIApprovalItemPreview],
        maximumByteCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.expiresAt = expiresAt
        self.items = items
        self.maximumByteCount = maximumByteCount
    }

    /// Source-compatible convenience for deterministic test doubles.
    ///
    /// Production plans are created by `FinderAIWorkspaceService` with an exact local root path.
    init(
        id: FinderAIPlanID,
        sessionID: FinderAISessionID,
        expiresAt: Date,
        items: [FinderAIItemSummary],
        maximumByteCount: Int
    ) {
        self.init(
            id: id,
            sessionID: sessionID,
            expiresAt: expiresAt,
            items: items.map { item in
                let fallbackRoot = "Authorized root \(item.rootID.rawValue.uuidString.prefix(8))"
                return FinderAIApprovalItemPreview(
                    id: item.id,
                    displayName: item.displayName,
                    location: FinderAIApprovalLocation(
                        rootID: item.rootID,
                        authorizedRootName: fallbackRoot,
                        authorizedRootDisplayPath: fallbackRoot,
                        rootRelativePath: item.relativeLocation
                    )
                )
            },
            maximumByteCount: maximumByteCount
        )
    }
}

nonisolated struct FinderAITextContent: Sendable, Equatable {
    let item: FinderAIItemSummary
    let text: String
    let wasTruncated: Bool
}

nonisolated enum FinderAICollisionPolicy: String, Sendable, Codable, Equatable {
    case fail
    case keepBoth
}

nonisolated enum FinderAIMutationOperation: Sendable, Equatable {
    case createFolder(parent: FinderAIDirectoryReference, name: String)
    case rename(item: FinderAIItemID, newName: String)
    case duplicate(items: [FinderAIItemID], collisionPolicy: FinderAICollisionPolicy)
    case copy(
        items: [FinderAIItemID],
        destination: FinderAIDirectoryReference,
        collisionPolicy: FinderAICollisionPolicy
    )
    case move(
        items: [FinderAIItemID],
        destination: FinderAIDirectoryReference,
        collisionPolicy: FinderAICollisionPolicy
    )
    case trash(items: [FinderAIItemID])
}

nonisolated struct FinderAIMutationRequest: Sendable, Equatable {
    let operations: [FinderAIMutationOperation]

    init(operations: [FinderAIMutationOperation]) {
        self.operations = operations
    }
}

nonisolated enum FinderAIOperationRisk: Int, Sendable, Codable, Comparable, Equatable {
    case createsItems = 1
    case changesLocation = 2
    case destructive = 3

    static func < (lhs: FinderAIOperationRisk, rhs: FinderAIOperationRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum FinderAIPlanWarning: Hashable, Sendable, Equatable {
    case affectsDirectoryContents
    case affectsPackage
    case affectsSymbolicLink
    case changesFilenameExtension
    case batchIsNotAtomic
    case collisionRenamed
}

nonisolated enum FinderAIMutationPreviewKind: String, Sendable, Equatable {
    case createFolder
    case rename
    case duplicate
    case copy
    case move
    case trash
}

/// A local-only destination displayed before a Finder mutation can run.
nonisolated enum FinderAIApprovalDestination: Sendable, Equatable {
    case authorizedLocation(FinderAIApprovalLocation)
    case trash

    var userVisibleDescription: String {
        switch self {
        case .authorizedLocation(let location): location.userVisibleDescription
        case .trash: "macOS Trash"
        }
    }
}

nonisolated struct FinderAIMutationPreview: Sendable, Equatable, Identifiable {
    let id: UUID
    let kind: FinderAIMutationPreviewKind
    /// Structured local-only locations for exact approval rendering.
    let sourceLocations: [FinderAIApprovalLocation]
    let destinations: [FinderAIApprovalDestination]
    /// Compatibility strings consumed by the current approval view.
    let sourceNames: [String]
    let destinationDescription: String?
    let resultingNames: [String]

    init(
        id: UUID,
        kind: FinderAIMutationPreviewKind,
        sourceLocations: [FinderAIApprovalLocation],
        destinations: [FinderAIApprovalDestination],
        resultingNames: [String]
    ) {
        self.id = id
        self.kind = kind
        self.sourceLocations = sourceLocations
        self.destinations = destinations
        self.sourceNames = sourceLocations.map(\.userVisibleDescription)
        let destinationDescriptions = destinations.map(\.userVisibleDescription)
        self.destinationDescription = destinationDescriptions.isEmpty
            ? nil
            : destinationDescriptions.joined(separator: " · ")
        self.resultingNames = resultingNames
    }
}

nonisolated struct FinderAIMutationPlan: Sendable, Equatable, Identifiable {
    let id: FinderAIPlanID
    let sessionID: FinderAISessionID
    let expiresAt: Date
    let risk: FinderAIOperationRisk
    let operations: [FinderAIMutationPreview]
    let warnings: Set<FinderAIPlanWarning>
    let affectedItemCount: Int
}

nonisolated enum FinderAIExecutionItemStatus: Sendable, Equatable {
    case completed
    case failed(FinderAIWorkspaceError)
    case cancelled
}

nonisolated struct FinderAIExecutionItemResult: Sendable, Equatable, Identifiable {
    let id: UUID
    let operation: FinderAIMutationPreviewKind
    let displayName: String
    let resultingName: String?
    let status: FinderAIExecutionItemStatus
}

nonisolated struct FinderAIExecutionReport: Sendable, Equatable {
    let planID: FinderAIPlanID
    let results: [FinderAIExecutionItemResult]

    var completedCount: Int {
        results.count { $0.status == .completed }
    }
}

nonisolated enum FinderAIWorkspaceError: Error, Sendable, Equatable {
    case unknownSession
    case unknownRoot
    case unknownItem
    case referenceExpired
    case noAuthorizedRoots
    case unauthorized
    case rootIsProtected
    case itemNotFound
    case expectedDirectory
    case invalidName
    case unsupportedItemKind
    case collision
    case recursiveDestination
    case limitExceeded
    case emptyRequest
    case approvalRequired
    case invalidApproval
    case planExpired
    case planAlreadyConsumed
    case itemChangedSincePreview
    case unreadableText
    case operationFailed
}

/// Read/query surface suitable for injection into model-facing tool handlers. It deliberately has
/// no method that issues an approval or executes a mutation.
nonisolated protocol FinderAIWorkspaceQuerying: Sendable {
    func beginSession() async -> FinderAISessionID
    func endSession(_ sessionID: FinderAISessionID) async
    func authorizedRoots(in sessionID: FinderAISessionID) async throws -> [FinderAIRootSummary]
    func search(
        _ request: FinderAISearchRequest,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIItemPage
    func listDirectory(
        _ directory: FinderAIDirectoryReference,
        limit: Int,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIItemPage
    func metadata(
        for itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) async throws -> [FinderAIItemSummary]
    func prepareTextRead(
        itemIDs: [FinderAIItemID],
        maximumByteCount: Int,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadPlan
    func reveal(
        itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) async throws
    func planMutation(
        _ request: FinderAIMutationRequest,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationPlan
}

/// Local UI-only surface. Do not inject this protocol into a model tool registry.
nonisolated protocol FinderAIWorkspaceApprovalCoordinating: Sendable {
    func approveTextRead(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadApproval
    func readApprovedText(_ approval: FinderAITextReadApproval) async throws -> [FinderAITextContent]
    func approveMutation(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationApproval
    func executeApprovedMutation(
        _ approval: FinderAIMutationApproval
    ) async throws -> FinderAIExecutionReport
}
