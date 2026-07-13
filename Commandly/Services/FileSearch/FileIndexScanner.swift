import Foundation
import SearchKit
import UniformTypeIdentifiers

actor FileIndexStatusHub {
    private var current: FileSearchIndexStatus = .idle
    private var continuations: [UUID: AsyncStream<FileSearchIndexStatus>.Continuation] = [:]

    func stream() -> AsyncStream<FileSearchIndexStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func yield(_ status: FileSearchIndexStatus) {
        current = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

enum FileIndexScanner {
    nonisolated static let batchSize = 400
    nonisolated static let enrichmentBatchSize = 12
    nonisolated static let maximumConcurrentEnrichments = 3
    nonisolated static let ignoredDirectoryNames: Set<String> = [
        "node_modules", "DerivedData", ".build", ".Trash", ".Spotlight-V100", ".fseventsd"
    ]

    nonisolated static func scan(
        scopes: [URL],
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub
    ) async throws {
        let roots = removeNestedScopes(scopes)
        try await database.replaceAuthorizedScopes(with: roots.map(\.path))
        var indexedCount = 0
        for root in roots {
            try Task.checkCancellation()
            let generation = Int64(Date.now.timeIntervalSince1970 * 1_000)
            let manager = FileManager()
            let keys: Set<URLResourceKey> = [
                .nameKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isHiddenKey,
                .isPackageKey,
                .contentTypeKey,
                .localizedTypeDescriptionKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
                .tagNamesKey
            ]
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            var batch: [FileIndexRecord] = []
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if database.isStoragePath(url.path) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                let name = values.name ?? url.lastPathComponent
                if values.isDirectory == true,
                   ignoredDirectoryNames.contains(name) || values.isPackage == true {
                    enumerator.skipDescendants()
                }
                if values.isHidden == true || shouldIgnore(url: url, values: values) { continue }
                guard values.isDirectory == true || values.isRegularFile == true else { continue }

                batch.append(record(
                    url: url,
                    root: root,
                    values: values,
                    generation: generation
                ))
                if batch.count >= batchSize {
                    try await database.upsert(batch)
                    indexedCount += batch.count
                    batch.removeAll(keepingCapacity: true)
                    await statusHub.yield(.scanning(indexedItemCount: indexedCount))
                }
            }
            if batch.isEmpty == false {
                try await database.upsert(batch)
                indexedCount += batch.count
                await statusHub.yield(.scanning(indexedItemCount: indexedCount))
            }
            try await database.removeStaleEntries(rootPath: root.path, generation: generation)
        }
        try await database.markFullScanCompleted(at: .now)
        let count = try await database.indexedItemCount()
        await statusHub.yield(.enriching(indexedItemCount: count, enrichedItemCount: 0))
        try await enrich(database: database, statusHub: statusHub, indexedItemCount: count)
        await statusHub.yield(.ready(indexedItemCount: count))
    }

    nonisolated static func scanChangedPath(
        _ path: String,
        scopes: [URL],
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub
    ) async throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard database.isStoragePath(url.path) == false else { return }
        guard let root = mostSpecificRoot(containing: url, scopes: scopes) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            try await database.remove(path: url.path, includingDescendants: true)
            return
        }
        if isDirectory.boolValue {
            try await indexSubtree(url, root: root, database: database)
            let count = try await database.indexedItemCount()
            await statusHub.yield(.ready(indexedItemCount: count))
            return
        }
        let keys: Set<URLResourceKey> = [
            .nameKey, .isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isPackageKey,
            .contentTypeKey, .localizedTypeDescriptionKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .contentAccessDateKey, .tagNamesKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isHidden != true,
              values.isRegularFile == true else {
            try await database.remove(path: url.path, includingDescendants: false)
            return
        }
        let generation = Int64(Date.now.timeIntervalSince1970 * 1_000)
        try await database.upsert([
            record(url: url, root: root, values: values, generation: generation)
        ])
        if let candidate = try await database.contentCandidate(atPath: url.path) {
            let extraction = await FileContentExtractor.extract(candidate)
            try await database.updateContent([
                FileContentUpdate(
                    path: candidate.path,
                    text: extraction.text,
                    metadata: extraction.metadata,
                    tags: extraction.tags
                )
            ])
        }
        let count = try await database.indexedItemCount()
        await statusHub.yield(.ready(indexedItemCount: count))
    }

    private nonisolated static func indexSubtree(
        _ directory: URL,
        root: URL,
        database: FileIndexDatabase
    ) async throws {
        let keys: Set<URLResourceKey> = [
            .nameKey, .isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isPackageKey,
            .contentTypeKey, .localizedTypeDescriptionKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .contentAccessDateKey, .tagNamesKey
        ]
        let generation = Int64(Date.now.timeIntervalSince1970 * 1_000)
        var batch: [FileIndexRecord] = []
        if let values = try? directory.resourceValues(forKeys: keys), values.isHidden != true {
            batch.append(record(url: directory, root: root, values: values, generation: generation))
        }
        guard let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            try await database.upsert(batch)
            return
        }
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if database.isStoragePath(url.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let name = values.name ?? url.lastPathComponent
            if values.isDirectory == true,
               ignoredDirectoryNames.contains(name) || values.isPackage == true {
                enumerator.skipDescendants()
            }
            if values.isHidden == true || shouldIgnore(url: url, values: values) { continue }
            guard values.isDirectory == true || values.isRegularFile == true else { continue }
            batch.append(record(url: url, root: root, values: values, generation: generation))
            if batch.count >= batchSize {
                try await database.upsert(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        try await database.upsert(batch)
    }

    private nonisolated static func enrich(
        database: FileIndexDatabase,
        statusHub: FileIndexStatusHub,
        indexedItemCount: Int
    ) async throws {
        var enrichedCount = 0
        while true {
            try Task.checkCancellation()
            let candidates = try await database.contentCandidates(limit: enrichmentBatchSize)
            guard candidates.isEmpty == false else { return }
            let updates = await withTaskGroup(of: FileContentUpdate.self) { group in
                var iterator = candidates.makeIterator()
                for _ in 0..<maximumConcurrentEnrichments {
                    guard let candidate = iterator.next() else { break }
                    group.addTask(priority: .utility) {
                        let extraction = await FileContentExtractor.extract(candidate)
                        return FileContentUpdate(
                            path: candidate.path,
                            text: extraction.text,
                            metadata: extraction.metadata,
                            tags: extraction.tags
                        )
                    }
                }
                var values: [FileContentUpdate] = []
                while let update = await group.next() {
                    values.append(update)
                    if let candidate = iterator.next() {
                        group.addTask(priority: .utility) {
                            let extraction = await FileContentExtractor.extract(candidate)
                            return FileContentUpdate(
                                path: candidate.path,
                                text: extraction.text,
                                metadata: extraction.metadata,
                                tags: extraction.tags
                            )
                        }
                    }
                }
                return values
            }
            try await database.updateContent(updates)
            enrichedCount += updates.count
            await statusHub.yield(.enriching(
                indexedItemCount: indexedItemCount,
                enrichedItemCount: enrichedCount
            ))
        }
    }

    private nonisolated static func record(
        url: URL,
        root: URL,
        values: URLResourceValues,
        generation: Int64
    ) -> FileIndexRecord {
        let isFolder = values.isDirectory == true
        let type = values.contentType
        let tags = values.tagNames ?? []
        let description = isFolder
            ? "Folder"
            : (values.localizedTypeDescription ?? type?.localizedDescription ?? "File")
        let metadata = [
            description,
            url.pathExtension,
            tags.joined(separator: " "),
            values.creationDate?.ISO8601Format() ?? "",
            values.contentModificationDate?.ISO8601Format() ?? "",
            values.fileSize.map(String.init) ?? ""
        ]
        .filter { $0.isEmpty == false }
        .joined(separator: "\n")
        return FileIndexRecord(
            path: url.standardizedFileURL.path,
            rootPath: root.standardizedFileURL.path,
            name: values.name ?? url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().path,
            kind: isFolder ? .folder : .file,
            category: category(for: type, isFolder: isFolder),
            contentTypeIdentifier: type?.identifier,
            contentTypeDescription: description,
            byteCount: values.fileSize.map(Int64.init),
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            lastUsedAt: values.contentAccessDate,
            tags: tags,
            metadataText: metadata,
            contentText: "",
            scanGeneration: generation
        )
    }

    private nonisolated static func category(for type: UTType?, isFolder: Bool) -> FileSearchCategory {
        if isFolder { return .folders }
        if type?.conforms(to: .image) == true { return .images }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .archive) == true { return .archives }
        if type?.conforms(to: .sourceCode) == true { return .sourceCode }
        if type?.conforms(to: .text) == true
            || type?.conforms(to: .pdf) == true
            || type?.conforms(to: .presentation) == true
            || type?.conforms(to: .spreadsheet) == true {
            return .documents
        }
        return .all
    }

    private nonisolated static func shouldIgnore(url: URL, values: URLResourceValues) -> Bool {
        let name = values.name ?? url.lastPathComponent
        if name.hasSuffix(".tmp") || name.hasSuffix(".temp") || name == ".DS_Store" { return true }
        return values.isDirectory == true && ignoredDirectoryNames.contains(name)
    }

    private nonisolated static func removeNestedScopes(_ scopes: [URL]) -> [URL] {
        let sorted = scopes.map(\.standardizedFileURL).sorted { $0.path.count < $1.path.count }
        var roots: [URL] = []
        for scope in sorted where mostSpecificRoot(containing: scope, scopes: roots) == nil {
            roots.append(scope)
        }
        return roots
    }

    private nonisolated static func mostSpecificRoot(containing url: URL, scopes: [URL]) -> URL? {
        scopes
            .filter { root in
                let rootPath = root.standardizedFileURL.path
                let path = url.standardizedFileURL.path
                return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/")
            }
            .max { $0.path.count < $1.path.count }
    }
}
