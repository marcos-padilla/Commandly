import Foundation
import Infrastructure

nonisolated enum NotionWorkspaceParser {
    static func dictionary(_ data: Data) throws -> [String: Any] {
        guard data.count <= 4 * 1_024 * 1_024,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NotionWorkspaceError.invalidResponse }
        return value
    }
    static func identity(_ data: Data) throws -> NotionWorkspaceConnection {
        let value = try dictionary(data)
        guard value["type"] as? String == "bot", let rawID = value["id"] as? String, let id = UUID(uuidString: rawID),
              let bot = value["bot"] as? [String: Any] else { throw NotionWorkspaceError.invalidResponse }
        let name = (bot["workspace_name"] as? String) ?? (value["name"] as? String) ?? "Notion workspace"
        guard !name.isEmpty, name.utf8.count <= 512 else { throw NotionWorkspaceError.invalidResponse }
        return .init(id: id, name: name, revision: UUID())
    }
    static func page(_ data: Data) throws -> NotionWorkspacePage {
        let value = try dictionary(data)
        guard value["object"] as? String == "list", let results = value["results"] as? [[String: Any]],
              results.count <= 100, let more = value["has_more"] as? Bool else { throw NotionWorkspaceError.invalidResponse }
        let cursor = value["next_cursor"] as? String
        guard !more || (cursor?.isEmpty == false && (cursor?.utf8.count ?? 0) <= 2048) else { throw NotionWorkspaceError.invalidResponse }
        return .init(items: try results.filter { $0["archived"] as? Bool != true && $0["in_trash"] as? Bool != true }.map(item), nextCursor: more ? cursor : nil)
    }
    static func database(_ data: Data) throws -> NotionWorkspacePage {
        let value = try dictionary(data)
        guard let sources = value["data_sources"] as? [[String: Any]], sources.count <= 100 else { throw NotionWorkspaceError.invalidResponse }
        return .init(items: try sources.map { source in
            guard let raw = source["id"] as? String, let id = UUID(uuidString: raw) else { throw NotionWorkspaceError.invalidResponse }
            return .init(id: id, title: bounded(source["name"] as? String ?? "Untitled database"), kind: .dataSource, hasChildren: true)
        }, nextCursor: nil)
    }
    static func item(_ value: [String: Any]) throws -> NotionWorkspaceItem {
        guard let raw = value["id"] as? String, let id = UUID(uuidString: raw), let object = value["object"] as? String else { throw NotionWorkspaceError.invalidResponse }
        if object == "page" || object == "data_source" {
            var title = richText(value["title"])
            if let properties = value["properties"] as? [String: [String: Any]], let property = properties.values.first(where: { $0["type"] as? String == "title" }) {
                title = richText(property["title"])
            }
            return .init(id: id, title: title.isEmpty ? "Untitled" : title, kind: object == "page" ? .page : .dataSource, hasChildren: true)
        }
        guard object == "block", let type = value["type"] as? String else { throw NotionWorkspaceError.invalidResponse }
        let payload = value[type] as? [String: Any] ?? [:]
        if type == "child_page" || type == "child_database" {
            return .init(id: id, title: bounded(payload["title"] as? String ?? "Untitled"), kind: type == "child_page" ? .page : .database, hasChildren: true)
        }
        var text = richText(payload["rich_text"])
        if type == "table_row", let cells = payload["cells"] as? [Any] { text = bounded(cells.map(richText).joined(separator: "  |  ")) }
        if text.isEmpty { text = richText(payload["caption"]) }
        if type == "to_do" { text = (payload["checked"] as? Bool == true ? "☑ " : "☐ ") + text }
        let label = type.replacingOccurrences(of: "_", with: " ").capitalized
        return .init(id: id, title: text.isEmpty ? label : String(text.prefix(160)), kind: .block,
                     text: text.isEmpty ? "\(label) — open in Notion for its full presentation." : text,
                     hasChildren: value["has_children"] as? Bool == true)
    }
    private static func richText(_ value: Any?) -> String {
        guard let parts = value as? [[String: Any]] else { return "" }
        return bounded(parts.prefix(1000).map { ($0["plain_text"] as? String) ?? (($0["text"] as? [String: Any])?["content"] as? String) ?? "" }.joined())
    }
    private static func bounded(_ value: String) -> String { String(value.prefix(16_384)) }
}
