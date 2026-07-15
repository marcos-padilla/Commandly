import Darwin
import Foundation
import Infrastructure
import SearchKit
import UniformTypeIdentifiers

/// Issued only from the local approval coordinator in this file. It is not Codable and has no
/// initializer visible to model/tool integration code.
nonisolated struct FinderAITextReadApproval: Sendable {
    fileprivate let planID: FinderAIPlanID
    fileprivate let sessionID: FinderAISessionID
    fileprivate let nonce: UUID

    fileprivate init(planID: FinderAIPlanID, sessionID: FinderAISessionID, nonce: UUID) {
        self.planID = planID
        self.sessionID = sessionID
        self.nonce = nonce
    }
}

/// Opaque local authority proving that a human approved one exact, immutable plan.
nonisolated struct FinderAIMutationApproval: Sendable {
    fileprivate let planID: FinderAIPlanID
    fileprivate let sessionID: FinderAISessionID
    fileprivate let nonce: UUID

    fileprivate init(planID: FinderAIPlanID, sessionID: FinderAISessionID, nonce: UUID) {
        self.planID = planID
        self.sessionID = sessionID
        self.nonce = nonce
    }
}

nonisolated protocol FinderAITrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws
}

/// Trash is intentionally the only destructive primitive. There is no permanent-delete fallback.
nonisolated struct NativeFinderAITrashMover: FinderAITrashMoving {
    func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try FileManager().trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

/// Local, typed filesystem boundary for the built-in Finder AI extension.
///
/// Model-facing callers receive only random handles. Every filesystem access resolves those handles
/// against the current user-selected roots, and every write is separated into plan, local approval,
/// and execution phases. This service never executes shell commands, AppleScript, or permanent
/// deletion.
actor FinderAIWorkspaceService: FinderAIWorkspaceQuerying, FinderAIWorkspaceApprovalCoordinating {
    nonisolated static let maximumSearchResultCount = 50
    nonisolated static let maximumDirectoryResultCount = 100
    nonisolated static let maximumMetadataItemCount = 50
    nonisolated static let maximumTextItemCount = 5
    nonisolated static let maximumTextByteCount = 256 * 1_024
    nonisolated static let maximumMutationItemCount = 50
    nonisolated static let maximumKeepBothCandidateAttempts = 1_000

    private let folderAccessStore: any FolderAccessStoring
    private let searchService: any FileSearching
    private let fileRevealer: any FileRevealing
    private let trashMover: any FinderAITrashMoving
    private let directAuthorizedRoots: [URL]
    private let fileManager: FileManager
    private let protectedUserHomeDirectory: URL
    private let protectedVolumeRoots: [URL]?
    private let commandlyOwnedDataDirectories: [URL]
    private let now: @Sendable () -> Date
    private let planLifetime: TimeInterval

    private var sessions: [FinderAISessionID: SessionState] = [:]
    private var textPlans: [FinderAIPlanID: StoredTextPlan] = [:]
    private var mutationPlans: [FinderAIPlanID: StoredMutationPlan] = [:]

    init(
        folderAccessStore: any FolderAccessStoring,
        searchService: any FileSearching,
        fileRevealer: any FileRevealing,
        trashMover: any FinderAITrashMoving = NativeFinderAITrashMover(),
        directAuthorizedRoots: [URL] = [],
        fileManager: FileManager = FileManager(),
        protectedUserHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        protectedVolumeRoots: [URL]? = nil,
        commandlyOwnedDataDirectories: [URL]? = nil,
        planLifetime: TimeInterval = 120,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.folderAccessStore = folderAccessStore
        self.searchService = searchService
        self.fileRevealer = fileRevealer
        self.trashMover = trashMover
        self.directAuthorizedRoots = directAuthorizedRoots.map(\.standardizedFileURL)
        self.fileManager = fileManager
        self.protectedUserHomeDirectory = protectedUserHomeDirectory.standardizedFileURL
        self.protectedVolumeRoots = protectedVolumeRoots?.map(\.standardizedFileURL)
        self.commandlyOwnedDataDirectories = (
            commandlyOwnedDataDirectories
                ?? Self.defaultCommandlyOwnedDataDirectories(
                    fileManager: fileManager,
                    userHomeDirectory: protectedUserHomeDirectory
                )
        ).map(\.standardizedFileURL)
        self.planLifetime = planLifetime
        self.now = now
    }

    func beginSession() async -> FinderAISessionID {
        let id = FinderAISessionID()
        sessions[id] = SessionState()
        return id
    }

    func endSession(_ sessionID: FinderAISessionID) async {
        sessions[sessionID] = nil
        textPlans = textPlans.filter { $0.value.view.sessionID != sessionID }
        mutationPlans = mutationPlans.filter { $0.value.view.sessionID != sessionID }
    }

    func authorizedRoots(in sessionID: FinderAISessionID) async throws -> [FinderAIRootSummary] {
        let roots = try await refreshRoots(in: sessionID)
        return roots
            .map { FinderAIRootSummary(id: $0.id, displayName: $0.displayName, isWritable: true) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func search(
        _ request: FinderAISearchRequest,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        try Task.checkCancellation()
        let limit = try validatedLimit(request.limit, maximum: Self.maximumSearchResultCount)
        let normalizedQuery = SearchQuery(text: request.query)
        guard normalizedQuery.isEmpty == false else {
            throw FinderAIWorkspaceError.emptyRequest
        }
        let roots = try await refreshRoots(in: sessionID)
        guard roots.isEmpty == false else { throw FinderAIWorkspaceError.noAuthorizedRoots }
        if request.rootIDs.isEmpty == false {
            guard request.rootIDs.allSatisfy({ id in roots.contains { $0.id == id } }) else {
                throw FinderAIWorkspaceError.unknownRoot
            }
        }

        let selectedRoots = request.rootIDs.isEmpty
            ? roots
            : roots.filter { request.rootIDs.contains($0.id) }
        let stops = try startAccessing(selectedRoots)
        defer { stopAccessing(stops) }

        let searchRequest = FileSearchRequest(
            query: SearchQuery(
                text: normalizedQuery.text,
                limit: Self.maximumSearchResultCount * 4 + 1
            ),
            category: request.category,
            includesFileNames: true,
            includesFilePaths: false,
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false,
            scopeURLs: selectedRoots.map(\.url)
        )
        let hits = try await searchService.search(searchRequest)
        try Task.checkCancellation()

        let refreshedRoots = try await refreshRoots(in: sessionID)
        let selectedRootIDs = Set(selectedRoots.map(\.id))
        let currentSelectedRoots = refreshedRoots.filter { selectedRootIDs.contains($0.id) }
        var summaries: [FinderAIItemSummary] = []
        summaries.reserveCapacity(min(limit, hits.count))
        for hit in hits {
            try Task.checkCancellation()
            guard let root = mostSpecificRoot(containing: hit.url, among: currentSelectedRoots) else {
                continue
            }
            guard SearchMatchScorer.score(
                query: normalizedQuery.text,
                title: hit.name
            ) != nil else {
                continue
            }
            if let summary = try? registerItem(
                at: hit.url,
                root: root,
                matchKind: .filename,
                in: sessionID
            ) {
                summaries.append(summary)
            }
            if summaries.count > limit { break }
        }
        return FinderAIItemPage(
            items: Array(summaries.prefix(limit)),
            wasTruncated: summaries.count > limit
        )
    }

    func listDirectory(
        _ directory: FinderAIDirectoryReference,
        limit: Int,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIItemPage {
        try Task.checkCancellation()
        let limit = try validatedLimit(limit, maximum: Self.maximumDirectoryResultCount)
        _ = try await refreshRoots(in: sessionID)
        let resolved = try await resolveDirectory(directory, in: sessionID)
        let stops = try startAccessing([resolved.root])
        defer { stopAccessing(stops) }

        let keys: [URLResourceKey] = Self.metadataKeys
        guard let enumerator = fileManager.enumerator(
            at: resolved.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw FinderAIWorkspaceError.expectedDirectory
        }

        var values: [FinderAIItemSummary] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if let summary = try? registerItem(at: url, root: resolved.root, in: sessionID) {
                values.append(summary)
            }
            if values.count > limit { break }
        }
        values.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return FinderAIItemPage(
            items: Array(values.prefix(limit)),
            wasTruncated: values.count > limit
        )
    }

    func metadata(
        for itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) async throws -> [FinderAIItemSummary] {
        try Task.checkCancellation()
        guard itemIDs.isEmpty == false else { return [] }
        guard itemIDs.count <= Self.maximumMetadataItemCount else {
            throw FinderAIWorkspaceError.limitExceeded
        }
        _ = try await refreshRoots(in: sessionID)
        var results: [FinderAIItemSummary] = []
        results.reserveCapacity(itemIDs.count)
        for id in itemIDs {
            try Task.checkCancellation()
            let item = try await resolveItem(id, in: sessionID)
            let stops = try startAccessing([item.root])
            defer { stopAccessing(stops) }
            results.append(try refreshSummary(for: item, in: sessionID))
        }
        return results
    }

    func prepareTextRead(
        itemIDs: [FinderAIItemID],
        maximumByteCount: Int,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadPlan {
        try Task.checkCancellation()
        guard itemIDs.isEmpty == false else { throw FinderAIWorkspaceError.emptyRequest }
        guard itemIDs.count <= Self.maximumTextItemCount,
              (1...Self.maximumTextByteCount).contains(maximumByteCount) else {
            throw FinderAIWorkspaceError.limitExceeded
        }
        _ = try await refreshRoots(in: sessionID)

        let perItemLimit = min(64 * 1_024, max(1, maximumByteCount / itemIDs.count))
        var resolvedItems: [ResolvedTextItem] = []
        for id in itemIDs {
            try Task.checkCancellation()
            let item = try await resolveItem(id, in: sessionID)
            let stops = try startAccessing([item.root])
            defer { stopAccessing(stops) }
            let refreshed = try resolvedItem(from: item, in: sessionID)
            guard refreshed.summary.kind == .file,
                  let contentType = try? refreshed.url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                  contentType.conforms(to: .text) else {
                throw FinderAIWorkspaceError.unsupportedItemKind
            }
            resolvedItems.append(ResolvedTextItem(item: refreshed, byteLimit: perItemLimit))
        }

        let id = FinderAIPlanID()
        let view = FinderAITextReadPlan(
            id: id,
            sessionID: sessionID,
            expiresAt: now().addingTimeInterval(planLifetime),
            items: resolvedItems.map { stored in
                FinderAIApprovalItemPreview(
                    id: stored.item.summary.id,
                    displayName: stored.item.summary.displayName,
                    location: approvalLocation(for: stored.item.url, root: stored.item.root)
                )
            },
            maximumByteCount: maximumByteCount
        )
        textPlans[id] = StoredTextPlan(view: view, items: resolvedItems)
        return view
    }

    func approveTextRead(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAITextReadApproval {
        guard var stored = textPlans[planID] else { throw FinderAIWorkspaceError.approvalRequired }
        try validatePlan(stored.view.expiresAt, sessionID: stored.view.sessionID, requested: sessionID)
        guard stored.isConsumed == false, stored.approvalNonce == nil else {
            throw FinderAIWorkspaceError.planAlreadyConsumed
        }
        let nonce = UUID()
        stored.approvalNonce = nonce
        textPlans[planID] = stored
        return FinderAITextReadApproval(planID: planID, sessionID: sessionID, nonce: nonce)
    }

    func readApprovedText(_ approval: FinderAITextReadApproval) async throws -> [FinderAITextContent] {
        try Task.checkCancellation()
        guard var stored = textPlans[approval.planID] else {
            throw FinderAIWorkspaceError.invalidApproval
        }
        try validatePlan(
            stored.view.expiresAt,
            sessionID: stored.view.sessionID,
            requested: approval.sessionID
        )
        guard stored.isConsumed == false, stored.approvalNonce == approval.nonce else {
            throw FinderAIWorkspaceError.invalidApproval
        }
        stored.isConsumed = true
        textPlans[approval.planID] = stored

        _ = try await refreshRoots(in: approval.sessionID)
        var remaining = stored.view.maximumByteCount
        var output: [FinderAITextContent] = []
        for storedItem in stored.items {
            try Task.checkCancellation()
            let item = try await resolveStoredItem(storedItem.item, in: approval.sessionID)
            guard item.identity == storedItem.item.identity else {
                throw FinderAIWorkspaceError.itemChangedSincePreview
            }
            let stops = try startAccessing([item.root])
            defer { stopAccessing(stops) }
            let allowed = min(storedItem.byteLimit, remaining)
            guard allowed > 0 else { break }
            let data: Data
            do {
                let descriptor = Darwin.open(
                    item.url.path,
                    O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                )
                guard descriptor >= 0 else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
                defer { _ = Darwin.close(descriptor) }
                guard try identity(ofOpenedDescriptor: descriptor) == storedItem.item.identity else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                data = try handle.read(upToCount: allowed + 1) ?? Data()
                guard try identity(ofOpenedDescriptor: descriptor) == storedItem.item.identity else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
            } catch {
                throw mapOperationError(error)
            }
            try Task.checkCancellation()
            let visibleData = Data(data.prefix(allowed))
            let text = String(data: visibleData, encoding: .utf8)
                ?? (data.count > allowed ? Self.decodeUTF8PrefixCutByLimit(visibleData) : nil)
            guard let text else {
                throw FinderAIWorkspaceError.unreadableText
            }
            output.append(FinderAITextContent(
                item: storedItem.item.summary,
                text: text,
                wasTruncated: data.count > allowed
            ))
            remaining -= visibleData.count
        }
        return output
    }

    func reveal(
        itemIDs: [FinderAIItemID],
        in sessionID: FinderAISessionID
    ) async throws {
        try Task.checkCancellation()
        guard itemIDs.isEmpty == false, itemIDs.count <= Self.maximumMetadataItemCount else {
            throw FinderAIWorkspaceError.limitExceeded
        }
        _ = try await refreshRoots(in: sessionID)
        var items: [ResolvedItem] = []
        for id in itemIDs {
            items.append(try await resolveItem(id, in: sessionID))
        }
        let stops = try startAccessing(uniqueRoots(items.map(\.root)))
        defer { stopAccessing(stops) }
        try await fileRevealer.revealInFinder(urls: items.map(\.url))
    }

    func planMutation(
        _ request: FinderAIMutationRequest,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationPlan {
        try Task.checkCancellation()
        guard request.operations.isEmpty == false else { throw FinderAIWorkspaceError.emptyRequest }
        _ = try await refreshRoots(in: sessionID)

        var actions: [ResolvedMutationAction] = []
        var previews: [FinderAIMutationPreview] = []
        var warnings: Set<FinderAIPlanWarning> = []
        var risk = FinderAIOperationRisk.createsItems
        var reservedDestinations: Set<String> = []
        var sourcePaths: Set<String> = []

        for operation in request.operations {
            try Task.checkCancellation()
            let planned = try await plan(
                operation,
                sessionID: sessionID,
                reservedDestinations: &reservedDestinations,
                sourcePaths: &sourcePaths
            )
            actions.append(contentsOf: planned.actions)
            previews.append(planned.preview)
            warnings.formUnion(planned.warnings)
            risk = max(risk, planned.risk)
            guard actions.count <= Self.maximumMutationItemCount else {
                throw FinderAIWorkspaceError.limitExceeded
            }
        }
        if actions.count > 1 { warnings.insert(.batchIsNotAtomic) }

        let id = FinderAIPlanID()
        let view = FinderAIMutationPlan(
            id: id,
            sessionID: sessionID,
            expiresAt: now().addingTimeInterval(planLifetime),
            risk: risk,
            operations: previews,
            warnings: warnings,
            affectedItemCount: actions.count
        )
        mutationPlans[id] = StoredMutationPlan(view: view, actions: actions)
        return view
    }

    func approveMutation(
        planID: FinderAIPlanID,
        in sessionID: FinderAISessionID
    ) async throws -> FinderAIMutationApproval {
        guard var stored = mutationPlans[planID] else {
            throw FinderAIWorkspaceError.approvalRequired
        }
        try validatePlan(stored.view.expiresAt, sessionID: stored.view.sessionID, requested: sessionID)
        guard stored.isConsumed == false, stored.approvalNonce == nil else {
            throw FinderAIWorkspaceError.planAlreadyConsumed
        }
        let nonce = UUID()
        stored.approvalNonce = nonce
        mutationPlans[planID] = stored
        return FinderAIMutationApproval(planID: planID, sessionID: sessionID, nonce: nonce)
    }

    func executeApprovedMutation(
        _ approval: FinderAIMutationApproval
    ) async throws -> FinderAIExecutionReport {
        try Task.checkCancellation()
        guard var stored = mutationPlans[approval.planID] else {
            throw FinderAIWorkspaceError.invalidApproval
        }
        try validatePlan(
            stored.view.expiresAt,
            sessionID: stored.view.sessionID,
            requested: approval.sessionID
        )
        guard stored.isConsumed == false, stored.approvalNonce == approval.nonce else {
            throw FinderAIWorkspaceError.invalidApproval
        }
        stored.isConsumed = true
        mutationPlans[approval.planID] = stored

        _ = try await refreshRoots(in: approval.sessionID)
        let rootIDs = Set(stored.actions.flatMap(\.rootIDs))
        var roots: [RootRecord] = []
        for rootID in rootIDs {
            roots.append(try await currentRoot(rootID, in: approval.sessionID))
        }
        let stops = try startAccessing(uniqueRoots(roots))
        defer { stopAccessing(stops) }
        try await preflight(stored.actions, in: approval.sessionID)

        var results: [FinderAIExecutionItemResult] = []
        for (index, action) in stored.actions.enumerated() {
            if Task.isCancelled {
                for pending in stored.actions[index...] {
                    results.append(pending.result(status: .cancelled, resultingName: nil))
                }
                break
            }
            do {
                // Revalidate immediately before each filesystem primitive. The up-front preflight
                // prevents known-invalid batches from partially executing; this second check closes
                // the longer window introduced by earlier actions in the same batch.
                try await preflight([action], in: approval.sessionID)
                let resultingName = try execute(action)
                results.append(action.result(status: .completed, resultingName: resultingName))
                invalidateSourceHandle(for: action, in: approval.sessionID)
            } catch {
                results.append(action.result(
                    status: .failed(mapOperationError(error)),
                    resultingName: nil
                ))
            }
        }
        return FinderAIExecutionReport(planID: approval.planID, results: results)
    }
}

private extension FinderAIWorkspaceService {
    nonisolated static let metadataKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .isAliasFileKey,
        .contentTypeKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .tagNamesKey
    ]

    struct SessionState {
        var roots: [FinderAIRootID: RootRecord] = [:]
        var items: [FinderAIItemID: ItemRecord] = [:]
    }

    enum RootSource: Hashable {
        case direct(String)
        case bookmark(Data)
    }

    struct RootCandidate {
        let source: RootSource
        let url: URL
        let requiresSecurityScope: Bool
    }

    struct RootRecord: Equatable {
        let id: FinderAIRootID
        let source: RootSource
        let url: URL
        let displayName: String
        let requiresSecurityScope: Bool
    }

    struct ItemRecord {
        let id: FinderAIItemID
        let rootID: FinderAIRootID
        let url: URL
        var summary: FinderAIItemSummary
    }

    struct FileIdentity: Sendable, Equatable {
        let systemNumber: UInt64
        let fileNumber: UInt64
        let fileType: String
        let byteCount: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    struct ResolvedItem {
        let recordID: FinderAIItemID
        let root: RootRecord
        let url: URL
        let summary: FinderAIItemSummary
        let identity: FileIdentity
    }

    struct ResolvedDirectory {
        let root: RootRecord
        let url: URL
        let identity: FileIdentity
    }

    struct ResolvedTextItem {
        let item: ResolvedItem
        let byteLimit: Int
    }

    struct StoredTextPlan {
        let view: FinderAITextReadPlan
        let items: [ResolvedTextItem]
        var approvalNonce: UUID?
        var isConsumed = false
    }

    enum ResolvedMutationAction {
        case createFolder(
            parent: ResolvedDirectory,
            destination: URL,
            displayName: String,
            rootID: FinderAIRootID
        )
        case rename(source: ResolvedItem, destination: URL, resultingName: String)
        case duplicate(source: ResolvedItem, destination: URL)
        case copy(source: ResolvedItem, destination: ResolvedDirectory, output: URL)
        case move(source: ResolvedItem, destination: ResolvedDirectory, output: URL)
        case trash(source: ResolvedItem)

        var rootIDs: [FinderAIRootID] {
            switch self {
            case .createFolder(_, _, _, let rootID): return [rootID]
            case .rename(let source, _, _), .duplicate(let source, _), .trash(let source):
                return [source.root.id]
            case .copy(let source, let destination, _), .move(let source, let destination, _):
                return [source.root.id, destination.root.id]
            }
        }

        var source: ResolvedItem? {
            switch self {
            case .createFolder: return nil
            case .rename(let source, _, _), .duplicate(let source, _),
                 .copy(let source, _, _), .move(let source, _, _), .trash(let source):
                return source
            }
        }

        var destinationURL: URL? {
            switch self {
            case .createFolder(_, let destination, _, _), .rename(_, let destination, _),
                 .duplicate(_, let destination), .copy(_, _, let destination),
                 .move(_, _, let destination):
                return destination
            case .trash:
                return nil
            }
        }

        var destinationDirectory: ResolvedDirectory? {
            switch self {
            case .createFolder(let parent, _, _, _): return parent
            case .copy(_, let destination, _), .move(_, let destination, _): return destination
            case .rename, .duplicate, .trash: return nil
            }
        }

        var destinationRootID: FinderAIRootID? {
            switch self {
            case .createFolder(_, _, _, let rootID):
                rootID
            case .rename(let source, _, _), .duplicate(let source, _):
                source.root.id
            case .copy(_, let destination, _), .move(_, let destination, _):
                destination.root.id
            case .trash:
                nil
            }
        }

        var previewKind: FinderAIMutationPreviewKind {
            switch self {
            case .createFolder: return .createFolder
            case .rename: return .rename
            case .duplicate: return .duplicate
            case .copy: return .copy
            case .move: return .move
            case .trash: return .trash
            }
        }

        var displayName: String {
            switch self {
            case .createFolder(_, _, let displayName, _): return displayName
            case .rename(let source, _, _), .duplicate(let source, _),
                 .copy(let source, _, _), .move(let source, _, _), .trash(let source):
                return source.summary.displayName
            }
        }

        func result(
            status: FinderAIExecutionItemStatus,
            resultingName: String?
        ) -> FinderAIExecutionItemResult {
            FinderAIExecutionItemResult(
                id: UUID(),
                operation: previewKind,
                displayName: displayName,
                resultingName: resultingName,
                status: status
            )
        }
    }

    struct PlannedOperation {
        let actions: [ResolvedMutationAction]
        let preview: FinderAIMutationPreview
        let warnings: Set<FinderAIPlanWarning>
        let risk: FinderAIOperationRisk
    }

    struct StoredMutationPlan {
        let view: FinderAIMutationPlan
        let actions: [ResolvedMutationAction]
        var approvalNonce: UUID?
        var isConsumed = false
    }
}

private extension FinderAIWorkspaceService {
    func refreshRoots(in sessionID: FinderAISessionID) async throws -> [RootRecord] {
        guard var session = sessions[sessionID] else { throw FinderAIWorkspaceError.unknownSession }
        let candidates = await resolvedRootCandidates()
        var oldBySource = Dictionary(
            uniqueKeysWithValues: session.roots.values.map { ($0.source, $0) }
        )
        var refreshed: [FinderAIRootID: RootRecord] = [:]

        for candidate in candidates {
            let old = oldBySource.removeValue(forKey: candidate.source)
            let rootID = old?.id ?? FinderAIRootID()
            let record = RootRecord(
                id: rootID,
                source: candidate.source,
                url: candidate.url,
                displayName: fileManager.displayName(atPath: candidate.url.path),
                requiresSecurityScope: candidate.requiresSecurityScope
            )
            refreshed[rootID] = record
            if let old, old.url.standardizedFileURL != candidate.url.standardizedFileURL {
                session.items = session.items.filter { $0.value.rootID != rootID }
            }
        }

        let removedRootIDs = Set(oldBySource.values.map(\.id))
        if removedRootIDs.isEmpty == false {
            session.items = session.items.filter { removedRootIDs.contains($0.value.rootID) == false }
        }
        session.roots = refreshed
        sessions[sessionID] = session
        return Array(refreshed.values)
    }

    func resolvedRootCandidates() async -> [RootCandidate] {
        var candidates: [RootCandidate] = []
        var seenPaths: Set<String> = []

        for suppliedURL in directAuthorizedRoots {
            let url = suppliedURL.standardizedFileURL
            guard isUsableRootCandidate(url, requiresSecurityScope: false),
                  seenPaths.insert(url.path).inserted else { continue }
            candidates.append(RootCandidate(
                source: .direct(url.path),
                url: url,
                requiresSecurityScope: false
            ))
        }

        guard directAuthorizedRoots.isEmpty else { return candidates }
        let bookmarkData = await folderAccessStore.bookmarkData
        for data in bookmarkData {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isStale == false else { continue }
            let url = resolved.standardizedFileURL
            guard isUsableRootCandidate(url, requiresSecurityScope: true),
                  seenPaths.insert(url.path).inserted else { continue }
            candidates.append(RootCandidate(
                source: .bookmark(data),
                url: url,
                requiresSecurityScope: true
            ))
        }
        return candidates
    }

    func isUsableRootCandidate(_ url: URL, requiresSecurityScope: Bool) -> Bool {
        let didStartAccessing: Bool
        if requiresSecurityScope {
            didStartAccessing = url.startAccessingSecurityScopedResource()
            guard didStartAccessing else { return false }
        } else {
            didStartAccessing = false
        }
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return isProtectedRootCandidate(url) == false
    }

    func isProtectedRootCandidate(_ url: URL) -> Bool {
        let physicalCandidate = url.resolvingSymlinksInPath().standardizedFileURL
        let physicalHome = protectedUserHomeDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isLexicallyContained(physicalHome, in: physicalCandidate) == false else {
            return true
        }
        if let protectedVolumeRoots {
            if protectedVolumeRoots.contains(where: {
                $0.resolvingSymlinksInPath().standardizedFileURL == physicalCandidate
            }) {
                return true
            }
        } else if let volume = try? physicalCandidate.resourceValues(
            forKeys: [.volumeURLKey]
        ).volume,
                  volume.resolvingSymlinksInPath().standardizedFileURL == physicalCandidate {
            return true
        }
        return isCommandlyOwnedData(physicalCandidate, kind: .directory)
    }

    func currentRoot(
        _ rootID: FinderAIRootID,
        in sessionID: FinderAISessionID
    ) async throws -> RootRecord {
        _ = try await refreshRoots(in: sessionID)
        guard let root = sessions[sessionID]?.roots[rootID] else {
            throw FinderAIWorkspaceError.unknownRoot
        }
        return root
    }

    func uniqueRoots(_ roots: [RootRecord]) -> [RootRecord] {
        var seen: Set<FinderAIRootID> = []
        return roots.filter { seen.insert($0.id).inserted }
    }

    func startAccessing(_ roots: [RootRecord]) throws -> [URL] {
        var started: [URL] = []
        for root in uniqueRoots(roots) where root.requiresSecurityScope {
            guard root.url.startAccessingSecurityScopedResource() else {
                started.forEach { $0.stopAccessingSecurityScopedResource() }
                throw FinderAIWorkspaceError.unauthorized
            }
            started.append(root.url)
        }
        return started
    }

    func stopAccessing(_ urls: [URL]) {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    func mostSpecificRoot(containing url: URL, among roots: [RootRecord]) -> RootRecord? {
        roots
            .filter { isLexicallyContained(url, in: $0.url) }
            .max { $0.url.path.count < $1.url.path.count }
    }

    func isLexicallyContained(_ item: URL, in root: URL) -> Bool {
        let itemPath = item.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return itemPath == rootPath || itemPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/")
    }

    static func defaultCommandlyOwnedDataDirectories(
        fileManager: FileManager,
        userHomeDirectory: URL
    ) -> [URL] {
        var values: [URL] = []
        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            values.append(applicationSupport.appendingPathComponent("Commandly", isDirectory: true))
        }
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            values.append(caches.appendingPathComponent("Commandly", isDirectory: true))
        }
        values.append(fileManager.temporaryDirectory.appendingPathComponent("Commandly", isDirectory: true))

        let processHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
        if processHome.path.contains("/Library/Containers/") {
            values.append(processHome)
        }
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           bundleIdentifier.isEmpty == false {
            values.append(
                userHomeDirectory
                    .standardizedFileURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Containers", isDirectory: true)
                    .appendingPathComponent(bundleIdentifier, isDirectory: true)
            )
            let containerDerivationCandidates = values + [processHome]
            values.append(contentsOf: containerDerivationCandidates.compactMap {
                sandboxContainerRoot(containing: $0, bundleIdentifier: bundleIdentifier)
            })
        }

        var seen: Set<String> = []
        return values
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
    }

    static func sandboxContainerRoot(
        containing url: URL,
        bundleIdentifier: String
    ) -> URL? {
        let path = url.standardizedFileURL.path
        let marker = "/Library/Containers/\(bundleIdentifier)"
        guard let range = path.range(of: marker) else { return nil }
        let suffix = path[range.upperBound...]
        guard suffix.isEmpty || suffix.first == "/" else { return nil }
        return URL(
            fileURLWithPath: String(path[..<range.upperBound]),
            isDirectory: true
        ).standardizedFileURL
    }

    func isCommandlyOwnedData(_ url: URL, kind: FinderAIItemKind?) -> Bool {
        let lexicalURL = url.standardizedFileURL
        if commandlyOwnedDataDirectories.contains(where: {
            isLexicallyContained(lexicalURL, in: $0)
        }) {
            return true
        }
        guard kind != .symbolicLink, kind != .alias else { return false }
        let physicalURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
        return commandlyOwnedDataDirectories.contains(where: { protectedDirectory in
            isLexicallyContained(
                physicalURL,
                in: protectedDirectory.resolvingSymlinksInPath().standardizedFileURL
            )
        })
    }

    func isPhysicallyContained(_ item: URL, kind: FinderAIItemKind, in root: URL) -> Bool {
        let physicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let physicalItem: URL
        if kind == .symbolicLink {
            physicalItem = item.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        } else {
            physicalItem = item.resolvingSymlinksInPath().standardizedFileURL
        }
        return isLexicallyContained(physicalItem, in: physicalRoot)
    }

    func registerItem(
        at suppliedURL: URL,
        root: RootRecord,
        matchKind: FileSearchMatchKind? = nil,
        in sessionID: FinderAISessionID
    ) throws -> FinderAIItemSummary {
        guard var session = sessions[sessionID], session.roots[root.id] != nil else {
            throw FinderAIWorkspaceError.unknownSession
        }
        let url = suppliedURL.standardizedFileURL
        let isAuthorizationRoot = session.roots.values.contains {
            $0.url.standardizedFileURL == url
        }
        guard isAuthorizationRoot == false,
              isLexicallyContained(url, in: root.url) else {
            throw isAuthorizationRoot
                ? FinderAIWorkspaceError.rootIsProtected
                : FinderAIWorkspaceError.unauthorized
        }
        guard isCommandlyOwnedData(url, kind: nil) == false else {
            throw FinderAIWorkspaceError.unauthorized
        }
        let metadata = try metadataValues(at: url)
        guard isPhysicallyContained(url, kind: metadata.kind, in: root.url),
              isCommandlyOwnedData(url, kind: metadata.kind) == false else {
            throw FinderAIWorkspaceError.unauthorized
        }

        if let existing = session.items.values.first(where: {
            $0.rootID == root.id && $0.url.standardizedFileURL == url
        }) {
            let summary = summary(
                id: existing.id,
                root: root,
                url: url,
                metadata: metadata,
                matchKind: matchKind ?? existing.summary.matchKind
            )
            var updated = existing
            updated.summary = summary
            session.items[existing.id] = updated
            sessions[sessionID] = session
            return summary
        }

        let id = FinderAIItemID()
        let summary = summary(
            id: id,
            root: root,
            url: url,
            metadata: metadata,
            matchKind: matchKind
        )
        session.items[id] = ItemRecord(id: id, rootID: root.id, url: url, summary: summary)
        sessions[sessionID] = session
        return summary
    }

    func resolveItem(
        _ id: FinderAIItemID,
        in sessionID: FinderAISessionID
    ) async throws -> ResolvedItem {
        guard let session = sessions[sessionID] else { throw FinderAIWorkspaceError.unknownSession }
        guard let record = session.items[id] else { throw FinderAIWorkspaceError.unknownItem }
        let root = try await currentRoot(record.rootID, in: sessionID)
        guard isLexicallyContained(record.url, in: root.url),
              record.url.standardizedFileURL != root.url.standardizedFileURL else {
            throw FinderAIWorkspaceError.referenceExpired
        }
        let stops = try startAccessing([root])
        defer { stopAccessing(stops) }
        return try resolvedItem(record: record, root: root, in: sessionID)
    }

    func resolvedItem(
        from item: ResolvedItem,
        in sessionID: FinderAISessionID
    ) throws -> ResolvedItem {
        let record = ItemRecord(
            id: item.recordID,
            rootID: item.root.id,
            url: item.url,
            summary: item.summary
        )
        return try resolvedItem(record: record, root: item.root, in: sessionID)
    }

    func resolvedItem(
        record: ItemRecord,
        root: RootRecord,
        in sessionID: FinderAISessionID
    ) throws -> ResolvedItem {
        let refreshedSummary = try registerItem(
            at: record.url,
            root: root,
            matchKind: record.summary.matchKind,
            in: sessionID
        )
        return ResolvedItem(
            recordID: record.id,
            root: root,
            url: record.url.standardizedFileURL,
            summary: refreshedSummary,
            identity: try identity(at: record.url)
        )
    }

    func resolveStoredItem(
        _ stored: ResolvedItem,
        in sessionID: FinderAISessionID
    ) async throws -> ResolvedItem {
        let current = try await resolveItem(stored.recordID, in: sessionID)
        guard current.url.standardizedFileURL == stored.url.standardizedFileURL else {
            throw FinderAIWorkspaceError.itemChangedSincePreview
        }
        return current
    }

    func refreshSummary(for item: ResolvedItem, in sessionID: FinderAISessionID) throws -> FinderAIItemSummary {
        try resolvedItem(from: item, in: sessionID).summary
    }

    func resolveDirectory(
        _ reference: FinderAIDirectoryReference,
        in sessionID: FinderAISessionID
    ) async throws -> ResolvedDirectory {
        switch reference {
        case .root(let rootID):
            let root = try await currentRoot(rootID, in: sessionID)
            let stops = try startAccessing([root])
            defer { stopAccessing(stops) }
            return ResolvedDirectory(root: root, url: root.url, identity: try identity(at: root.url))
        case .item(let itemID):
            let item = try await resolveItem(itemID, in: sessionID)
            guard item.summary.kind == .directory else {
                throw FinderAIWorkspaceError.expectedDirectory
            }
            return ResolvedDirectory(root: item.root, url: item.url, identity: item.identity)
        }
    }

    struct MetadataValues {
        let displayName: String
        let kind: FinderAIItemKind
        let contentTypeIdentifier: String?
        let byteCount: Int64?
        let createdAt: Date?
        let modifiedAt: Date?
        let tags: [String]
    }

    func metadataValues(at url: URL) throws -> MetadataValues {
        guard fileManager.fileExists(atPath: url.path) || isSymbolicLink(at: url) else {
            throw FinderAIWorkspaceError.itemNotFound
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: Set(Self.metadataKeys))
        } catch {
            throw mapOperationError(error)
        }
        let kind: FinderAIItemKind
        if values.isSymbolicLink == true {
            kind = .symbolicLink
        } else if values.isAliasFile == true {
            kind = .alias
        } else if values.isPackage == true {
            kind = .package
        } else if values.isDirectory == true {
            kind = .directory
        } else if values.isRegularFile == true {
            kind = .file
        } else {
            throw FinderAIWorkspaceError.unsupportedItemKind
        }
        return MetadataValues(
            displayName: values.name ?? url.lastPathComponent,
            kind: kind,
            contentTypeIdentifier: values.contentType?.identifier,
            byteCount: values.fileSize.map(Int64.init),
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            tags: values.tagNames ?? []
        )
    }

    func summary(
        id: FinderAIItemID,
        root: RootRecord,
        url: URL,
        metadata: MetadataValues,
        matchKind: FileSearchMatchKind?
    ) -> FinderAIItemSummary {
        let rootPath = root.url.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        let relative = itemPath.dropFirst(rootPath.count).drop(while: { $0 == "/" })
        return FinderAIItemSummary(
            id: id,
            rootID: root.id,
            displayName: metadata.displayName,
            relativeLocation: String(relative),
            kind: metadata.kind,
            contentTypeIdentifier: metadata.contentTypeIdentifier,
            byteCount: metadata.byteCount,
            createdAt: metadata.createdAt,
            modifiedAt: metadata.modifiedAt,
            tags: metadata.tags,
            matchKind: matchKind
        )
    }

    nonisolated static func decodeUTF8PrefixCutByLimit(_ data: Data) -> String? {
        guard data.isEmpty == false else { return "" }
        let bytes = [UInt8](data)
        var leadIndex = bytes.count - 1
        while leadIndex > 0, bytes[leadIndex] & 0b1100_0000 == 0b1000_0000 {
            leadIndex -= 1
        }
        let lead = bytes[leadIndex]
        let expectedLength: Int
        switch lead {
        case 0xC2 ... 0xDF:
            expectedLength = 2
        case 0xE0 ... 0xEF:
            expectedLength = 3
        case 0xF0 ... 0xF4:
            expectedLength = 4
        default:
            return nil
        }
        let actualLength = bytes.count - leadIndex
        guard actualLength < expectedLength,
              bytes[(leadIndex + 1)...].allSatisfy({ $0 & 0b1100_0000 == 0b1000_0000 }) else {
            return nil
        }
        return String(data: data.prefix(leadIndex), encoding: .utf8)
    }

    func isSymbolicLink(at url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType)
            == .typeSymbolicLink
    }

    func identity(at url: URL) throws -> FileIdentity {
        var itemStatus = stat()
        guard Darwin.lstat(url.path, &itemStatus) == 0 else {
            throw FinderAIWorkspaceError.itemNotFound
        }
        return identity(from: itemStatus)
    }

    func identity(ofOpenedDescriptor descriptor: Int32) throws -> FileIdentity {
        var descriptorStatus = stat()
        guard Darwin.fstat(descriptor, &descriptorStatus) == 0,
              descriptorStatus.st_mode & S_IFMT == S_IFREG else {
            throw FinderAIWorkspaceError.itemChangedSincePreview
        }
        return identity(from: descriptorStatus)
    }

    func identity(from itemStatus: stat) -> FileIdentity {
        return FileIdentity(
            systemNumber: UInt64(itemStatus.st_dev),
            fileNumber: UInt64(itemStatus.st_ino),
            fileType: fileType(for: itemStatus.st_mode).rawValue,
            byteCount: UInt64(max(0, itemStatus.st_size)),
            modifiedSeconds: Int64(itemStatus.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(itemStatus.st_mtimespec.tv_nsec)
        )
    }

    func fileType(for mode: mode_t) -> FileAttributeType {
        switch mode & S_IFMT {
        case S_IFREG: .typeRegular
        case S_IFDIR: .typeDirectory
        case S_IFLNK: .typeSymbolicLink
        case S_IFCHR: .typeCharacterSpecial
        case S_IFBLK: .typeBlockSpecial
        case S_IFSOCK: .typeSocket
        default: .typeUnknown
        }
    }

    func validatedLimit(_ limit: Int, maximum: Int) throws -> Int {
        guard (1...maximum).contains(limit) else { throw FinderAIWorkspaceError.limitExceeded }
        return limit
    }

    func validatePlan(
        _ expiresAt: Date,
        sessionID: FinderAISessionID,
        requested: FinderAISessionID
    ) throws {
        guard sessionID == requested, sessions[requested] != nil else {
            throw FinderAIWorkspaceError.invalidApproval
        }
        guard expiresAt > now() else { throw FinderAIWorkspaceError.planExpired }
    }
}

private extension FinderAIWorkspaceService {
    func plan(
        _ operation: FinderAIMutationOperation,
        sessionID: FinderAISessionID,
        reservedDestinations: inout Set<String>,
        sourcePaths: inout Set<String>
    ) async throws -> PlannedOperation {
        switch operation {
        case .createFolder(let parentReference, let name):
            try validateNewName(name)
            let parent = try await resolveDirectory(parentReference, in: sessionID)
            let destination = parent.url.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            try reserveExactDestination(destination, in: parent.root, reserved: &reservedDestinations)
            return PlannedOperation(
                actions: [.createFolder(
                    parent: parent,
                    destination: destination,
                    displayName: name,
                    rootID: parent.root.id
                )],
                preview: FinderAIMutationPreview(
                    id: UUID(),
                    kind: .createFolder,
                    sourceLocations: [],
                    destinations: [
                        .authorizedLocation(approvalLocation(for: destination, root: parent.root))
                    ],
                    resultingNames: [name]
                ),
                warnings: [],
                risk: .createsItems
            )

        case .rename(let itemID, let newName):
            try validateNewName(newName)
            let source = try await resolveItem(itemID, in: sessionID)
            try reserveSource(source, in: sessionID, used: &sourcePaths)
            guard source.summary.displayName != newName else {
                throw FinderAIWorkspaceError.invalidName
            }
            let destination = source.url.deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: source.summary.kind == .directory)
                .standardizedFileURL
            try reserveExactDestination(destination, in: source.root, reserved: &reservedDestinations)
            var warnings = warnings(for: source)
            if source.url.pathExtension != destination.pathExtension {
                warnings.insert(.changesFilenameExtension)
            }
            return PlannedOperation(
                actions: [.rename(source: source, destination: destination, resultingName: newName)],
                preview: FinderAIMutationPreview(
                    id: UUID(),
                    kind: .rename,
                    sourceLocations: [approvalLocation(for: source.url, root: source.root)],
                    destinations: [
                        .authorizedLocation(approvalLocation(for: destination, root: source.root))
                    ],
                    resultingNames: [newName]
                ),
                warnings: warnings,
                risk: .changesLocation
            )

        case .duplicate(let itemIDs, let collisionPolicy):
            let sources = try await resolvedSources(itemIDs, sessionID: sessionID, used: &sourcePaths)
            var actions: [ResolvedMutationAction] = []
            var outputs: [String] = []
            var destinations: [FinderAIApprovalDestination] = []
            var allWarnings: Set<FinderAIPlanWarning> = []
            for source in sources {
                let preferredName = duplicateName(for: source.url)
                let destination = try reserveDestination(
                    named: preferredName,
                    in: source.url.deletingLastPathComponent(),
                    root: source.root,
                    collisionPolicy: collisionPolicy,
                    reserved: &reservedDestinations
                )
                if destination.lastPathComponent != preferredName {
                    allWarnings.insert(.collisionRenamed)
                }
                allWarnings.formUnion(warnings(for: source))
                actions.append(.duplicate(source: source, destination: destination))
                outputs.append(destination.lastPathComponent)
                destinations.append(
                    .authorizedLocation(approvalLocation(for: destination, root: source.root))
                )
            }
            return PlannedOperation(
                actions: actions,
                preview: FinderAIMutationPreview(
                    id: UUID(),
                    kind: .duplicate,
                    sourceLocations: sources.map {
                        approvalLocation(for: $0.url, root: $0.root)
                    },
                    destinations: destinations,
                    resultingNames: outputs
                ),
                warnings: allWarnings,
                risk: .createsItems
            )

        case .copy(let itemIDs, let destinationReference, let collisionPolicy):
            let sources = try await resolvedSources(itemIDs, sessionID: sessionID, used: &sourcePaths)
            let destination = try await resolveDirectory(destinationReference, in: sessionID)
            return try plannedTransfer(
                sources: sources,
                destination: destination,
                collisionPolicy: collisionPolicy,
                isMove: false,
                reservedDestinations: &reservedDestinations
            )

        case .move(let itemIDs, let destinationReference, let collisionPolicy):
            let sources = try await resolvedSources(itemIDs, sessionID: sessionID, used: &sourcePaths)
            let destination = try await resolveDirectory(destinationReference, in: sessionID)
            return try plannedTransfer(
                sources: sources,
                destination: destination,
                collisionPolicy: collisionPolicy,
                isMove: true,
                reservedDestinations: &reservedDestinations
            )

        case .trash(let itemIDs):
            let sources = try await resolvedSources(itemIDs, sessionID: sessionID, used: &sourcePaths)
            var allWarnings: Set<FinderAIPlanWarning> = []
            sources.forEach { allWarnings.formUnion(warnings(for: $0)) }
            return PlannedOperation(
                actions: sources.map { .trash(source: $0) },
                preview: FinderAIMutationPreview(
                    id: UUID(),
                    kind: .trash,
                    sourceLocations: sources.map {
                        approvalLocation(for: $0.url, root: $0.root)
                    },
                    destinations: [.trash],
                    resultingNames: []
                ),
                warnings: allWarnings,
                risk: .destructive
            )
        }
    }

    func resolvedSources(
        _ itemIDs: [FinderAIItemID],
        sessionID: FinderAISessionID,
        used: inout Set<String>
    ) async throws -> [ResolvedItem] {
        guard itemIDs.isEmpty == false else { throw FinderAIWorkspaceError.emptyRequest }
        guard itemIDs.count <= Self.maximumMutationItemCount else {
            throw FinderAIWorkspaceError.limitExceeded
        }
        var sources: [ResolvedItem] = []
        for id in itemIDs {
            let source = try await resolveItem(id, in: sessionID)
            try reserveSource(source, in: sessionID, used: &used)
            sources.append(source)
        }
        return sources
    }

    func reserveSource(
        _ source: ResolvedItem,
        in sessionID: FinderAISessionID,
        used: inout Set<String>
    ) throws {
        try validateMutationSource(source, in: sessionID)
        guard used.insert(source.url.standardizedFileURL.path).inserted else {
            throw FinderAIWorkspaceError.collision
        }
    }

    func validateMutationSource(
        _ source: ResolvedItem,
        in sessionID: FinderAISessionID
    ) throws {
        guard let session = sessions[sessionID] else {
            throw FinderAIWorkspaceError.unknownSession
        }
        let sourceURL = source.url.standardizedFileURL
        let isDirectoryLike = source.summary.kind == .directory || source.summary.kind == .package
        let affectsAuthorizationRoot = session.roots.values.contains { root in
            let rootURL = root.url.standardizedFileURL
            if sourceURL == rootURL { return true }
            guard isDirectoryLike else { return false }
            if isLexicallyContained(rootURL, in: sourceURL) { return true }
            let physicalSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
            let physicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
            return isLexicallyContained(physicalRoot, in: physicalSource)
        }
        guard affectsAuthorizationRoot == false else {
            throw FinderAIWorkspaceError.rootIsProtected
        }
        guard mutationSourceIntersectsCommandlyOwnedData(
            sourceURL,
            kind: source.summary.kind
        ) == false else {
            throw FinderAIWorkspaceError.unauthorized
        }
    }

    func mutationSourceIntersectsCommandlyOwnedData(
        _ url: URL,
        kind: FinderAIItemKind
    ) -> Bool {
        if isCommandlyOwnedData(url, kind: kind) { return true }
        guard kind == .directory || kind == .package else { return false }
        let lexicalURL = url.standardizedFileURL
        let physicalURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
        return commandlyOwnedDataDirectories.contains { protectedDirectory in
            let lexicalProtected = protectedDirectory.standardizedFileURL
            let physicalProtected = lexicalProtected.resolvingSymlinksInPath().standardizedFileURL
            return isLexicallyContained(lexicalProtected, in: lexicalURL)
                || isLexicallyContained(physicalProtected, in: physicalURL)
        }
    }

    func plannedTransfer(
        sources: [ResolvedItem],
        destination: ResolvedDirectory,
        collisionPolicy: FinderAICollisionPolicy,
        isMove: Bool,
        reservedDestinations: inout Set<String>
    ) throws -> PlannedOperation {
        var actions: [ResolvedMutationAction] = []
        var outputs: [String] = []
        var destinations: [FinderAIApprovalDestination] = []
        var allWarnings: Set<FinderAIPlanWarning> = []
        for source in sources {
            if source.summary.kind == .directory,
               isLexicallyContained(destination.url, in: source.url) {
                throw FinderAIWorkspaceError.recursiveDestination
            }
            if isMove,
               source.url.deletingLastPathComponent().standardizedFileURL
                == destination.url.standardizedFileURL {
                throw FinderAIWorkspaceError.collision
            }
            let output = try reserveDestination(
                named: source.summary.displayName,
                in: destination.url,
                root: destination.root,
                collisionPolicy: collisionPolicy,
                reserved: &reservedDestinations
            )
            if output.lastPathComponent != source.summary.displayName {
                allWarnings.insert(.collisionRenamed)
            }
            allWarnings.formUnion(warnings(for: source))
            actions.append(isMove
                ? .move(source: source, destination: destination, output: output)
                : .copy(source: source, destination: destination, output: output))
            outputs.append(output.lastPathComponent)
            destinations.append(
                .authorizedLocation(approvalLocation(for: output, root: destination.root))
            )
        }
        return PlannedOperation(
            actions: actions,
            preview: FinderAIMutationPreview(
                id: UUID(),
                kind: isMove ? .move : .copy,
                sourceLocations: sources.map {
                    approvalLocation(for: $0.url, root: $0.root)
                },
                destinations: destinations,
                resultingNames: outputs
            ),
            warnings: allWarnings,
            risk: isMove ? .changesLocation : .createsItems
        )
    }

    func warnings(for item: ResolvedItem) -> Set<FinderAIPlanWarning> {
        switch item.summary.kind {
        case .directory: return [.affectsDirectoryContents]
        case .package: return [.affectsPackage]
        case .symbolicLink: return [.affectsSymbolicLink]
        case .file, .alias: return []
        }
    }

    func approvalLocation(for url: URL, root: RootRecord) -> FinderAIApprovalLocation {
        let rootPath = root.url.standardizedFileURL.path
        let relative = url.standardizedFileURL.path
            .dropFirst(rootPath.count)
            .drop(while: { $0 == "/" })
        return FinderAIApprovalLocation(
            rootID: root.id,
            authorizedRootName: root.displayName,
            authorizedRootDisplayPath: (rootPath as NSString).abbreviatingWithTildeInPath,
            rootRelativePath: String(relative)
        )
    }

    func validateNewName(_ name: String) throws {
        let forbiddenScalars = CharacterSet.controlCharacters
        guard name.isEmpty == false,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              name != ".",
              name != "..",
              name.hasPrefix(".") == false,
              name.contains("/") == false,
              name.contains(":") == false,
              name.utf8.contains(0) == false,
              name.unicodeScalars.contains(where: forbiddenScalars.contains) == false,
              name.lengthOfBytes(using: .utf8) <= 255 else {
            throw FinderAIWorkspaceError.invalidName
        }
    }

    func duplicateName(for source: URL) -> String {
        let extensionName = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent + " copy"
        if extensionName.isEmpty { return stem }
        return "\(stem).\(extensionName)"
    }

    func reserveExactDestination(
        _ destination: URL,
        in root: RootRecord,
        reserved: inout Set<String>
    ) throws {
        guard isLexicallyContained(destination, in: root.url),
              isPhysicallyContained(
                  destination.deletingLastPathComponent(),
                  kind: .directory,
                  in: root.url
              ),
              isCommandlyOwnedData(destination, kind: nil) == false else {
            throw FinderAIWorkspaceError.unauthorized
        }
        guard fileManager.fileExists(atPath: destination.path) == false,
              isSymbolicLink(at: destination) == false,
              reserved.insert(destination.path).inserted else {
            throw FinderAIWorkspaceError.collision
        }
    }

    func reserveDestination(
        named name: String,
        in directory: URL,
        root: RootRecord,
        collisionPolicy: FinderAICollisionPolicy,
        reserved: inout Set<String>
    ) throws -> URL {
        try validateNewName(name)
        var candidate = directory.appendingPathComponent(name).standardizedFileURL
        if destinationIsAvailable(candidate, reserved: reserved) {
            try reserveExactDestination(candidate, in: root, reserved: &reserved)
            return candidate
        }
        guard collisionPolicy == .keepBoth else { throw FinderAIWorkspaceError.collision }

        let original = URL(fileURLWithPath: name)
        let extensionName = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        for index in 2 ... (Self.maximumKeepBothCandidateAttempts + 1) {
            try Task.checkCancellation()
            let indexedName = extensionName.isEmpty
                ? "\(stem) \(index)"
                : "\(stem) \(index).\(extensionName)"
            try validateNewName(indexedName)
            candidate = directory.appendingPathComponent(indexedName).standardizedFileURL
            if destinationIsAvailable(candidate, reserved: reserved) {
                try reserveExactDestination(candidate, in: root, reserved: &reserved)
                return candidate
            }
        }
        throw FinderAIWorkspaceError.limitExceeded
    }

    func destinationIsAvailable(_ url: URL, reserved: Set<String>) -> Bool {
        fileManager.fileExists(atPath: url.path) == false
            && isSymbolicLink(at: url) == false
            && reserved.contains(url.path) == false
    }
}

private extension FinderAIWorkspaceService {
    func preflight(
        _ actions: [ResolvedMutationAction],
        in sessionID: FinderAISessionID
    ) async throws {
        for action in actions {
            try Task.checkCancellation()
            if let storedSource = action.source {
                let current = try await resolveStoredItem(storedSource, in: sessionID)
                guard current.identity == storedSource.identity else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
                try validateMutationSource(current, in: sessionID)
            }
            if let storedDirectory = action.destinationDirectory {
                let currentRoot = try await currentRoot(storedDirectory.root.id, in: sessionID)
                guard currentRoot.url.standardizedFileURL == storedDirectory.root.url.standardizedFileURL,
                      try identity(at: storedDirectory.url) == storedDirectory.identity else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
            }
            if let destination = action.destinationURL,
               let destinationRootID = action.destinationRootID {
                let destinationRoot = try await currentRoot(destinationRootID, in: sessionID)
                let parent = destination.deletingLastPathComponent().standardizedFileURL
                let parentKind = try? metadataValues(at: parent).kind
                guard isCommandlyOwnedData(destination, kind: nil) == false,
                      isLexicallyContained(parent, in: destinationRoot.url),
                      isPhysicallyContained(parent, kind: .directory, in: destinationRoot.url),
                      parentKind == .directory,
                      isSymbolicLink(at: parent) == false,
                      fileManager.fileExists(atPath: destination.path) == false,
                      isSymbolicLink(at: destination) == false else {
                    throw FinderAIWorkspaceError.itemChangedSincePreview
                }
            }
        }
    }

    func execute(_ action: ResolvedMutationAction) throws -> String? {
        switch action {
        case .createFolder(_, let destination, _, _):
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false,
                attributes: nil
            )
            return destination.lastPathComponent

        case .rename(let source, let destination, _):
            try fileManager.moveItem(at: source.url, to: destination)
            return destination.lastPathComponent

        case .duplicate(let source, let destination):
            try fileManager.copyItem(at: source.url, to: destination)
            return destination.lastPathComponent

        case .copy(let source, _, let output):
            try fileManager.copyItem(at: source.url, to: output)
            return output.lastPathComponent

        case .move(let source, _, let output):
            try fileManager.moveItem(at: source.url, to: output)
            return output.lastPathComponent

        case .trash(let source):
            try trashMover.moveToTrash(source.url)
            return nil
        }
    }

    func invalidateSourceHandle(for action: ResolvedMutationAction, in sessionID: FinderAISessionID) {
        let shouldInvalidate: Bool
        switch action {
        case .rename, .move, .trash:
            shouldInvalidate = true
        case .createFolder, .duplicate, .copy:
            shouldInvalidate = false
        }
        guard shouldInvalidate, let sourceID = action.source?.recordID,
              var session = sessions[sessionID] else { return }
        session.items[sourceID] = nil
        sessions[sessionID] = session
    }

    func mapOperationError(_ error: Error) -> FinderAIWorkspaceError {
        if let error = error as? FinderAIWorkspaceError { return error }
        if error is CancellationError { return .operationFailed }
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else { return .operationFailed }
        switch nsError.code {
        case CocoaError.Code.fileNoSuchFile.rawValue,
             CocoaError.Code.fileReadNoSuchFile.rawValue:
            return .itemNotFound
        case CocoaError.Code.fileWriteFileExists.rawValue:
            return .collision
        case CocoaError.Code.fileReadNoPermission.rawValue,
             CocoaError.Code.fileWriteNoPermission.rawValue:
            return .unauthorized
        default:
            return .operationFailed
        }
    }
}
