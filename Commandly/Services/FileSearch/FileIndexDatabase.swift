import Foundation
import SearchKit
import SQLite3

struct FileIndexRecord: Sendable, Equatable {
    let path: String
    let rootPath: String
    let name: String
    let parentPath: String
    let kind: FileSearchItemKind
    let category: FileSearchCategory
    let contentTypeIdentifier: String?
    let contentTypeDescription: String
    let byteCount: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let lastUsedAt: Date?
    let tags: [String]
    let metadataText: String
    let contentText: String
    let scanGeneration: Int64

    var itemURL: URL { URL(fileURLWithPath: path) }
}

struct FileContentCandidate: Sendable, Equatable {
    let path: String
    let contentTypeIdentifier: String?
    let byteCount: Int64?
    let tags: [String]
    let metadataText: String
}

struct FileContentUpdate: Sendable {
    let path: String
    let text: String
    let metadata: String
    let tags: [String]
}

/// Actor-confined SQLite/FTS5 store for the local file index.
///
/// The connection never leaves this actor. WAL mode keeps short search reads responsive
/// while the scanner commits bounded write batches.
actor FileIndexDatabase {
    nonisolated let databaseURL: URL
    nonisolated let storageDirectoryURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        self.storageDirectoryURL = databaseURL.deletingLastPathComponent().standardizedFileURL
    }

    nonisolated func isStoragePath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let storagePath = storageDirectoryURL.path
        return standardized == storagePath || standardized.hasPrefix("\(storagePath)/")
    }

    func indexedItemCount() throws -> Int {
        try ensureOpen()
        let statement = try prepare("SELECT COUNT(*) FROM files")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FileSearchError.indexCorrupt }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func reset() throws {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
            }
        }
    }

    func lastFullScanDate() throws -> Date? {
        try ensureOpen()
        let statement = try prepare("SELECT value FROM settings WHERE key = 'last_full_scan'")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let value = text(at: 0, in: statement), let interval = TimeInterval(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    func markFullScanCompleted(at date: Date) throws {
        try ensureOpen()
        let statement = try prepare(
            "INSERT INTO settings(key, value) VALUES('last_full_scan', ?) " +
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        )
        defer { sqlite3_finalize(statement) }
        bind(String(date.timeIntervalSince1970), at: 1, in: statement)
        try stepDone(statement)
    }

    func replaceAuthorizedScopes(with rootPaths: [String]) throws {
        try ensureOpen()
        try transaction {
            let clear = try prepare("DELETE FROM authorized_scopes")
            defer { sqlite3_finalize(clear) }
            try stepDone(clear)

            let insert = try prepare("INSERT OR IGNORE INTO authorized_scopes(path) VALUES(?)")
            defer { sqlite3_finalize(insert) }
            for path in rootPaths {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                bind(path, at: 1, in: insert)
                try stepDone(insert)
            }

            try execute(
                "DELETE FROM files WHERE root_path NOT IN (SELECT path FROM authorized_scopes)"
            )
        }
    }

    func upsert(_ records: [FileIndexRecord]) throws {
        guard records.isEmpty == false else { return }
        try ensureOpen()
        try transaction {
            let upsert = try prepare(
                """
                INSERT INTO files(
                    path, root_path, name, parent_path, normalized_name, normalized_path,
                    kind, category, content_type, content_description, byte_count,
                    created_at, modified_at, last_used_at, tags, metadata, content,
                    scan_generation, content_indexed
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(path) DO UPDATE SET
                    root_path = excluded.root_path,
                    name = excluded.name,
                    parent_path = excluded.parent_path,
                    normalized_name = excluded.normalized_name,
                    normalized_path = excluded.normalized_path,
                    kind = excluded.kind,
                    category = excluded.category,
                    content_type = excluded.content_type,
                    content_description = excluded.content_description,
                    byte_count = excluded.byte_count,
                    created_at = excluded.created_at,
                    modified_at = excluded.modified_at,
                    last_used_at = excluded.last_used_at,
                    tags = excluded.tags,
                    metadata = excluded.metadata,
                    content = CASE
                        WHEN files.modified_at IS NOT excluded.modified_at THEN ''
                        ELSE files.content
                    END,
                    scan_generation = excluded.scan_generation,
                    content_indexed = CASE
                        WHEN files.modified_at IS NOT excluded.modified_at THEN 0
                        ELSE files.content_indexed
                    END
                """
            )
            defer { sqlite3_finalize(upsert) }
            for record in records {
                sqlite3_reset(upsert)
                sqlite3_clear_bindings(upsert)
                bind(record.path, at: 1, in: upsert)
                bind(record.rootPath, at: 2, in: upsert)
                bind(record.name, at: 3, in: upsert)
                bind(record.parentPath, at: 4, in: upsert)
                bind(FileIndexNormalizer.normalize(record.name), at: 5, in: upsert)
                bind(FileIndexNormalizer.normalize(record.path), at: 6, in: upsert)
                sqlite3_bind_int(upsert, 7, record.kind == .folder ? 1 : 0)
                bind(record.category.rawValue, at: 8, in: upsert)
                bind(record.contentTypeIdentifier, at: 9, in: upsert)
                bind(record.contentTypeDescription, at: 10, in: upsert)
                bind(record.byteCount, at: 11, in: upsert)
                bind(record.createdAt, at: 12, in: upsert)
                bind(record.modifiedAt, at: 13, in: upsert)
                bind(record.lastUsedAt, at: 14, in: upsert)
                bind(record.tags.joined(separator: "\n"), at: 15, in: upsert)
                bind(record.metadataText, at: 16, in: upsert)
                bind(record.contentText, at: 17, in: upsert)
                sqlite3_bind_int64(upsert, 18, record.scanGeneration)
                try stepDone(upsert)
            }
        }
    }

    func updateContent(_ updates: [FileContentUpdate]) throws {
        guard updates.isEmpty == false else { return }
        try ensureOpen()
        try transaction {
            let update = try prepare(
                "UPDATE files SET content = ?, metadata = ?, tags = ?, content_indexed = 1 WHERE path = ?"
            )
            defer { sqlite3_finalize(update) }
            for item in updates {
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                bind(item.text, at: 1, in: update)
                bind(item.metadata, at: 2, in: update)
                bind(item.tags.joined(separator: "\n"), at: 3, in: update)
                bind(item.path, at: 4, in: update)
                try stepDone(update)
            }
        }
    }

    func contentCandidates(limit: Int) throws -> [FileContentCandidate] {
        try ensureOpen()
        let statement = try prepare(
            """
            SELECT path, content_type, byte_count, tags, metadata
            FROM files
            WHERE kind = 0 AND content_indexed = 0
            ORDER BY COALESCE(last_used_at, modified_at, 0) DESC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))
        var candidates: [FileContentCandidate] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return candidates }
            guard result == SQLITE_ROW, let path = text(at: 0, in: statement) else {
                throw FileSearchError.indexCorrupt
            }
            candidates.append(
                FileContentCandidate(
                    path: path,
                    contentTypeIdentifier: text(at: 1, in: statement),
                    byteCount: optionalInt64(at: 2, in: statement),
                    tags: (text(at: 3, in: statement) ?? "").split(separator: "\n").map(String.init),
                    metadataText: text(at: 4, in: statement) ?? ""
                )
            )
        }
    }

    func contentCandidate(atPath path: String) throws -> FileContentCandidate? {
        try ensureOpen()
        let statement = try prepare(
            """
            SELECT path, content_type, byte_count, tags, metadata
            FROM files WHERE path = ? AND kind = 0 AND content_indexed = 0
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(path, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW, let path = text(at: 0, in: statement) else {
            return nil
        }
        return FileContentCandidate(
            path: path,
            contentTypeIdentifier: text(at: 1, in: statement),
            byteCount: optionalInt64(at: 2, in: statement),
            tags: (text(at: 3, in: statement) ?? "").split(separator: "\n").map(String.init),
            metadataText: text(at: 4, in: statement) ?? ""
        )
    }

    func removeStaleEntries(rootPath: String, generation: Int64) throws {
        try ensureOpen()
        try transaction {
            let removeFiles = try prepare(
                "DELETE FROM files WHERE root_path = ? AND scan_generation != ?"
            )
            defer { sqlite3_finalize(removeFiles) }
            bind(rootPath, at: 1, in: removeFiles)
            sqlite3_bind_int64(removeFiles, 2, generation)
            try stepDone(removeFiles)
        }
    }

    func remove(path: String, includingDescendants: Bool) throws {
        try ensureOpen()
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let predicate = includingDescendants ? "path = ? OR path LIKE ? ESCAPE '\\'" : "path = ?"
        try transaction {
            let removeFiles = try prepare("DELETE FROM files WHERE \(predicate)")
            defer { sqlite3_finalize(removeFiles) }
            bind(path, at: 1, in: removeFiles)
            if includingDescendants { bind("\(escaped)/%", at: 2, in: removeFiles) }
            try stepDone(removeFiles)
        }
    }

    func search(_ request: FileSearchRequest) throws -> [FileSearchItem] {
        try ensureOpen()
        let limit = max(0, request.query.limit ?? 100)
        guard limit > 0 else { return [] }
        let scopePaths = Array(request.scopeURLs.prefix(64)).map(\.standardizedFileURL.path)
        if request.query.isEmpty {
            return try recent(category: request.category, scopePaths: scopePaths, limit: limit)
        }

        let tokens = FileIndexNormalizer.tokens(request.query.text)
        guard tokens.isEmpty == false else { return [] }
        var resultsByPath: [String: FileSearchItem] = [:]
        var orderedPaths: [String] = []

        func append(_ items: [FileSearchItem]) {
            for item in items where resultsByPath[item.id] == nil {
                resultsByPath[item.id] = item
                orderedPaths.append(item.id)
            }
        }

        if request.includesFileNames {
            var fields = ["normalized_name"]
            if request.includesFilePaths { fields.append("normalized_path") }
            append(try ftsSearch(
                fields: fields,
                tokens: tokens,
                category: request.category,
                scopePaths: scopePaths,
                matchKind: .filename,
                limit: limit * 2
            ))
        }
        if request.includesTags {
            append(try ftsSearch(fields: ["tags"], tokens: tokens, category: request.category, scopePaths: scopePaths, matchKind: .tag, limit: limit))
        }
        if request.includesMetadata {
            append(try ftsSearch(fields: ["metadata"], tokens: tokens, category: request.category, scopePaths: scopePaths, matchKind: .metadata, limit: limit))
        }
        if request.includesFileContents {
            append(try ftsSearch(fields: ["content"], tokens: tokens, category: request.category, scopePaths: scopePaths, matchKind: .contents, limit: limit))
        }
        return orderedPaths.prefix(limit).compactMap { resultsByPath[$0] }
    }

    private func recent(
        category: FileSearchCategory,
        scopePaths: [String],
        limit: Int
    ) throws -> [FileSearchItem] {
        var predicates: [String] = []
        if category != .all { predicates.append("category = ?") }
        if scopePaths.isEmpty == false {
            predicates.append(Self.scopePredicate(pathColumn: "path", count: scopePaths.count))
        }
        let whereClause = predicates.isEmpty ? "" : "WHERE \(predicates.joined(separator: " AND "))"
        let statement = try prepare(
            "SELECT \(selectedColumns) FROM files \(whereClause) " +
                "ORDER BY COALESCE(last_used_at, modified_at, created_at, 0) DESC LIMIT ?"
        )
        defer { sqlite3_finalize(statement) }
        var binding: Int32 = 1
        if category != .all {
            bind(category.rawValue, at: binding, in: statement)
            binding += 1
        }
        binding = bindScopes(scopePaths, startingAt: binding, in: statement)
        sqlite3_bind_int(statement, binding, Int32(limit))
        return try readItems(from: statement, matchKind: .recent)
    }

    private func ftsSearch(
        fields: [String],
        tokens: [String],
        category: FileSearchCategory,
        scopePaths: [String],
        matchKind: FileSearchMatchKind,
        limit: Int
    ) throws -> [FileSearchItem] {
        let tokenExpressions = tokens.map { token in
            "(" + fields.map { "\($0):\(token)*" }.joined(separator: " OR ") + ")"
        }
        let expression = tokenExpressions.joined(separator: " AND ")
        let categoryClause = category == .all ? "" : "AND files.category = ?"
        let scopeClause = scopePaths.isEmpty
            ? ""
            : "AND \(Self.scopePredicate(pathColumn: "files.path", count: scopePaths.count))"
        let statement = try prepare(
            """
            SELECT \(selectedColumns)
            FROM file_fts JOIN files ON files.rowid = file_fts.rowid
            WHERE file_fts MATCH ? \(categoryClause) \(scopeClause)
            ORDER BY bm25(file_fts, 8.0, 4.0, 6.0, 2.0, 1.0),
                     COALESCE(files.last_used_at, files.modified_at, 0) DESC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        var binding: Int32 = 1
        bind(expression, at: binding, in: statement)
        binding += 1
        if category != .all {
            bind(category.rawValue, at: binding, in: statement)
            binding += 1
        }
        binding = bindScopes(scopePaths, startingAt: binding, in: statement)
        sqlite3_bind_int(statement, binding, Int32(limit))
        return try readItems(from: statement, matchKind: matchKind)
    }

    private static func scopePredicate(pathColumn: String, count: Int) -> String {
        "(" + Array(
            repeating: "(\(pathColumn) = ? OR \(pathColumn) LIKE ? ESCAPE '\\')",
            count: count
        ).joined(separator: " OR ") + ")"
    }

    private func bindScopes(
        _ scopePaths: [String],
        startingAt initialIndex: Int32,
        in statement: OpaquePointer
    ) -> Int32 {
        var index = initialIndex
        for path in scopePaths {
            bind(path, at: index, in: statement)
            index += 1
            bind("\(escapedLikeValue(path))/%", at: index, in: statement)
            index += 1
        }
        return index
    }

    private func escapedLikeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private var selectedColumns: String {
        "files.path, files.name, files.parent_path, files.kind, files.content_type, " +
            "files.content_description, files.byte_count, files.created_at, files.modified_at, " +
            "files.last_used_at, files.tags"
    }

    private func readItems(
        from statement: OpaquePointer,
        matchKind: FileSearchMatchKind
    ) throws -> [FileSearchItem] {
        var items: [FileSearchItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return items }
            guard result == SQLITE_ROW,
                  let path = text(at: 0, in: statement),
                  let name = text(at: 1, in: statement),
                  let parentPath = text(at: 2, in: statement),
                  let description = text(at: 5, in: statement) else {
                throw FileSearchError.indexCorrupt
            }
            let tags = (text(at: 10, in: statement) ?? "")
                .split(separator: "\n")
                .map(String.init)
            items.append(
                FileSearchItem(
                    url: URL(fileURLWithPath: path),
                    name: name,
                    parentPath: parentPath,
                    kind: sqlite3_column_int(statement, 3) == 1 ? .folder : .file,
                    contentTypeIdentifier: text(at: 4, in: statement),
                    contentTypeDescription: description,
                    byteCount: optionalInt64(at: 6, in: statement),
                    createdAt: date(at: 7, in: statement),
                    modifiedAt: date(at: 8, in: statement),
                    lastUsedAt: date(at: 9, in: statement),
                    tags: tags,
                    matchKind: matchKind
                )
            )
        }
    }

    private func ensureOpen() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw FileSearchError.indexUnavailable
        }
        database = connection
        do {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA temp_store = MEMORY")
            try execute("PRAGMA mmap_size = 67108864")
            let schemaVersion = try integerValue(for: "PRAGMA user_version")
            if schemaVersion != 2 {
                try execute("DROP TRIGGER IF EXISTS files_after_insert")
                try execute("DROP TRIGGER IF EXISTS files_after_delete")
                try execute("DROP TRIGGER IF EXISTS files_after_update")
                try execute("DROP TABLE IF EXISTS file_fts")
                try execute("DROP TABLE IF EXISTS files")
                try execute("DROP TABLE IF EXISTS settings")
                try execute("DROP TABLE IF EXISTS authorized_scopes")
            }
            try execute(
                """
                CREATE TABLE IF NOT EXISTS files(
                    path TEXT PRIMARY KEY NOT NULL,
                    root_path TEXT NOT NULL,
                    name TEXT NOT NULL,
                    parent_path TEXT NOT NULL,
                    normalized_name TEXT NOT NULL,
                    normalized_path TEXT NOT NULL,
                    kind INTEGER NOT NULL,
                    category TEXT NOT NULL,
                    content_type TEXT,
                    content_description TEXT NOT NULL,
                    byte_count INTEGER,
                    created_at REAL,
                    modified_at REAL,
                    last_used_at REAL,
                    tags TEXT NOT NULL DEFAULT '',
                    metadata TEXT NOT NULL DEFAULT '',
                    content TEXT NOT NULL DEFAULT '',
                    scan_generation INTEGER NOT NULL,
                    content_indexed INTEGER NOT NULL DEFAULT 0
                )
                """
            )
            try execute("CREATE INDEX IF NOT EXISTS files_recent ON files(last_used_at DESC, modified_at DESC)")
            try execute("CREATE INDEX IF NOT EXISTS files_category ON files(category)")
            try execute("CREATE INDEX IF NOT EXISTS files_root_generation ON files(root_path, scan_generation)")
            try execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS file_fts USING fts5(
                    normalized_name,
                    normalized_path,
                    tags,
                    metadata,
                    content,
                    content = 'files',
                    content_rowid = 'rowid',
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS files_after_insert AFTER INSERT ON files BEGIN
                    INSERT INTO file_fts(rowid, normalized_name, normalized_path, tags, metadata, content)
                    VALUES (new.rowid, new.normalized_name, new.normalized_path, new.tags, new.metadata, new.content);
                END
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS files_after_delete AFTER DELETE ON files BEGIN
                    INSERT INTO file_fts(file_fts, rowid, normalized_name, normalized_path, tags, metadata, content)
                    VALUES ('delete', old.rowid, old.normalized_name, old.normalized_path, old.tags, old.metadata, old.content);
                END
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS files_after_update AFTER UPDATE ON files
                WHEN old.normalized_name IS NOT new.normalized_name
                    OR old.normalized_path IS NOT new.normalized_path
                    OR old.tags IS NOT new.tags
                    OR old.metadata IS NOT new.metadata
                    OR old.content IS NOT new.content
                BEGIN
                    INSERT INTO file_fts(file_fts, rowid, normalized_name, normalized_path, tags, metadata, content)
                    VALUES ('delete', old.rowid, old.normalized_name, old.normalized_path, old.tags, old.metadata, old.content);
                    INSERT INTO file_fts(rowid, normalized_name, normalized_path, tags, metadata, content)
                    VALUES (new.rowid, new.normalized_name, new.normalized_path, new.tags, new.metadata, new.content);
                END
                """
            )
            try execute("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS authorized_scopes(path TEXT PRIMARY KEY)")
            if try hasColumn("content_indexed", in: "files") == false {
                try execute("ALTER TABLE files ADD COLUMN content_indexed INTEGER NOT NULL DEFAULT 0")
            }
            try execute("PRAGMA user_version = 2")
        } catch {
            sqlite3_close(connection)
            database = nil
            throw error
        }
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(at: 1, in: statement) == column { return true }
        }
        return false
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw FileSearchError.indexUnavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw FileSearchError.indexCorrupt
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw FileSearchError.indexUnavailable }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FileSearchError.indexCorrupt
        }
    }

    private func integerValue(for sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FileSearchError.indexCorrupt }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FileSearchError.indexCorrupt }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func bind(_ value: Int64?, at index: Int32, in statement: OpaquePointer) {
        if let value { sqlite3_bind_int64(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }

    private func bind(_ value: Date?, at index: Int32, in statement: OpaquePointer) {
        if let value { sqlite3_bind_double(statement, index, value.timeIntervalSince1970) } else { sqlite3_bind_null(statement, index) }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private func optionalInt64(at index: Int32, in statement: OpaquePointer) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private func date(at index: Int32, in statement: OpaquePointer) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    /// SQLite copies bound Swift strings before the call returns.
    private nonisolated static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
}

enum FileIndexNormalizer {
    nonisolated static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let separated = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }.joined()
        return separated.split(whereSeparator: \.isWhitespace)
        .map(String.init)
        .joined(separator: " ")
    }

    nonisolated static func tokens(_ value: String) -> [String] {
        Array(normalize(value).split(separator: " ").prefix(12)).map(String.init)
    }
}
