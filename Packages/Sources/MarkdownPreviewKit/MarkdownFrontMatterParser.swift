import Foundation

enum MarkdownFrontMatterParser {
    static func extract(
        from markdown: String
    ) -> (body: String, entries: [MarkdownFrontMatterEntry]) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (markdown, [])
        }
        guard let closing = lines.indices.dropFirst().prefix(300).first(where: {
            let marker = lines[$0].trimmingCharacters(in: .whitespaces)
            return marker == "---" || marker == "..."
        }) else {
            return (markdown, [])
        }

        var entries: [MarkdownFrontMatterEntry] = []
        var currentKey: String?
        var currentValues: [String] = []
        func appendCurrent() {
            guard let key = currentKey else { return }
            entries.append(MarkdownFrontMatterEntry(key: key, value: currentValues.joined(separator: "\n")))
        }
        for line in lines[1 ..< closing] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.first?.isWhitespace != true,
               !trimmed.hasPrefix("#"),
               let colon = line.firstIndex(of: ":") {
                appendCurrent()
                currentKey = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                currentValues = [String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)]
            } else if currentKey != nil, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                let continuation = trimmed.hasPrefix("-")
                    ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                    : trimmed
                currentValues.append(continuation)
            }
        }
        appendCurrent()
        let bodyStart = min(closing + 1, lines.count)
        return (lines[bodyStart...].joined(separator: "\n"), entries.filter { !$0.key.isEmpty })
    }
}
