import Foundation

struct MarkdownParseResult {
    let bodyHTML: String
    let outline: [MarkdownOutlineEntry]
    let frontMatter: [MarkdownFrontMatterEntry]
}

struct MarkdownParser {
    let configuration: MarkdownPreviewConfiguration
    let localImageDataURLs: [String: String]

    private var outline: [MarkdownOutlineEntry] = []
    private var usedAnchors: [String: Int] = [:]
    private var footnoteDefinitions: [(identifier: String, text: String)] = []
    private var footnoteNumbers: [String: Int] = [:]
    private var linkDefinitions: [String: String] = [:]

    init(configuration: MarkdownPreviewConfiguration, localImageDataURLs: [String: String]) {
        self.configuration = configuration
        self.localImageDataURLs = Self.sanitizedImages(localImageDataURLs)
    }

    mutating func parse(_ markdown: String) -> MarkdownParseResult {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let extracted = MarkdownFrontMatterParser.extract(from: normalized)
        let lines = extractLinkDefinitions(
            from: extractFootnotes(from: extracted.body.components(separatedBy: "\n"))
        )
        let body = renderBlocks(lines) + renderFootnotes()
        return MarkdownParseResult(bodyHTML: body, outline: outline, frontMatter: extracted.entries)
    }

    private mutating func renderBlocks(_ lines: [String]) -> String {
        var html: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(in: trimmed) {
                let block = collectFence(lines: lines, start: index, fence: fence)
                html.append(renderFence(language: block.language, source: block.source))
                index = block.nextIndex
                continue
            }

            if configuration.enablesMath, configuration.mathMode == .styledText,
               let math = collectDisplayMath(lines: lines, start: index) {
                html.append("<div class=\"math math-display\" role=\"math\">\(MarkdownHTML.escapeText(math.source))</div>")
                index = math.nextIndex
                continue
            }

            if let heading = atxHeading(line) {
                html.append(renderHeading(level: heading.level, title: heading.title))
                index += 1
                continue
            }

            if index + 1 < lines.count, let level = setextLevel(lines[index + 1]), !trimmed.isEmpty {
                html.append(renderHeading(level: level, title: trimmed))
                index += 2
                continue
            }

            if isThematicBreak(trimmed) {
                html.append("<hr>")
                index += 1
                continue
            }

            if configuration.enablesTables,
               index + 1 < lines.count,
               isTableDelimiter(lines[index + 1]) {
                let table = collectTable(lines: lines, start: index)
                html.append(table.html)
                index = table.nextIndex
                continue
            }

            if parseListItem(line) != nil {
                let list = collectList(lines: lines, start: index)
                html.append(list.html)
                index = list.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = collectQuote(lines: lines, start: index)
                html.append(quote.html)
                index = quote.nextIndex
                continue
            }

            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                var codeLines: [String] = []
                while index < lines.count {
                    if lines[index].hasPrefix("    ") {
                        codeLines.append(String(lines[index].dropFirst(4)))
                    } else if lines[index].hasPrefix("\t") {
                        codeLines.append(String(lines[index].dropFirst()))
                    } else if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        codeLines.append("")
                    } else {
                        break
                    }
                    index += 1
                }
                html.append(renderCode(source: codeLines.joined(separator: "\n"), language: ""))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if !paragraphLines.isEmpty, isBlockStart(lines: lines, index: index) { break }
                paragraphLines.append(candidate)
                index += 1
            }
            html.append("<p>\(renderParagraphLines(paragraphLines))</p>")
        }
        return html.joined(separator: "\n")
    }

    private mutating func renderHeading(level: Int, title: String) -> String {
        let plainTitle = MarkdownHTML.plainInlineText(title)
        let baseAnchor = MarkdownHTML.slug(plainTitle)
        let occurrence = usedAnchors[baseAnchor, default: 0]
        usedAnchors[baseAnchor] = occurrence + 1
        let anchor = occurrence == 0 ? baseAnchor : "\(baseAnchor)-\(occurrence + 1)"
        outline.append(MarkdownOutlineEntry(level: level, title: plainTitle, anchor: anchor))
        let renderedTitle = inlineRenderer.render(title)
        return "<h\(level) id=\"\(MarkdownHTML.escapeAttribute(anchor))\" data-outline-level=\"\(level)\"><a class=\"heading-anchor\" href=\"#\(MarkdownHTML.escapeAttribute(anchor))\" aria-label=\"Link to this section\">#</a>\(renderedTitle)</h\(level)>"
    }

    private func renderParagraphLines(_ lines: [String]) -> String {
        lines.enumerated().map { index, line in
            var content = line
            let hardBreak = content.hasSuffix("  ")
            if hardBreak { content.removeLast(2) }
            let rendered = inlineRenderer.render(content)
            guard index < lines.count - 1 else { return rendered }
            return rendered + ((configuration.softBreaksAsLineBreaks || hardBreak) ? "<br>" : " ")
        }.joined()
    }

    private var inlineRenderer: MarkdownInlineRenderer {
        MarkdownInlineRenderer(
            configuration: configuration,
            localImageDataURLs: localImageDataURLs,
            footnoteNumbers: footnoteNumbers,
            linkDefinitions: linkDefinitions
        )
    }

    private mutating func extractLinkDefinitions(from lines: [String]) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"^ {0,3}\[([^\]^][^\]]{0,63})\]:\s*(<[^>\r\n]+>|\S+)(?:\s+(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|\([^\)\r\n]*\)))?\s*$"#
        ) else {
            return lines
        }
        var body: [String] = []
        var activeFence: Fence?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = activeFence {
                body.append(line)
                if trimmed.prefix(while: { $0 == fence.marker }).count >= fence.count,
                   trimmed.drop(while: { $0 == fence.marker })
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                    activeFence = nil
                }
                continue
            }
            if let fence = fenceStart(in: trimmed) {
                activeFence = fence
                body.append(line)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard linkDefinitions.count < 128,
                  let match = expression.firstMatch(in: line, range: range),
                  let identifierRange = Range(match.range(at: 1), in: line),
                  let destinationRange = Range(match.range(at: 2), in: line) else {
                body.append(line)
                continue
            }
            let identifier = normalizedReferenceLabel(String(line[identifierRange]))
            var destination = String(line[destinationRange])
            if destination.hasPrefix("<"), destination.hasSuffix(">") {
                destination.removeFirst()
                destination.removeLast()
            }
            if linkDefinitions[identifier] == nil {
                linkDefinitions[identifier] = destination
            }
        }
        return body
    }

    private func normalizedReferenceLabel(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private mutating func extractFootnotes(from lines: [String]) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"^\[\^([A-Za-z0-9_-]{1,64})\]:\s*(.*)$"#
        ) else {
            return lines
        }
        var body: [String] = []
        var activeFence: Fence?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = activeFence {
                body.append(line)
                if trimmed.prefix(while: { $0 == fence.marker }).count >= fence.count,
                   trimmed.drop(while: { $0 == fence.marker })
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                    activeFence = nil
                }
                continue
            }
            if let fence = fenceStart(in: trimmed) {
                activeFence = fence
                body.append(line)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard footnoteDefinitions.count < 128,
                  let match = expression.firstMatch(in: line, range: range),
                  let identifierRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line) else {
                body.append(line)
                continue
            }
            let identifier = line[identifierRange].lowercased()
            guard footnoteNumbers[identifier] == nil else { continue }
            footnoteNumbers[identifier] = footnoteDefinitions.count + 1
            footnoteDefinitions.append((identifier, String(line[textRange])))
        }
        return body
    }

    private func renderFootnotes() -> String {
        guard footnoteDefinitions.isEmpty == false else { return "" }
        let items = footnoteDefinitions.enumerated().map { offset, definition in
            let anchor = MarkdownHTML.escapeAttribute(definition.identifier)
            return "<li id=\"footnote-\(anchor)\"><span class=\"footnote-number\">\(offset + 1).</span> \(inlineRenderer.render(definition.text)) <a class=\"footnote-backlink\" href=\"#footnote-reference-\(anchor)\" aria-label=\"Back to footnote reference\">↩</a></li>"
        }.joined()
        return "<section class=\"footnotes\" aria-label=\"Footnotes\"><hr><ol>\(items)</ol></section>"
    }

    private func atxHeading(_ line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(hashes),
              trimmed.dropFirst(hashes).first?.isWhitespace == true else { return nil }
        var title = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        return (hashes, title)
    }

    private func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private func isBlockStart(lines: [String], index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if fenceStart(in: trimmed) != nil || atxHeading(lines[index]) != nil || isThematicBreak(trimmed) ||
            parseListItem(lines[index]) != nil || trimmed.hasPrefix(">") || trimmed == "$$" ||
            lines[index].hasPrefix("    ") || lines[index].hasPrefix("\t") {
            return true
        }
        return configuration.enablesTables && index + 1 < lines.count && isTableDelimiter(lines[index + 1])
    }

    private func isThematicBreak(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private struct Fence {
        let marker: Character
        let count: Int
        let language: String
    }

    private func fenceStart(in trimmed: String) -> Fence? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        let rawLanguage = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let language = String(rawLanguage.prefix(40)).filter { $0.isLetter || $0.isNumber || "+#_-".contains($0) }
        return Fence(marker: marker, count: count, language: language.lowercased())
    }

    private func collectFence(
        lines: [String],
        start: Int,
        fence: Fence
    ) -> (language: String, source: String, nextIndex: Int) {
        var source: [String] = []
        var index = start + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.prefix(while: { $0 == fence.marker }).count >= fence.count,
               trimmed.drop(while: { $0 == fence.marker }).trimmingCharacters(in: .whitespaces).isEmpty {
                return (fence.language, source.joined(separator: "\n"), index + 1)
            }
            source.append(lines[index])
            index += 1
        }
        return (fence.language, source.joined(separator: "\n"), index)
    }

    private func renderFence(language: String, source: String) -> String {
        let diagramEnabled: Bool
        switch language {
        case "mermaid": diagramEnabled = configuration.enablesMermaid
        case "dot", "graphviz": diagramEnabled = configuration.enablesGraphviz
        case "vega", "vega-lite", "vegalite": diagramEnabled = configuration.enablesVega
        default: diagramEnabled = false
        }
        if diagramEnabled, configuration.diagramMode == .safePreview {
            if let diagram = MarkdownDiagramRenderer.render(language: language, source: source) {
                return diagram
            }
            return diagramFallback(language: language, source: source)
        }
        if language == "typst", configuration.enablesTypst {
            return "<figure class=\"math typst-fallback\"><figcaption>Typst notation (text preview)</figcaption><div role=\"math\">\(MarkdownHTML.escapeText(source))</div></figure>"
        }
        return renderCode(source: source, language: language)
    }

    private func diagramFallback(language: String, source: String) -> String {
        "<figure class=\"diagram diagram-fallback\" data-diagram-kind=\"\(MarkdownHTML.escapeAttribute(language))\"><figcaption>This diagram uses syntax outside the secure built-in preview subset. Its source is preserved below.</figcaption>\(renderCode(source: source, language: language))</figure>"
    }

    private func renderCode(source: String, language: String) -> String {
        let escapedLanguage = MarkdownHTML.escapeAttribute(language)
        let languageLabel = language.isEmpty ? "" : "<span class=\"code-language\">\(MarkdownHTML.escapeText(language))</span>"
        let code: String
        if configuration.showsLineNumbers {
            let lines = source.components(separatedBy: "\n")
            code = lines.enumerated().map { offset, line in
                let highlighted = MarkdownCodeHighlighter.highlight(line, language: language)
                return "<span class=\"code-line\" data-line=\"\(offset + 1)\"><span class=\"line-number\" aria-hidden=\"true\">\(offset + 1)</span><span class=\"line-content\">\(highlighted)</span></span>"
            }.joined(separator: "\n")
        } else {
            code = MarkdownCodeHighlighter.highlight(source, language: language)
        }
        return "<div class=\"code-container\">\(languageLabel)<pre class=\"code-block language-\(escapedLanguage)\" data-language=\"\(escapedLanguage)\"><code>\(code)</code></pre></div>"
    }

    private func collectDisplayMath(lines: [String], start: Int) -> (source: String, nextIndex: Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
            return (String(trimmed.dropFirst(2).dropLast(2)), start + 1)
        }
        guard trimmed == "$$" else { return nil }
        var content: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                return (content.joined(separator: "\n"), index + 1)
            }
            content.append(lines[index])
            index += 1
        }
        return nil
    }

    private func isTableDelimiter(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }

    private func collectTable(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        let headers = tableCells(lines[start])
        let delimiters = tableCells(lines[start + 1])
        let alignments = delimiters.map { delimiter -> String in
            let trimmed = delimiter.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") { return "center" }
            if trimmed.hasSuffix(":") { return "right" }
            return "left"
        }
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, lines[index].contains("|"),
              !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(tableCells(lines[index]))
            index += 1
        }
        let headerHTML = headers.enumerated().map { offset, cell in
            let alignment = alignments.indices.contains(offset) ? alignments[offset] : "left"
            return "<th class=\"align-\(alignment)\">\(inlineRenderer.render(cell.trimmingCharacters(in: .whitespaces)))</th>"
        }.joined()
        let rowsHTML = rows.map { cells in
            let content = headers.indices.map { offset in
                let cell = cells.indices.contains(offset) ? cells[offset] : ""
                let alignment = alignments.indices.contains(offset) ? alignments[offset] : "left"
                return "<td class=\"align-\(alignment)\">\(inlineRenderer.render(cell.trimmingCharacters(in: .whitespaces)))</td>"
            }.joined()
            return "<tr>\(content)</tr>"
        }.joined()
        return ("<div class=\"table-scroll\"><table><thead><tr>\(headerHTML)</tr></thead><tbody>\(rowsHTML)</tbody></table></div>", index)
    }

    private func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                current.append(character)
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells
    }

    private struct ListItem {
        let ordered: Bool
        let text: String
        let taskState: Bool?
    }

    private func parseListItem(_ line: String) -> ListItem? {
        guard let expression = try? NSRegularExpression(
            pattern: #"^\s*(?:(\d+)[\.)]|([-+*]))\s+(.+)$"#
        ),
        let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
        let textRange = Range(match.range(at: 3), in: line) else { return nil }
        var text = String(line[textRange])
        var taskState: Bool?
        if configuration.enablesTaskLists,
           let taskExpression = try? NSRegularExpression(pattern: #"^\[([ xX])\]\s+(.*)$"#),
           let taskMatch = taskExpression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let stateRange = Range(taskMatch.range(at: 1), in: text),
           let contentRange = Range(taskMatch.range(at: 2), in: text) {
            taskState = text[stateRange].lowercased() == "x"
            text = String(text[contentRange])
        }
        return ListItem(ordered: match.range(at: 1).location != NSNotFound, text: text, taskState: taskState)
    }

    private func collectList(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        guard let first = parseListItem(lines[start]) else { return ("", start + 1) }
        var items: [ListItem] = []
        var index = start
        while index < lines.count, let item = parseListItem(lines[index]), item.ordered == first.ordered {
            items.append(item)
            index += 1
        }
        let tag = first.ordered ? "ol" : "ul"
        let hasTasks = items.contains { $0.taskState != nil }
        let className = hasTasks ? " class=\"task-list\"" : ""
        let itemHTML = items.map { item in
            let checkbox: String
            if let completed = item.taskState {
                checkbox = "<input type=\"checkbox\" disabled\(completed ? " checked" : "") aria-label=\"\(completed ? "Completed" : "Not completed")\">"
            } else {
                checkbox = ""
            }
            return "<li\(item.taskState == nil ? "" : " class=\"task-item\"")>\(checkbox)\(inlineRenderer.render(item.text))</li>"
        }.joined()
        return ("<\(tag)\(className)>\(itemHTML)</\(tag)>", index)
    }

    private func collectQuote(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        var contents: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var content = String(trimmed.dropFirst())
            if content.hasPrefix(" ") { content.removeFirst() }
            contents.append(content)
            index += 1
        }

        let alertTypes = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]
        if configuration.enablesAlerts, let first = contents.first {
            let marker = first.trimmingCharacters(in: .whitespaces).uppercased()
            if alertTypes.contains(where: { marker == "[!\($0)]" }) {
                let type = marker.dropFirst(2).dropLast().lowercased()
                let title = type.prefix(1).uppercased() + type.dropFirst()
                let body = contents.dropFirst().map { inlineRenderer.render($0) }.joined(separator: "<br>")
                let alert = "<aside class=\"alert alert-\(type)\" role=\"note\"><div class=\"alert-title\">\(title)</div><div>\(body)</div></aside>"
                if configuration.collapsesBlockquotes {
                    return ("<details class=\"quote-details alert-details\"><summary>\(title)</summary>\(alert)</details>", index)
                }
                return (alert, index)
            }
        }

        let body = contents.map { inlineRenderer.render($0) }.joined(separator: "<br>")
        if configuration.collapsesBlockquotes {
            return ("<details class=\"quote-details\"><summary>Quoted passage</summary><blockquote>\(body)</blockquote></details>", index)
        }
        return ("<blockquote>\(body)</blockquote>", index)
    }

    private static func sanitizedImages(_ images: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        var totalCharacters = 0
        for key in images.keys.sorted() {
            guard let reference = MarkdownHTML.normalizedRelativeReference(key),
                  let dataURL = images[key],
                  let validURL = MarkdownHTML.validEmbeddedImageDataURL(dataURL),
                  totalCharacters + validURL.count <= 24_000_000 else { continue }
            result[reference] = validURL
            totalCharacters += validURL.count
        }
        return result
    }
}
