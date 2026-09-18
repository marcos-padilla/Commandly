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
    private let changeMonitor: any FileIndexChangeMonitoring
    private let eventProcessor = FileIndexEventProcessor()
    private var activeScopes: [URL] = []
    private var prepareTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexWorker: Task<Void, any Error>?
    private var isSessionActive = false
    private var sessionGeneration: UInt64 = 0

    init(
        folderAccessStore: any FolderAccessStoring,
        databaseURL: URL? = nil,
        directAuthorizedScopes: [URL] = [],
        changeMonitor: any FileIndexChangeMonitoring = FileIndexChangeMonitor()
    ) {
        self.folderAccessStore = folderAccessStore
        self.directAuthorizedScopes = directAuthorizedScopes.map(\.standardizedFileURL)
        self.changeMonitor = changeMonitor
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
        if isSessionActive == false { beginFileSearchSession() }
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
        let scopesChanged = resolvedPaths != activePaths
        if isSessionActive, scopesChanged == false {
            return
        }

        sessionGeneration &+= 1
        let generation = sessionGeneration
        isSessionActive = true

        if scopesChanged {
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
            let database = database
            prepareTask?.cancel()
            prepareTask = Task { [weak self] in
                try? await database.replaceAuthorizedScopes(with: [])
                guard let self, generation == sessionGeneration else { return }
                prepareTask = nil
            }
            return
        }

        prepareTask?.cancel()
        let scopes = activeScopes
        let database = database
        let statusHub = statusHub
        prepareTask = Task { [weak self] in
            do {
                try await database.replaceAuthorizedScopes(with: scopes.map(\.path))
                try Task.checkCancellation()
                let count = try await database.indexedItemCount()
                let lastScan = try await database.lastFullScanDate()
                let isFresh = lastScan.map { Date.now.timeIntervalSince($0) < 6 * 60 * 60 } ?? false
                if count > 0 {
                    await statusHub.yield(.ready(indexedItemCount: count))
                }
                guard let self,
                      isSessionActive,
                      generation == sessionGeneration,
                      Task.isCancelled == false else {
                    return
                }
                if count == 0 || isFresh == false {
                    startFullScan(scopes: scopes, generation: generation)
                } else {
                    startMonitoring(scopes: scopes, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      isSessionActive,
                      generation == sessionGeneration else {
                    return
                }
                await statusHub.yield(.failed)
            }
            guard let self, generation == sessionGeneration else { return }
            prepareTask = nil
        }
    }

    /// Stops all indexing work once no file-search surface is active.
    ///
    /// Existing rows remain in SQLite, so the next session can search immediately while a stale or
    /// incomplete index resumes at utility priority. Folder access is released only after the
    /// detached scanner and serialized event worker have observed cancellation.
    func endFileSearchSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        sessionGeneration &+= 1
        let generation = sessionGeneration
        changeMonitor.stop()
        prepareTask?.cancel()
        prepareTask = nil
        indexTask?.cancel()
        indexTask = nil
        let worker = indexWorker
        worker?.cancel()
        indexWorker = nil
        let scopesToRelease = directAuthorizedScopes.isEmpty ? activeScopes : []
        activeScopes = []

        let eventProcessor = eventProcessor
        let statusHub = statusHub
        Task { @MainActor [weak self] in
            await eventProcessor.cancel(upTo: generation)
            _ = try? await worker?.value
            scopesToRelease.forEach { $0.stopAccessingSecurityScopedResource() }
            guard let self,
                  isSessionActive == false,
                  generation == sessionGeneration else {
                return
            }
            await statusHub.yield(.idle)
        }
    }

    private func startFullScan(scopes: [URL], generation: UInt64) {
        guard isSessionActive,
              generation == sessionGeneration,
              indexTask == nil else {
            return
        }
        let database = database
        let statusHub = statusHub
        let worker = Task.detached(priority: .utility) {
            try await FileIndexScanner.scan(scopes: scopes, database: database, statusHub: statusHub)
        }
        indexWorker = worker
        indexTask = Task { [weak self] in
            do {
                try await worker.value
                guard let self,
                      isSessionActive,
                      generation == sessionGeneration,
                      Task.isCancelled == false else {
                    return
                }
                startMonitoring(scopes: scopes, generation: generation)
            } catch is CancellationError {
                worker.cancel()
            } catch {
                guard let self,
                      isSessionActive,
                      generation == sessionGeneration else {
                    return
                }
                await statusHub.yield(.failed)
            }
            guard let self, generation == sessionGeneration else { return }
            indexTask = nil
            indexWorker = nil
        }
    }

    private func startMonitoring(scopes: [URL], generation: UInt64) {
        guard isSessionActive, generation == sessionGeneration else { return }
        let database = database
        let statusHub = statusHub
        let eventProcessor = eventProcessor
        changeMonitor.start(paths: scopes.map(\.path)) { paths in
            Task.detached(priority: .utility) {
                await eventProcessor.enqueue(
                    paths: paths,
                    scopes: scopes,
                    database: database,
                    statusHub: statusHub,
                    generation: generation
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
            startFullScan(scopes: activeScopes, generation: sessionGeneration)
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

/// Coalesces event bursts behind one cancellable worker so callbacks cannot accumulate unbounded
/// directory scans after the file-search surface has closed.
actor FileIndexEventProcessor {
    private var currentGeneration: UInt64 = 0
    private var pendingPaths: Set<String> = []
    private var worker: Task<Void, Never>?

    func enqueue(
        paths: [String],
        scopes: [URL],
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub,
        generation: UInt64
    ) {
        guard generation >= currentGeneration else { return }
        if generation > currentGeneration {
            worker?.cancel()
            worker = nil
            pendingPaths.removeAll()
            currentGeneration = generation
        }
        pendingPaths.formUnion(paths)
        guard worker == nil else { return }

        worker = Task { [weak self] in
            await self?.drain(
                scopes: scopes,
                database: database,
                statusHub: statusHub,
                generation: generation
            )
        }
    }

    func cancel(upTo generation: UInt64) async {
        guard generation >= currentGeneration else { return }
        currentGeneration = generation
        pendingPaths.removeAll()
        let activeWorker = worker
        worker = nil
        activeWorker?.cancel()
        await activeWorker?.value
    }

    private func drain(
        scopes: [URL],
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub,
        generation: UInt64
    ) async {
        defer {
            if generation == currentGeneration {
                worker = nil
            }
        }

        while generation == currentGeneration, Task.isCancelled == false {
            let paths = Self.compact(Array(pendingPaths))
            pendingPaths.removeAll()
            guard paths.isEmpty == false else { return }

            do {
                if paths.count > 200 {
                    try await FileIndexScanner.scan(
                        scopes: scopes,
                        database: database,
                        statusHub: statusHub
                    )
                } else {
                    for path in paths {
                        try Task.checkCancellation()
                        guard generation == currentGeneration else { return }
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

    /// If a parent and one of its descendants arrive in the same burst, scanning the parent already
    /// covers the child. Removing descendants prevents repeated subtree work in directory-heavy
    /// FSEvents batches.
    nonisolated static func compact(_ paths: [String]) -> [String] {
        let ordered = Set(paths).sorted {
            let left = URL(fileURLWithPath: $0).standardizedFileURL.path
            let right = URL(fileURLWithPath: $1).standardizedFileURL.path
            if left.count != right.count { return left.count < right.count }
            return left < right
        }
        var compacted: [String] = []
        for rawPath in ordered {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            let isCovered = compacted.contains { parent in
                path == parent || path.hasPrefix("\(parent)/")
            }
            if isCovered == false {
                compacted.append(path)
            }
        }
        return compacted
    }
}
