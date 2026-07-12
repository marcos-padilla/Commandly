import Foundation

struct CSVPreviewContent: Sendable, Equatable {
    let headers: [String]
    let rows: [[String]]
    let isTruncated: Bool

    nonisolated init(headers: [String], rows: [[String]], isTruncated: Bool) {
        self.headers = headers
        self.rows = rows
        self.isTruncated = isTruncated
    }
}

enum CSVPreviewError: Error, Sendable, Equatable {
    case unreadable
    case invalidEncoding
    case empty
}

enum CSVPreviewLoader {
    nonisolated private static let maximumBytes = 512 * 1_024
    nonisolated private static let maximumRows = 60
    nonisolated private static let maximumColumns = 20

    nonisolated static func load(url: URL) async throws -> CSVPreviewContent {
        let task = Task.detached(priority: .userInitiated) {
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: url)
            } catch {
                throw CSVPreviewError.unreadable
            }
            defer { try? handle.close() }
            let data: Data
            do {
                data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            } catch {
                throw CSVPreviewError.unreadable
            }
            guard Task.isCancelled == false else { throw CancellationError() }
            let wasByteLimited = data.count > maximumBytes
            let previewData = wasByteLimited ? data.prefix(maximumBytes) : data[...]
            guard let text = String(data: previewData, encoding: .utf8) else {
                throw CSVPreviewError.invalidEncoding
            }
            return try CSVPreviewParser.parse(
                text,
                maximumRows: maximumRows,
                maximumColumns: maximumColumns,
                wasByteLimited: wasByteLimited
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

enum CSVPreviewParser {
    nonisolated static func parse(
        _ text: String,
        maximumRows: Int = 60,
        maximumColumns: Int = 20,
        wasByteLimited: Bool = false
    ) throws -> CSVPreviewContent {
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = text.startIndex
        var isTruncated = wasByteLimited

        func appendField() {
            if row.count < maximumColumns {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                isTruncated = true
            }
            field = ""
        }

        func appendRow() {
            appendField()
            if row.contains(where: { $0.isEmpty == false }) {
                if records.count <= maximumRows {
                    records.append(row)
                } else {
                    isTruncated = true
                }
            }
            row = []
        }

        while index < text.endIndex {
            guard Task.isCancelled == false else { throw CancellationError() }
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if isInsideQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                isInsideQuotes.toggle()
            } else if character == ",", isInsideQuotes == false {
                appendField()
            } else if (character == "\n" || character == "\r" || character == "\r\n"),
                      isInsideQuotes == false {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                appendRow()
                if records.count > maximumRows {
                    isTruncated = true
                    break
                }
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if field.isEmpty == false || row.isEmpty == false {
            appendRow()
        }
        guard let headers = records.first, headers.isEmpty == false else {
            throw CSVPreviewError.empty
        }
        let columnCount = headers.count
        let rows = records.dropFirst().prefix(maximumRows).map { record in
            if record.count >= columnCount { return Array(record.prefix(columnCount)) }
            return record + Array(repeating: "", count: columnCount - record.count)
        }
        return CSVPreviewContent(
            headers: headers,
            rows: rows,
            isTruncated: isTruncated || records.count > maximumRows + 1
        )
    }
}
