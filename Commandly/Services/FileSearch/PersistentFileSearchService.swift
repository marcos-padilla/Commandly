import Foundation
import SearchKit

/// Persistent direct-filesystem search with SQLite FTS, bounded content enrichment,
/// and FSEvents-driven refreshes. Spotlight is optional enrichment, never the name-search path.
@MainActor
final class PersistentFileSearchService: FileSearching, FileSearchSessionManaging, FileSearchIndexStatusProviding {
    private let folderAccessStore: any FolderAccessStoring
    private let directAuthorizedScopes: [URL]
    private let database: FileIndexDatabase
    private let statusHub = FileIndexStatusHub()
    private let changeMonitor = FileIndexChangeMonitor()
    private let eventProcessor = FileIndexEventProcessor()
    private var activeScopes: [URL] = []
    private var prepareTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexWorker: Task<Void, any Error>?

    init(
        folderAccessStore: any FolderAccessStoring,
        databaseURL: URL? = nil,
        directAuthorizedScopes: [URL] = []
    ) {
        self.folderAccessStore = folderAccessStore
        self.directAuthorizedScopes = directAuthorizedScopes.map(\.standardizedFileURL)
        let resolvedURL: URL
        if let databaseURL {
            resolvedURL = databaseURL
        } else if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            resolvedURL = applicationSupport
                .appendingPathComponent("Commandly", isDirectory: true)
                .appendingPathComponent("FileIndex.sqlite")
        } else {
            resolvedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Commandly-FileIndex.sqlite")
        }
        self.database = FileIndexDatabase(databaseURL: resolvedURL)
    }

    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        try Task.checkCancellation()
        if activeScopes.isEmpty { beginFileSearchSession() }
        guard activeScopes.isEmpty == false else { throw FileSearchError.noAuthorizedScopes }
        if let prepareTask { await prepareTask.value }
        try Task.checkCancellation()
        do {
            let items = try await database.search(request)
            try Task.checkCancellation()
            return Self.rank(items, query: request.query.text)
        } catch FileSearchError.indexCorrupt {
            await recoverCorruptIndex()
            return []
        }
    }

    func indexStatusUpdates() async -> AsyncStream<FileSearchIndexStatus> {
        await statusHub.stream()
    }

    func beginFileSearchSession() {
        let resolved = resolveAuthorizedScopes()
        let resolvedPaths = Set(resolved.map(\.path))
        let activePaths = Set(activeScopes.map(\.path))
        if resolvedPaths != activePaths {
            if directAuthorizedScopes.isEmpty {
                activeScopes.forEach { $0.stopAccessingSecurityScopedResource() }
                activeScopes = resolved.filter { $0.startAccessingSecurityScopedResource() }
            } else {
                activeScopes = resolved
            }
            changeMonitor.stop()
            indexTask?.cancel()
            indexWorker?.cancel()
            indexTask = nil
            indexWorker = nil
        }
        guard activeScopes.isEmpty == false else {
            changeMonitor.stop()
            if prepareTask == nil {
                let database = database
                prepareTask = Task { [weak self] in
                    try? await database.replaceAuthorizedScopes(with: [])
                    self?.prepareTask = nil
                }
            }
            return
        }
        guard prepareTask == nil else { return }
        let scopes = activeScopes
        let database = database
        let statusHub = statusHub
        prepareTask = Task { [weak self] in
            do {
                try await database.replaceAuthorizedScopes(with: scopes.map(\.path))
                let count = try await database.indexedItemCount()
                let lastScan = try await database.lastFullScanDate()
                let isFresh = lastScan.map { Date.now.timeIntervalSince($0) < 6 * 60 * 60 } ?? false
                if count > 0 {
                    await statusHub.yield(.ready(indexedItemCount: count))
                }
                if count == 0 || isFresh == false {
                    self?.startFullScan(scopes: scopes)
                } else {
                    self?.startMonitoring(scopes: scopes)
                }
            } catch {
                await statusHub.yield(.failed)
            }
            self?.prepareTask = nil
        }
    }

    /// Indexing and monitoring continue after the window closes so subsequent searches are instant.
    func endFileSearchSession() {}

    private func startFullScan(scopes: [URL]) {
        guard indexTask == nil else { return }
        let database = database
        let statusHub = statusHub
        let worker = Task.detached(priority: .utility) {
            try await FileIndexScanner.scan(scopes: scopes, database: database, statusHub: statusHub)
        }
        indexWorker = worker
        indexTask = Task { [weak self] in
            do {
                try await worker.value
                self?.startMonitoring(scopes: scopes)
            } catch is CancellationError {
                worker.cancel()
            } catch {
                await statusHub.yield(.failed)
            }
            self?.indexTask = nil
            self?.indexWorker = nil
        }
    }

    private func startMonitoring(scopes: [URL]) {
        let database = database
        let statusHub = statusHub
        let eventProcessor = eventProcessor
        changeMonitor.start(paths: scopes.map(\.path)) { paths in
            Task.detached(priority: .utility) {
                await eventProcessor.process(
                    paths: paths,
                    scopes: scopes,
                    database: database,
                    statusHub: statusHub
                )
            }
        }
    }

    private func recoverCorruptIndex() async {
        indexTask?.cancel()
        indexWorker?.cancel()
        indexTask = nil
        indexWorker = nil
        do {
            try await database.reset()
            await statusHub.yield(.scanning(indexedItemCount: 0))
            startFullScan(scopes: activeScopes)
        } catch {
            await statusHub.yield(.failed)
        }
    }

    private func resolveAuthorizedScopes() -> [URL] {
        if directAuthorizedScopes.isEmpty == false { return directAuthorizedScopes }
        return folderAccessStore.bookmarkData.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isStale == false else { return nil }
            return url.standardizedFileURL
        }
    }

    private static func rank(_ items: [FileSearchItem], query: String) -> [FileSearchItem] {
        let normalizedQuery = FileIndexNormalizer.normalize(query)
        guard normalizedQuery.isEmpty == false else { return items }
        return items.enumerated().sorted { lhs, rhs in
            let lhsScore = score(lhs.element, query: normalizedQuery)
            let rhsScore = score(rhs.element, query: normalizedQuery)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            let lhsDate = lhs.element.lastUsedAt ?? lhs.element.modifiedAt ?? .distantPast
            let rhsDate = rhs.element.lastUsedAt ?? rhs.element.modifiedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func score(_ item: FileSearchItem, query: String) -> Int {
        let name = FileIndexNormalizer.normalize(item.name)
        let base: Int
        switch item.matchKind {
        case .filename: base = 400
        case .tag: base = 300
        case .metadata: base = 200
        case .contents: base = 100
        case .recent: base = 0
        }
        if name == query { return base + 90 }
        if name.hasPrefix(query) { return base + 70 }
        let queryTokens = FileIndexNormalizer.tokens(query)
        let nameTokens = FileIndexNormalizer.tokens(name)
        if queryTokens.allSatisfy({ queryToken in nameTokens.contains { $0.hasPrefix(queryToken) } }) {
            return base + 50
        }
        return base
    }
}

/// Serializes event batches so bursts cannot start overlapping directory scans.
private actor FileIndexEventProcessor {
    func process(
        paths: [String],
        scopes: [URL],
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub
    ) async {
        do {
            if paths.count > 200 {
                try await FileIndexScanner.scan(
                    scopes: scopes,
                    database: database,
                    statusHub: statusHub
                )
            } else {
                for path in Set(paths).sorted() {
                    try Task.checkCancellation()
                    guard database.isStoragePath(path) == false else { continue }
                    try await FileIndexScanner.scanChangedPath(
                        path,
                        scopes: scopes,
                        database: database,
                        statusHub: statusHub
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await statusHub.yield(.failed)
        }
    }
}
