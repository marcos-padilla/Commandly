import Foundation
import SearchKit
import UniformTypeIdentifiers

/// Queries the system Spotlight index within user-authorized security-scoped folders.
///
/// `NSMetadataQuery` performs its gathering asynchronously. Keeping the adapter on the
/// main actor gives the query a stable run loop without performing file I/O there.
@MainActor
final class SpotlightFileSearchService: FileSearching, FileSearchSessionManaging {
    private let folderAccessStore: any FolderAccessStoring
    private var activeScopes: [URL] = []

    init(folderAccessStore: any FolderAccessStoring) {
        self.folderAccessStore = folderAccessStore
    }

    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        try Task.checkCancellation()
        if request.query.isEmpty == false,
           request.includesFileNames == false,
           request.includesFileContents == false {
            return []
        }
        if activeScopes.isEmpty {
            beginFileSearchSession()
        }
        let scopes = activeScopes
        guard scopes.isEmpty == false else {
            throw FileSearchError.noAuthorizedScopes
        }

        let query = NSMetadataQuery()
        query.searchScopes = Self.metadataSearchScopes(for: scopes)
        query.predicate = Self.predicate(for: request)
        query.sortDescriptors = Self.sortDescriptors(for: request)
        query.notificationBatchingInterval = 0.05

