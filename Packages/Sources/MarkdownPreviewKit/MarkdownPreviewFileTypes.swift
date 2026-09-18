import Foundation

/// File extensions and content-type identifiers accepted by Markdown Preview.
public enum MarkdownPreviewFileTypes {
    /// Extensions are lowercase and do not include a leading period.
    public static let fileExtensions: [String] = [
        "md", "markdown", "mdown", "mdwn", "mkd", "mkdn", "mkdown",
        "mmd", "mdx", "rmd", "qmd", "mdoc", "mdc", "livemd",
    ]

    /// Known Markdown uniform type identifiers suitable for Quick Look declarations.
    public static let contentTypeIdentifiers: [String] = [
        "public.markdown",
        "net.daringfireball.markdown",
        "org.commonmark.markdown",
        "net.ia.markdown",
    ]

    /// Returns whether an extension, with or without a period, is supported.
    public static func supports(fileExtension: String) -> Bool {
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
            .lowercased()
        return fileExtensions.contains(normalized)
    }

    /// Returns whether a uniform type identifier is a known Markdown type.
    public static func supports(contentTypeIdentifier: String) -> Bool {
        contentTypeIdentifiers.contains { $0.caseInsensitiveCompare(contentTypeIdentifier) == .orderedSame }
    }

    /// Treats a standalone Mermaid document as one diagram while preserving pre-fenced input.
    public static func preparingForPreview(
        _ markdown: String,
        fileExtension: String
    ) -> String {
        guard fileExtension.lowercased() == "mmd" else { return markdown }

        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.hasPrefix("```mermaid"), !trimmed.hasPrefix("~~~mermaid") else {
            return markdown
        }
        return "```mermaid\n\(markdown)\n```"
    }
}
