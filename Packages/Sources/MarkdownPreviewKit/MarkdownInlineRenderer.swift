import Foundation

struct MarkdownInlineRenderer {
    let configuration: MarkdownPreviewConfiguration
    let localImageDataURLs: [String: String]
    var footnoteNumbers: [String: Int] = [:]
    var linkDefinitions: [String: String] = [:]

    func render(_ value: String) -> String {
        var working = value
        var tokens: [String] = []

        func store(_ html: String) -> String {
            let index = tokens.count
            tokens.append(html)
            return "\u{F0000}\(index)\u{F0001}"
        }

        func tokenize(_ pattern: String, transform: ([String]) -> String) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let matches = expression.matches(
                in: working,
                range: NSRange(working.startIndex..., in: working)
            )
            for match in matches.reversed() {
                guard let fullRange = Range(match.range(at: 0), in: working) else { continue }
                var captures: [String] = []
                for captureIndex in 1 ..< match.numberOfRanges {
                    if let range = Range(match.range(at: captureIndex), in: working) {
                        captures.append(String(working[range]))
                    } else {
                        captures.append("")
                    }
                }
                working.replaceSubrange(fullRange, with: store(transform(captures)))
            }
        }

        tokenize(#"`([^`\n]+)`"#) { captures in
            "<code class=\"inline-code\">\(MarkdownHTML.escapeText(captures[0]))</code>"
        }
        tokenize(#"!\[([^\]]*)\]\(([^\)\n]+)\)"#) { captures in
            renderImage(alt: captures[0], reference: captures[1])
        }
        tokenize(#"\[([^\]]+)\]\(([^\)\n]+)\)"#) { captures in
            renderLink(label: captures[0], destination: captures[1])
        }
        tokenize(#"\[([^\]]+)\]\[([^\]\n]*)\]"#) { captures in
            let identifier = captures[1].isEmpty ? captures[0] : captures[1]
            guard let destination = linkDefinitions[normalizedLabel(identifier)] else {
                return MarkdownHTML.escapeText("[\(captures[0])][\(captures[1])]")
            }
            return renderLink(label: captures[0], destination: destination)
        }
        tokenize(#"\[\^([A-Za-z0-9_-]{1,64})\]"#) { captures in
            let identifier = captures[0].lowercased()
            guard let number = footnoteNumbers[identifier] else {
                return MarkdownHTML.escapeText("[^\(captures[0])]")
            }
            let anchor = MarkdownHTML.escapeAttribute(identifier)
            return "<sup class=\"footnote-ref\" id=\"footnote-reference-\(anchor)\"><a href=\"#footnote-\(anchor)\" aria-label=\"Footnote \(number)\">\(number)</a></sup>"
        }
        if configuration.enablesMath, configuration.mathMode == .styledText {
            tokenize(#"(?<!\\)\$([^$\n]+)\$"#) { captures in
                "<span class=\"math math-inline\" role=\"math\">\(MarkdownHTML.escapeText(captures[0]))</span>"
            }
        }

        var html = MarkdownHTML.escapeText(working)
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"\*\*([^*\n]+)\*\*"#, template: "<strong>$1</strong>")
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"__([^_\n]+)__"#, template: "<strong>$1</strong>")
        if configuration.enablesStrikethrough {
            html = MarkdownHTML.replaceMatches(in: html, pattern: #"~~([^~\n]+)~~"#, template: "<del>$1</del>")
        }
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"==([^=\n]+)=="#, template: "<mark>$1</mark>")
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"(?<!\^)\^([^\^\n]+)\^(?!\^)"#, template: "<sup>$1</sup>")
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"(?<!~)~([^~\n]+)~(?!~)"#, template: "<sub>$1</sub>")
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, template: "<em>$1</em>")
        html = MarkdownHTML.replaceMatches(in: html, pattern: #"(?<!_)_([^_\n]+)_(?!_)"#, template: "<em>$1</em>")
        if configuration.enablesEmoji {
            for (code, emoji) in Self.emoji.sorted(by: { $0.key.count > $1.key.count }) {
                html = html.replacingOccurrences(of: ":\(code):", with: emoji)
            }
        }
        for (index, token) in tokens.enumerated() {
            html = html.replacingOccurrences(of: "\u{F0000}\(index)\u{F0001}", with: token)
        }
        return html
    }

    private func renderLink(label: String, destination: String) -> String {
        let escapedLabel = MarkdownHTML.escapeText(label)
        guard let safeDestination = MarkdownHTML.safeLinkDestination(destination, policy: configuration.linkPolicy) else {
            return "<span class=\"blocked-link\">\(escapedLabel)</span>"
        }
        return "<a href=\"\(MarkdownHTML.escapeAttribute(safeDestination))\" rel=\"noopener noreferrer\">\(escapedLabel)</a>"
    }

    private func renderImage(alt: String, reference: String) -> String {
        let escapedAlt = MarkdownHTML.escapeText(alt)
        guard configuration.imagePolicy == .embeddedDataOnly else {
            return "<span class=\"image-placeholder\" role=\"img\" aria-label=\"Image unavailable\">\(escapedAlt)</span>"
        }
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the native file boundary may create embedded image data. Accepting a data URL
        // directly from document text would bypass its count, byte, type, and file checks.
        let dataURL = MarkdownHTML.normalizedRelativeReference(trimmed)
            .flatMap { localImageDataURLs[$0] }
        guard let dataURL else {
            return "<span class=\"image-placeholder\" role=\"img\" aria-label=\"Image unavailable\">\(escapedAlt)</span>"
        }
        return "<img src=\"\(MarkdownHTML.escapeAttribute(dataURL))\" alt=\"\(MarkdownHTML.escapeAttribute(alt))\" loading=\"eager\" decoding=\"async\">"
    }

    private func normalizedLabel(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static let emoji: [String: String] = [
        "+1": "👍", "-1": "👎", "checkered_flag": "🏁", "eyes": "👀",
        "fire": "🔥", "heart": "❤️", "joy": "😂", "rocket": "🚀",
        "smile": "😄", "sparkles": "✨", "tada": "🎉", "thinking": "🤔",
        "thumbsup": "👍", "warning": "⚠️", "wave": "👋", "x": "❌",
    ]
}