        let requestedLimit = request.query.limit ?? 100
        guard requestedLimit > 0 else { return [] }
        let waiter = MetadataQueryWaiter(query: query) {
            Self.hasUsableResult(in: query, scopes: scopes)
        }
        try await waiter.gather(untilResultCount: Self.minimumResultCount(for: request))
        defer { query.stop() }
        try Task.checkCancellation()
        query.disableUpdates()
        defer { query.enableUpdates() }
        return Self.items(from: query, request: request, scopes: scopes)
    }

    func beginFileSearchSession() {
        guard activeScopes.isEmpty else { return }
        activeScopes = resolveAuthorizedScopes().filter { scope in
            scope.startAccessingSecurityScopedResource()
        }
    }

    func endFileSearchSession() {
        activeScopes.forEach { $0.stopAccessingSecurityScopedResource() }
        activeScopes = []
    }

    private func resolveAuthorizedScopes() -> [URL] {
        folderAccessStore.bookmarkData.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isStale == false else {
                return nil
            }
            return url.standardizedFileURL
        }
    }

    static func metadataSearchScopes(for authorizedScopes: [URL]) -> [Any] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var includesUserHome = false
        var searchScopes: [Any] = []
        for scope in authorizedScopes {
            let path = scope.standardizedFileURL.path
            if path == homePath || path.hasPrefix("\(homePath)/") {
                includesUserHome = true
            } else {
                searchScopes.append(scope)
            }
        }
        if includesUserHome {
            searchScopes.insert(NSMetadataQueryUserHomeScope, at: 0)
        }
        return searchScopes
    }

    static func predicate(for request: FileSearchRequest, now: Date = .now) -> NSPredicate {
        var predicates: [NSPredicate] = []

        if request.query.isEmpty {
            // Spotlight often leaves `kMDItemLastUsedDate` unset. Include recently
            // modified items so the initial screen remains useful on those volumes.
            let recentCutoff = now.addingTimeInterval(-90 * 24 * 60 * 60)
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(
                        format: "%K >= %@",
                        NSMetadataItemLastUsedDateKey,
                        recentCutoff as NSDate
                    ),
                    NSPredicate(
                        format: "%K >= %@",
                        NSMetadataItemFSContentChangeDateKey,
                        recentCutoff as NSDate
                    )
                ])
            )
        } else {
            let tokenPredicates = queryTokens(request.query.text).map { token in
                let pattern = "*\(escapedLikeValue(token))*"
                var fieldPredicates: [NSPredicate] = []
                if request.includesFileNames {
                    fieldPredicates.append(
                        NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, pattern)
                    )
                    fieldPredicates.append(
                        NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemDisplayNameKey, pattern)
                    )
                }
                if request.includesFileContents {
                    fieldPredicates.append(
                        NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemTextContentKey, pattern)
                    )
                }
                if fieldPredicates.count == 1, let fieldPredicate = fieldPredicates.first {
                    return fieldPredicate
                }
                return NSCompoundPredicate(orPredicateWithSubpredicates: fieldPredicates)
            }
            if tokenPredicates.count == 1, let tokenPredicate = tokenPredicates.first {
                predicates.append(tokenPredicate)
            } else {
                predicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: tokenPredicates))
            }
        }

        let identifiers = contentTypeTreeIdentifiers(for: request.category)
        if identifiers.isEmpty == false {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: identifiers.map {
                        NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, $0)
                    }
                )
            )
        }
        if predicates.count == 1, let predicate = predicates.first {
            return predicate
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func minimumResultCount(for request: FileSearchRequest) -> Int {
        let requestedLimit = max(0, request.query.limit ?? 100)
        return min(requestedLimit, 1)
    }

    private static func queryTokens(_ value: String) -> [String] {
        Array(value.split(whereSeparator: \.isWhitespace).prefix(8)).map(String.init)
    }

    private static func escapedLikeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
    }

    private static func contentTypeTreeIdentifiers(for category: FileSearchCategory) -> [String] {
        switch category {
        case .all: return []
        case .folders: return [UTType.folder.identifier]
        case .documents: return ["public.text", "com.adobe.pdf", "public.presentation", "public.spreadsheet"]
        case .images: return [UTType.image.identifier]
        case .audio: return [UTType.audio.identifier]
        case .video: return [UTType.movie.identifier]
        case .archives: return ["public.archive"]
        case .sourceCode: return ["public.source-code"]
        }
    }

    private static func sortDescriptors(for request: FileSearchRequest) -> [NSSortDescriptor] {
        if request.query.isEmpty {
            return [
                NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false),
                NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
            ]
        }
        return [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
    }

    private static func items(
        from query: NSMetadataQuery,
        request: FileSearchRequest,
        scopes: [URL]
    ) -> [FileSearchItem] {
        let limit = request.query.limit ?? 100
        var items: [FileSearchItem] = []
        var seenPaths = Set<String>()

        for index in 0..<query.resultCount where items.count < limit {
            guard let metadata = query.result(at: index) as? NSMetadataItem,
                  let path = metadata.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard isWithinAuthorizedScope(url, scopes: scopes),
                  isHiddenPath(url) == false,
                  seenPaths.insert(url.path).inserted else {
                continue
            }
            let contentTypeIdentifier = metadata.value(
                forAttribute: NSMetadataItemContentTypeKey
            ) as? String
            let contentType = contentTypeIdentifier.flatMap(UTType.init)
            let isFolder = contentType?.conforms(to: .folder) == true
            let name = (metadata.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? url.lastPathComponent
            let filenameMatched = request.query.isEmpty
                || (request.includesFileNames
                    && (request.includesFileContents == false
                        || filenameMatches(name, query: request.query.text)))

            items.append(
                FileSearchItem(
                    url: url,
                    name: name,
                    parentPath: url.deletingLastPathComponent().path,
                    kind: isFolder ? .folder : .file,
                    contentTypeIdentifier: contentTypeIdentifier,
                    contentTypeDescription: isFolder
                        ? "Folder"
                        : (contentType?.localizedDescription ?? "File"),
                    byteCount: (metadata.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value,
                    createdAt: metadata.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                    modifiedAt: metadata.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                    lastUsedAt: metadata.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                    matchKind: request.query.isEmpty ? .recent : (filenameMatched ? .filename : .contents)
                )
            )
        }
        return items.sorted { lhs, rhs in
            let lhsRank = matchRank(for: lhs, query: request.query.text)
            let rhsRank = matchRank(for: rhs, query: request.query.text)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            if lhs.modifiedAt != rhs.modifiedAt {
                return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func matchRank(for item: FileSearchItem, query: String) -> Int {
        guard query.isEmpty == false else { return 0 }
        guard item.matchKind == .filename else { return 0 }
        let name = comparableSearchText(item.name)
        let needle = comparableSearchText(query)
        if name == needle { return 4 }
        if name.hasPrefix(needle) { return 3 }
        let queryParts = needle.split(separator: " ")
        let nameParts = name.split(separator: " ")
        if queryParts.allSatisfy({ queryPart in
            nameParts.contains { $0.hasPrefix(queryPart) }
        }) {
            return 2
        }
        return filenameMatches(name, query: needle) ? 1 : 0
    }

    private static func filenameMatches(_ name: String, query: String) -> Bool {
        let comparableName = comparableSearchText(name)
        return queryTokens(comparableSearchText(query)).allSatisfy(comparableName.contains)
    }

    private static func comparableSearchText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let separated = folded.map { character in
            character.isWhitespace || character == "_" || character == "-" ? " " : character
        }
        return String(separated).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isWithinAuthorizedScope(_ url: URL, scopes: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return scopes.contains { scope in
            let scopePath = scope.standardizedFileURL.path
            return path == scopePath || path.hasPrefix(scopePath.hasSuffix("/") ? scopePath : "\(scopePath)/")
        }
    }

    private static func hasUsableResult(in query: NSMetadataQuery, scopes: [URL]) -> Bool {
        for index in 0..<query.resultCount {
            guard let metadata = query.result(at: index) as? NSMetadataItem,
                  let path = metadata.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if isWithinAuthorizedScope(url, scopes: scopes), isHiddenPath(url) == false {
                return true
            }
        }
        return false
    }

    static func isHiddenPath(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.dropFirst().contains { component in
            component.hasPrefix(".") && component != "." && component != ".."
        }
    }
}

/// Bridges selector-based `NSMetadataQuery` completion into structured concurrency.
///
/// `@unchecked Sendable` is restricted to this private bridge: every property and method
/// is main-actor isolated, and the only cross-executor use is the cancellation callback,
/// which immediately hops back to the main actor before touching the query or continuation.
@MainActor
private final class MetadataQueryWaiter: NSObject, @unchecked Sendable {
    private let query: NSMetadataQuery
    private let hasUsableResult: @MainActor @Sendable () -> Bool
    private var continuation: CheckedContinuation<Void, any Error>?
    private var targetResultCount: Int?

    init(
        query: NSMetadataQuery,
        hasUsableResult: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.query = query
        self.hasUsableResult = hasUsableResult
    }

    func gather(untilResultCount: Int?) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard Task.isCancelled == false else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.targetResultCount = untilResultCount
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(didFinishGathering),
                    name: .NSMetadataQueryDidFinishGathering,
                    object: query
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(didProgressGathering),
                    name: .NSMetadataQueryGatheringProgress,
                    object: query
                )
                guard query.start() else {
                    finish(throwing: FileSearchError.indexUnavailable)
                    return
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        })
    }

    @objc private func didFinishGathering() {
        finish()
    }

    @objc private func didProgressGathering() {
        guard let targetResultCount,
              query.resultCount >= targetResultCount,
              hasUsableResult() else {
            return
        }
        finish()
    }

    private func cancel() {
        query.stop()
        finish(throwing: CancellationError())
    }

    private func finish(throwing error: (any Error)? = nil) {
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryGatheringProgress,
            object: query
        )
        guard let continuation else { return }
        self.continuation = nil
        targetResultCount = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
