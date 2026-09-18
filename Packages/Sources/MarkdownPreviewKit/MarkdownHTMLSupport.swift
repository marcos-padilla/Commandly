import Foundation

enum MarkdownHTML {
    static func escapeText(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "`", with: "&#96;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#13;")
    }

    static func normalizedRelativeReference(_ value: String) -> String? {
        let withoutTitle = stripOptionalImageTitle(value)
        guard let decoded = fullyPercentDecoded(withoutTitle) else { return nil }
        var normalized = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("<"), normalized.hasSuffix(">"), normalized.count >= 2 {
            normalized.removeFirst()
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.hasPrefix("~"),
              !normalized.contains("\0"),
              URL(string: normalized)?.scheme == nil else {
            return nil
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else { return nil }
        return components.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
    }

    static func validEmbeddedImageDataURL(_ value: String) -> String? {
        // A character limit prevents an untrusted Markdown string from forcing an unbounded decode.
        guard value.count <= 8_000_000 else { return nil }
        let allowedPrefixes = [
            "data:image/png;base64,",
            "data:image/jpeg;base64,",
            "data:image/gif;base64,",
            "data:image/webp;base64,",
        ]
        guard let prefix = allowedPrefixes.first(where: { value.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let payload = value.dropFirst(prefix.count)
        guard !payload.isEmpty,
              payload.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=\r\n".contains($0)) }),
              Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters) != nil else {
            return nil
        }
        return value
    }

    static func safeLinkDestination(_ value: String, policy: MarkdownLinkPolicy) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") {
            let fragment = String(trimmed.dropFirst())
            guard fragment.allSatisfy({ $0.isLetter || $0.isNumber || "-_".contains($0) }) else {
                return nil
            }
            return trimmed
        }
        if policy == .webEmailAndRelativeMarkdown,
           let relativeDestination = safeRelativeMarkdownDestination(trimmed) {
            return relativeDestination
        }
        guard policy == .webAndEmail || policy == .webEmailAndRelativeMarkdown,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }
        if scheme == "http" || scheme == "https" {
            guard components.host?.isEmpty == false else { return nil }
        }
        return trimmed
    }

    private static func safeRelativeMarkdownDestination(_ value: String) -> String? {
        guard !value.hasPrefix("/"), !value.hasPrefix("~"), !value.contains("\\") else { return nil }
        let pieces = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var encodedPath = String(pieces[0])
        while encodedPath.hasPrefix("./") {
            encodedPath.removeFirst(2)
        }
        guard !encodedPath.isEmpty, !encodedPath.contains("?") else { return nil }
        guard let decodedPath = fullyPercentDecoded(encodedPath),
              !decodedPath.contains("\0"),
              !decodedPath.contains("\\"),
              !decodedPath.contains("?"),
              !decodedPath.contains("#"),
              !decodedPath.hasPrefix("~"),
              URL(string: decodedPath)?.scheme == nil else { return nil }
        let pathParts = decodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !pathParts.contains(".."), !pathParts.contains("."), !pathParts.contains("") else { return nil }
        let fileExtension = URL(fileURLWithPath: decodedPath).pathExtension
        guard MarkdownPreviewFileTypes.supports(fileExtension: fileExtension) else { return nil }
        if pieces.count == 2 {
            let fragment = String(pieces[1])
            guard !fragment.isEmpty,
                  fragment.allSatisfy({ $0.isLetter || $0.isNumber || "-_%".contains($0) }) else {
                return nil
            }
        }
        return pieces.count == 2 ? "\(encodedPath)#\(pieces[1])" : encodedPath
    }

    static func slug(_ title: String) -> String {
        var slug = ""
        var previousWasSeparator = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator && !slug.isEmpty {
                slug.append("-")
                previousWasSeparator = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "section" : slug
    }

    static func plainInlineText(_ value: String) -> String {
        var result = value
        let markers = ["**", "__", "~~", "`", "*", "_", "!"]
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        result = replaceMatches(in: result, pattern: #"\[([^\]]+)\]\([^\)]+\)"#, template: "$1")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replaceMatches(in value: String, pattern: String, template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }

    private static func stripOptionalImageTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(
            pattern: #"^(.+?)\s+(?:\"[^\"]*\"|'[^']*')$"#
        ),
        let match = expression.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ),
        let pathRange = Range(match.range(at: 1), in: trimmed) else {
            return trimmed
        }
        return String(trimmed[pathRange])
    }

    private static func fullyPercentDecoded(_ value: String) -> String? {
        var current = value
        for _ in 0 ..< 4 {
            guard let decoded = current.removingPercentEncoding else { return nil }
            if decoded == current { return current }
            current = decoded
        }
        guard current.removingPercentEncoding == current else { return nil }
        return current
    }
}
